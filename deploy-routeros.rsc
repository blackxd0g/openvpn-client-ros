# Automated deployment for RouterOS 7.23/7.24.
# Upload the complete profile to usb1/openvpn-client-ros/config/client.ovpn first.
# Run this file from an interactive RouterOS terminal.

:local vpnUsername ""
:local vpnPassword ""
:local apiPassword [:rndstr from="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" length=40]

:local containerName "ovpn-client-ros"
:local imageName "registry-1.docker.io/blackxdog/openvpn-client-ros:latest"
:local envList "OVPN-CLIENT-ROS"
:local mountList "ovpn-client-ros-config"
:local vethName "veth-ovpn-client"
:local routerAddress "192.168.255.9/30"
:local containerAddress "192.168.255.10/30"
:local routerIP "192.168.255.9"
:local containerIP "192.168.255.10"
:local linkNetwork "192.168.255.8/30"
:local storageRoot "usb1/openvpn-client-ros"
:local profilePath "usb1/openvpn-client-ros/config/client.ovpn"
:local routeTable "main"
:local addressListName ""
:local routeTag ""
:local logLevel "info"
:local recreateContainer true

:put "[ovpn-deploy] Enter VPN login:"
:set vpnUsername [/terminal ask]
:if ([:len $vpnUsername] = 0) do={ :error "VPN login cannot be empty" }
:put "[ovpn-deploy] Enter VPN password (input may be visible in the terminal):"
:set vpnPassword [/terminal ask]
:if ([:len $vpnPassword] = 0) do={ :error "VPN password cannot be empty" }
:put "[ovpn-deploy] RouterOS REST API password generated automatically"

:put "[ovpn-deploy] preparing directories"
:if ([:len [/file find where name=$storageRoot and type="directory"]] = 0) do={
    /file add name=$storageRoot type=directory
}
:if ([:len [/file find where name=($storageRoot . "/config") and type="directory"]] = 0) do={
    /file add name=($storageRoot . "/config") type=directory
}

:if ([:len [/file find where name=$profilePath]] = 0) do={
    :error ("OpenVPN profile is missing: " . $profilePath)
}

:put "[ovpn-deploy] configuring veth and gateway"
:local vethId [/interface/veth find where name=$vethName]
:if ([:len $vethId] = 0) do={
    /interface/veth add name=$vethName address=$containerAddress gateway=$routerIP comment=$containerName
} else={
    /interface/veth set $vethId address=$containerAddress gateway=$routerIP comment=$containerName
}

:local addressId [/ip/address find where comment=$containerName and interface=$vethName]
:if ([:len $addressId] = 0) do={
    /ip/address add address=$routerAddress interface=$vethName comment=$containerName
} else={
    /ip/address set $addressId address=$routerAddress interface=$vethName comment=$containerName
}

:put "[ovpn-deploy] configuring NAT and REST firewall access"
:local natId [/ip/firewall/nat find where comment=($containerName . " outbound")]
:if ([:len $natId] = 0) do={
    /ip/firewall/nat add chain=srcnat action=masquerade src-address=$linkNetwork out-interface-list=WAN comment=($containerName . " outbound")
} else={
    /ip/firewall/nat set $natId chain=srcnat action=masquerade src-address=$linkNetwork out-interface-list=WAN disabled=no
}

:local filterId [/ip/firewall/filter find where comment=($containerName . " REST API")]
:if ([:len $filterId] = 0) do={
    /ip/firewall/filter add chain=input action=accept protocol=tcp src-address=$containerIP dst-port=80,443 place-before=0 comment=($containerName . " REST API")
} else={
    /ip/firewall/filter set $filterId chain=input action=accept protocol=tcp src-address=$containerIP dst-port=80,443 disabled=no
}

:put "[ovpn-deploy] configuring restricted REST account"
:local apiGroup "api-ovpn-routes"
:local apiUser "api-ovpn-client"
:local groupId [/user/group find where name=$apiGroup]
:if ([:len $groupId] = 0) do={
    /user/group add name=$apiGroup policy=read,write,web,api,rest-api
} else={
    /user/group set $groupId policy=read,write,web,api,rest-api
}
:local userId [/user find where name=$apiUser]
:if ([:len $userId] = 0) do={
    /user add name=$apiUser group=$apiGroup password=$apiPassword address=($containerIP . "/32") comment=$containerName
} else={
    /user set $userId group=$apiGroup password=$apiPassword address=($containerIP . "/32") disabled=no comment=$containerName
}
:put "[ovpn-deploy] configuring self-signed REST HTTPS certificate"
:local restCertName ($containerName . "-rest")
:local restCaName ($containerName . "-rest-ca")
:local restCaId [/certificate find where name=$restCaName]
:if ([:len $restCaId] = 0) do={
    /certificate add name=$restCaName common-name=($containerName . " REST CA") key-usage=key-cert-sign,crl-sign days-valid=3650
    /certificate sign $restCaName
    /certificate set [find where name=$restCaName] trusted=yes
}
:local restCertId [/certificate find where name=$restCertName]
:if ([:len $restCertId] = 0) do={
    /certificate add name=$restCertName common-name=$routerIP subject-alt-name=("IP:" . $routerIP) key-usage=tls-server,digital-signature,key-encipherment days-valid=3650
    /certificate sign $restCertName ca=$restCaName
    /certificate set [find where name=$restCertName] trusted=yes
}
/ip/service set www-ssl disabled=no address=($containerIP . "/32") certificate=$restCertName tls-version=only-1.2
# Plain HTTP remains available only from the isolated container IP as a fallback.
/ip/service set www disabled=no address=($containerIP . "/32")

:put "[ovpn-deploy] configuring read-only profile mount"
:local oldMounts [/container/mounts find where list=$mountList]
:if ([:len $oldMounts] > 0) do={ /container/mounts remove $oldMounts }
/container/mounts add list=$mountList src=($storageRoot . "/config") dst="/config" mode=ro

:local ovpnSetEnv do={
    :local itemId [/container/envs find where list=$listName and key=$keyName]
    :if ([:len $itemId] = 0) do={
        /container/envs add list=$listName key=$keyName value=$keyValue
    } else={
        /container/envs set $itemId value=$keyValue
    }
}

:put "[ovpn-deploy] configuring OVPN environment"
:local vpnPasswordFile ($storageRoot . "/config/openvpn-password")
:local apiPasswordFile ($storageRoot . "/config/router-api-password")
:foreach secretSpec in={($vpnPasswordFile . "=" . $vpnPassword);($apiPasswordFile . "=" . $apiPassword)} do={
    :local separator [:find $secretSpec "="]
    :local secretPath [:pick $secretSpec 0 $separator]
    :local secretValue [:pick $secretSpec ($separator + 1) [:len $secretSpec]]
    :local secretId [/file find where name=$secretPath]
    :if ([:len $secretId] = 0) do={
        /file add name=$secretPath contents=$secretValue
    } else={
        /file set $secretId contents=$secretValue
    }
}
$ovpnSetEnv listName=$envList keyName="OVPN_CONFIG" keyValue="/config/client.ovpn"
$ovpnSetEnv listName=$envList keyName="OVPN_USERNAME" keyValue=$vpnUsername
:local oldVpnPasswordEnv [/container/envs find where list=$envList and key="OVPN_PASSWORD"]
:if ([:len $oldVpnPasswordEnv] > 0) do={ /container/envs remove $oldVpnPasswordEnv }
$ovpnSetEnv listName=$envList keyName="OVPN_PASSWORD_FILE" keyValue="/config/openvpn-password"
$ovpnSetEnv listName=$envList keyName="OVPN_DATA_CIPHERS" keyValue="AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC"
$ovpnSetEnv listName=$envList keyName="OVPN_RESTART_DELAY" keyValue="10"
$ovpnSetEnv listName=$envList keyName="OVPN_LOG_LEVEL" keyValue=$logLevel
$ovpnSetEnv listName=$envList keyName="OVPN_API_URL" keyValue=("https://" . $routerIP)
$ovpnSetEnv listName=$envList keyName="OVPN_API_USER" keyValue=$apiUser
:local oldApiPasswordEnv [/container/envs find where list=$envList and key="OVPN_API_PASSWORD"]
:if ([:len $oldApiPasswordEnv] > 0) do={ /container/envs remove $oldApiPasswordEnv }
$ovpnSetEnv listName=$envList keyName="OVPN_API_PASSWORD_FILE" keyValue="/config/router-api-password"
$ovpnSetEnv listName=$envList keyName="OVPN_API_VERIFY_TLS" keyValue="false"
$ovpnSetEnv listName=$envList keyName="OVPN_GATEWAY" keyValue=$containerIP
$ovpnSetEnv listName=$envList keyName="OVPN_CONTAINER_NAME" keyValue=$containerName
$ovpnSetEnv listName=$envList keyName="OVPN_ROUTE_TAG" keyValue=$routeTag
$ovpnSetEnv listName=$envList keyName="OVPN_SYNC_ROUTES" keyValue="true"
$ovpnSetEnv listName=$envList keyName="OVPN_SYNC_ADDRESS_LIST" keyValue="true"
$ovpnSetEnv listName=$envList keyName="OVPN_ADDRESS_LIST_NAME" keyValue=$addressListName
$ovpnSetEnv listName=$envList keyName="OVPN_ROUTE_TABLE" keyValue=$routeTable
$ovpnSetEnv listName=$envList keyName="OVPN_ROUTE_DISTANCE" keyValue="1"
$ovpnSetEnv listName=$envList keyName="OVPN_ALLOW_DEFAULT_ROUTE" keyValue="false"
$ovpnSetEnv listName=$envList keyName="OVPN_EXTRA_ROUTES" keyValue=""

/container/config set registry-url="https://registry-1.docker.io" tmpdir=($storageRoot . "/tmp")

:local containerId [/container find where name=$containerName]
:if (([:len $containerId] > 0) and $recreateContainer) do={
    :put "[ovpn-deploy] removing previous ovpn-client-ros container"
    /container stop $containerId
    :delay 3s
    /container remove $containerId
    :delay 2s
    :set containerId ""
}

:if ([:len $containerId] = 0) do={
    :put "[ovpn-deploy] downloading container image"
    /container add name=$containerName remote-image=$imageName interface=$vethName root-dir=($storageRoot . "/root") mountlists=$mountList envlists=$envList user="0:0" dns="1.1.1.1" logging=yes start-on-boot=yes comment=$containerName
}

:put "[ovpn-deploy] waiting for image extraction"
:local ready false
:for attempt from=1 to=120 do={
    :set containerId [/container find where name=$containerName]
    :if ([:len $containerId] > 0) do={
        :local currentStatus [/container get $containerId status]
        :if ($currentStatus = "stopped") do={
            :set ready true
            :break
        }
    }
    :if (!$ready) do={ :delay 5s }
}

:if (!$ready) do={
    :error "Container image was not ready after 10 minutes; check /container/print and /log/print"
}

:put "[ovpn-deploy] starting container"
/container start $containerId
:delay 5s
/container print detail where name=$containerName
:put "[ovpn-deploy] complete; inspect /log/print where topics~\"container\""
