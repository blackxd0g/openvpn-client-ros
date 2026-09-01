**English** | [Русский](README_RU.md)

# openvpn-client-ros

> Multi-architecture OpenVPN client for MikroTik RouterOS containers.
> It receives routes pushed by the OpenVPN server, synchronizes RouterOS
> `/ip/route` and firewall address lists through REST, and reconnects automatically.

[![Docker Image](https://img.shields.io/badge/Docker%20Hub-blackxdog%2Fopenvpn--client--ros-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/blackxdog/openvpn-client-ros)
![Platforms](https://img.shields.io/badge/platform-armv7%20%7C%20arm64-success)
![RouterOS](https://img.shields.io/badge/RouterOS-7.23%20%7C%207.24-blue)

## ✨ Features

- 📦 One `latest` tag for `linux/arm/v7` and `linux/arm64`.
- ✅ Supports RB4011 (`arm`) and RB5009 (`arm64`).
- 🔄 Automatic OpenVPN reconnection with reasons written to the log.
- 🛣 Synchronizes pushed IPv4 networks with `/ip/route`.
- 🧾 Synchronizes the same networks with `/ip/firewall/address-list`.
- 🏷 Applies a container-specific ownership tag/comment.
- ♻️ Idempotent reconciliation: valid records are left unchanged.
- 🧹 Removes stale records and supports legacy ownership tags.
- 🔐 RouterOS REST over HTTPS with a dedicated self-signed CA.
- 🔒 File-based secrets keep passwords out of RouterOS container ENV logs.
- 🚀 Automated installation with one RouterOS script.
- 🪵 Logging levels: `error`, `warn`, `info`, and `debug`.

> [!NOTE]
> Tested on RouterOS 7.23 and 7.24. The `container` package and
> `device-mode container=yes` are required.

## ⚡ Quick start

1. Enable container support:

```routeros
/system/device-mode/print
/system/device-mode/update container=yes
```

Confirm the change using the physical button or a power cycle within the RouterOS time window.

2. Download [`deploy-routeros.rsc`](deploy-routeros.rsc) and set the credentials at the top:

```routeros
:local vpnUsername "VPN_LOGIN"
:local vpnPassword "VPN_PASSWORD"
:local apiPassword "LONG_RANDOM_API_PASSWORD"
```

3. Upload the complete OpenVPN profile to:

```text
usb1/openvpn-client-ros/config/client.ovpn
```

4. Upload and run the deployment script:

```routeros
/import file-name=deploy-routeros.rsc verbose=yes
```

5. Verify the result:

```routeros
/container/print
/log/print where topics~"container"
/ip/route/print where comment="ovpn-client-ros"
/ip/firewall/address-list/print where comment="ovpn-client-ros"
```

A successful synchronization ends with:

```text
[route-sync] [info] sync complete: destinations=17 routes=on address-list=on
```

## 🚀 Automated deployment

[`deploy-routeros.rsc`](deploy-routeros.rsc) is safe to run repeatedly. It:

- 📁 validates the profile and prepares storage;
- 🔌 creates a veth interface and an isolated `/30` network;
- 🔀 configures the RouterOS address and outbound NAT;
- 👤 creates a restricted RouterOS REST user;
- 🔏 creates a local CA and `www-ssl` certificate with an IP SAN;
- 🧱 limits REST access to the container IP;
- 💾 creates the `/config` mount and ENV list;
- 🔑 stores VPN and API passwords in files;
- 🐳 pulls `blackxdog/openvpn-client-ros:latest`;
- ▶️ creates the container and enables startup on boot.

| Variable | Default | Purpose |
|---|---:|---|
| `containerName` | `ovpn-client-ros` | Container name and default tag |
| `imageName` | `blackxdog/openvpn-client-ros:latest` | Docker image |
| `routerAddress` | `192.168.255.9/30` | RouterOS veth address |
| `containerAddress` | `192.168.255.10/30` | Container address |
| `storageRoot` | `usb1/openvpn-client-ros` | Container storage |
| `routeTable` | `main` | RouterOS routing table |
| `addressListName` | empty | Empty means container name |
| `routeTag` | empty | Empty means container name |
| `logLevel` | `info` | Container log level |
| `recreateContainer` | `true` | Recreate an existing container |

> [!IMPORTANT]
> Check the storage path and make sure the selected `/30` does not overlap
> any existing router network before importing the script.

### 📜 Complete deployment script

Expand the block, copy it to `deploy-routeros.rsc`, and replace the three
`CHANGE_ME_*` values before importing it.

<details>
<summary><strong>Show deploy-routeros.rsc</strong></summary>

```routeros
# Automated deployment for RouterOS 7.23/7.24.
# Upload the complete profile to usb1/openvpn-client-ros/config/client.ovpn first.
# Edit the three credentials below before importing this file.

:local vpnUsername "CHANGE_ME_VPN_USERNAME"
:local vpnPassword "CHANGE_ME_VPN_PASSWORD"
:local apiPassword "CHANGE_ME_API_PASSWORD_ALNUM"

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

:if (($vpnUsername = "CHANGE_ME_VPN_USERNAME") or ($vpnPassword = "CHANGE_ME_VPN_PASSWORD")) do={
    :error "Set vpnUsername and vpnPassword at the top of deploy-routeros.rsc"
}
:if ($apiPassword = "CHANGE_ME_API_PASSWORD_ALNUM") do={
    :error "Set apiPassword at the top of deploy-routeros.rsc"
}

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
```

</details>

## 🌐 Traffic flow

```text
LAN client
    │
    ▼
RouterOS route
    │ gateway = container veth IP
    ▼
container eth0 ── forwarding + masquerade ── tun0 ── VPN
```

The RouterOS gateway is the container veth address, not the remote tunnel gateway.

## 🧱 Supported architectures

| MikroTik family | RouterOS arch | Docker platform | Status |
|---|---|---|---|
| RB4011 and other ARMv7 devices | `arm` | `linux/arm/v7` | ✅ |
| RB5009 and other ARM64 devices | `arm64` | `linux/arm64` | ✅ |
| ARMv5 devices | `arm` | `linux/arm/v5` | ❌ |
| x86 / CHR | `x86_64` | `linux/amd64` | ❌ |

> [!TIP]
> RB4011 reports `arm`, not `arm64`; Docker Hub selects the `linux/arm/v7` manifest.

## 📁 Mount

Only one persistent mount is required:

```text
usb1/openvpn-client-ros/config  →  /config
```

It holds `client.ovpn`, referenced keys, an optional RouterOS CA, and password files.

## ⚙️ Environment variables

### 🔗 OpenVPN and supervisor

| ENV | Default | Purpose |
|---|---|---|
| `OVPN_CONFIG` | `/config/client.ovpn` | OpenVPN profile |
| `OVPN_USERNAME` | — | VPN username |
| `OVPN_PASSWORD` | — | VPN password; prefer the file option |
| `OVPN_PASSWORD_FILE` | — | VPN password file |
| `OVPN_DATA_CIPHERS` | image default | Cipher negotiation list |
| `OVPN_RESTART_DELAY` | `10` | Delay after a complete OpenVPN exit |
| `OVPN_LOG_LEVEL` | `info` | `error`, `warn`, `info`, or `debug` |
| `OVPN_VERB` | derived | Optional OpenVPN verbosity override |

### 🔐 RouterOS REST

| ENV | Default | Purpose |
|---|---|---|
| `OVPN_API_URL` | — | RouterOS REST base URL |
| `OVPN_API_USER` | — | Restricted REST username |
| `OVPN_API_PASSWORD` | — | REST password; prefer the file option |
| `OVPN_API_PASSWORD_FILE` | — | REST password file |
| `OVPN_API_VERIFY_TLS` | `true` | Verify RouterOS HTTPS certificate |
| `ROS_CA_FILE` | — | Optional custom CA file under `/config` |

### 🛣 Routes and address lists

| ENV | Default | Purpose |
|---|---|---|
| `OVPN_CONTAINER_NAME` | `ovpn-client-ros` | Identity and fallback tag |
| `OVPN_ROUTE_TAG` | empty | Comment; empty uses container name |
| `OVPN_LEGACY_TAGS` | empty | Previous custom tags to clean up |
| `OVPN_SYNC_ROUTES` | `true` | Synchronize `/ip/route` |
| `OVPN_SYNC_ADDRESS_LIST` | `true` | Synchronize firewall address list |
| `OVPN_ADDRESS_LIST_NAME` | empty | Empty uses container name |
| `OVPN_ROUTE_TABLE` | `main` | Target routing table |
| `OVPN_ROUTE_DISTANCE` | `1` | Generated route distance |
| `OVPN_ALLOW_DEFAULT_ROUTE` | `false` | Allow pushed `0.0.0.0/0` |
| `OVPN_EXTRA_ROUTES` | empty | Extra space-separated CIDRs |

Legacy `ROS_*` synchronization names remain accepted as compatibility aliases.

## ♻️ Reconciliation

On connect, startup, and reconnect, desired VPN networks are compared with RouterOS
records carrying the ownership tag. Valid records remain untouched, missing records
are created, and stale owned records are removed. Unrelated records are never modified.

## 🔄 Reconnect and logs

OpenVPN handles transient failures internally. If it exits, the supervisor removes
owned records, logs the exit code, waits `OVPN_RESTART_DELAY`, and starts it again.

```routeros
/log/print where topics~"container"
/container/print detail where name="ovpn-client-ros"
```

## 🐳 Build

```sh
docker buildx build --pull --no-cache \
  --platform linux/arm/v7,linux/arm64 \
  -t blackxdog/openvpn-client-ros:latest --push .
```

The image uses `alpine:latest` and installs the current OpenVPN package at build time.

## 🛡 Security

- Use dedicated VPN and RouterOS REST accounts.
- Restrict REST to the isolated container IP.
- Prefer `www-ssl`; plain `www` is only an isolated fallback.
- Use `OVPN_PASSWORD_FILE` and `OVPN_API_PASSWORD_FILE` for secrets.
- Never include private profiles, keys, or password files in the image.

## 💖 Support the project

If `openvpn-client-ros` saved you time or proved useful, you can
[support its development on Boosty](https://boosty.to/blackxdog/donate).

[![Support on Boosty](https://img.shields.io/badge/Boosty-support-f15f2c?logo=boosty&logoColor=white)](https://boosty.to/blackxdog/donate)

Your support helps test new RouterOS and OpenVPN releases, maintain ARMv7/ARM64
builds, and improve automatic route synchronization.

## 📄 Project files

| File | Purpose |
|---|---|
| [`Dockerfile`](Dockerfile) | Multi-architecture container image |
| [`entrypoint.sh`](entrypoint.sh) | OpenVPN supervisor |
| [`route_sync.py`](route_sync.py) | RouterOS reconciliation |
| [`deploy-routeros.rsc`](deploy-routeros.rsc) | Automated RouterOS installation |
| [`routeros.rsc`](routeros.rsc) | Manual RouterOS example |
| [`README_RU.md`](README_RU.md) | Russian documentation |
