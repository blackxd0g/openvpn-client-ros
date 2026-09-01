# Review addresses, disk path, image name and password before pasting.
# Intended for RouterOS 7.24 on ARMv7 or ARM64 (for example RB4011 or RB5009).

/interface/veth/add name=veth-ovpn address=172.31.255.2/30 gateway=172.31.255.1
/ip/address/add address=172.31.255.1/30 interface=veth-ovpn comment="OpenVPN container link"

# A deliberately limited account for route reconciliation through REST.
/user/group/add name=ovpn-route-sync policy=read,write,rest-api
/user/add name=ovpn-route-sync group=ovpn-route-sync password="CHANGE_ME_LONG_RANDOM_PASSWORD" address=172.31.255.2/32

# REST is exposed by www-ssl. Install/select a trusted certificate first.
# Do not enable plain HTTP in production.
/ip/service/set www-ssl disabled=no address=172.31.255.2/32

# Permit only the container to reach HTTPS/REST on the router.
/ip/firewall/filter/add chain=input action=accept protocol=tcp src-address=172.31.255.2 dst-port=443 comment="OpenVPN container to RouterOS REST"

/container/envs/add list=ovpn-env key=OVPN_CONFIG value=/config/client.ovpn
/container/envs/add list=ovpn-env key=OVPN_USERNAME value="CHANGE_ME_VPN_USERNAME"
/container/envs/add list=ovpn-env key=OVPN_PASSWORD value="CHANGE_ME_VPN_PASSWORD"
/container/envs/add list=ovpn-env key=OVPN_DATA_CIPHERS value=AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
/container/envs/add list=ovpn-env key=OVPN_RESTART_DELAY value=10
/container/envs/add list=ovpn-env key=OVPN_LOG_LEVEL value=info
/container/envs/add list=ovpn-env key=OVPN_API_URL value=https://172.31.255.1
/container/envs/add list=ovpn-env key=OVPN_API_USER value=ovpn-route-sync
/container/envs/add list=ovpn-env key=OVPN_API_PASSWORD value="CHANGE_ME_LONG_RANDOM_PASSWORD"
/container/envs/add list=ovpn-env key=OVPN_API_VERIFY_TLS value=false
/container/envs/add list=ovpn-env key=OVPN_GATEWAY value=172.31.255.2
/container/envs/add list=ovpn-env key=OVPN_ROUTE_TABLE value=main
/container/envs/add list=ovpn-env key=OVPN_ROUTE_DISTANCE value=1
/container/envs/add list=ovpn-env key=OVPN_CONTAINER_NAME value=ovpn-client-ros
/container/envs/add list=ovpn-env key=OVPN_ROUTE_TAG value=""
/container/envs/add list=ovpn-env key=OVPN_SYNC_ROUTES value=true
/container/envs/add list=ovpn-env key=OVPN_SYNC_ADDRESS_LIST value=true
/container/envs/add list=ovpn-env key=OVPN_ADDRESS_LIST_NAME value=""
/container/envs/add list=ovpn-env key=OVPN_ALLOW_DEFAULT_ROUTE value=false
/container/envs/add list=ovpn-env key=OVPN_EXTRA_ROUTES value=""

# Put client.ovpn and any files referenced by it in disk1/ovpn-config.
/container/mounts/add list=ovpn-config src=disk1/ovpn-config dst=/config

# Registry variant. Replace the image reference with your registry/tag.
/container/add name=ovpn-client remote-image=YOUR_REGISTRY/mikrotik-openvpn-client:latest interface=veth-ovpn root-dir=disk1/ovpn-root mountlists=ovpn-config envlist=ovpn-env user=0:0 logging=yes start-on-boot=yes

# Alternative for an image imported as a tar file. Use the ARMv7 archive on
# RB4011 and the ARM64 archive on RB5009:
# /container/add name=ovpn-client file=disk1/mikrotik-openvpn-client-arm64.tar interface=veth-ovpn root-dir=disk1/ovpn-root mountlists=ovpn-config envlist=ovpn-env user=0:0 logging=yes start-on-boot=yes
