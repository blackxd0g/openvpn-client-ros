# OpenVPN client container for MikroTik ARMv7 and ARM64

[English](README.md) | [Русский](README_RU.md)

Minimal OpenVPN client gateway targeting RouterOS 7.24 containers. When the tunnel comes up, it reads IPv4 routes pushed by the OpenVPN server and creates matching RouterOS routes through the RouterOS REST API. When the tunnel goes down, it removes only routes bearing its ownership comment.

Routes created using REST are static RouterOS records (`dynamic=false`). Their lifecycle is dynamic: the container reconciles them on every tunnel connect, reconnect, disconnect, and container startup.

## Network model

```text
LAN client -> RouterOS route -> 172.31.255.2 (container eth0)
           -> container forwarding + masquerade -> tun0 -> VPN
```

The RouterOS route gateway is the container's veth address, not the remote tunnel gateway.

## Supported MikroTik families

- RouterOS `arm64`, Docker platform `linux/arm64`: RB5009 and other ARM64 models.
- RouterOS `arm`, Docker platform `linux/arm/v7`: RB4011 and other ARMv7 models.
- ARMv5 is intentionally unsupported. This excludes devices that accept only ARM32v5 container images.
- x86 and CHR images are not published by this project.

RB4011 is reported by RouterOS as `arm`, not `arm64`, so it must use the `linux/arm/v7` manifest.

## Build a multi-architecture image

Build and push one tag containing ARMv7 and ARM64 manifests. RouterOS selects the matching manifest:

```sh
docker buildx build --pull --no-cache --platform linux/arm/v7,linux/arm64 -t YOUR_REGISTRY/mikrotik-openvpn-client:latest --push .
```

For direct upload, build a separate archive for each platform:

```sh
docker buildx build --pull --no-cache --platform linux/arm64 -t mikrotik-openvpn-client:arm64 --output type=docker,dest=mikrotik-openvpn-client-arm64.tar .
docker buildx build --pull --no-cache --platform linux/arm/v7 -t mikrotik-openvpn-client:armv7 --output type=docker,dest=mikrotik-openvpn-client-armv7.tar .
```

The Dockerfile uses `alpine:latest` and installs the unpinned `openvpn` package from that image's current stable repository. `--pull --no-cache` ensures every release build resolves the newest base image and package available at build time. The exact resolved OpenVPN version is printed to the RouterOS container log at startup.

## OpenVPN configuration

Place `client.ovpn` and all referenced certificate/key/auth files in `disk1/ovpn-config`. Paths inside `client.ovpn` must point under `/config`, for example:

```conf
client
dev tun
proto udp
remote vpn.example.net 1194
ca /config/ca.crt
cert /config/client.crt
key /config/client.key
auth-user-pass /config/auth.txt
verb 3
```

Do not put `script-security`, `route-up`, or `route-pre-down` in this file; the entrypoint supplies them. The image currently synchronizes IPv4 routes only.

### Supplied OpenVPN profile

The supplied profile is compatible with the image and can be uploaded unchanged as `disk1/ovpn-config/client.ovpn`. It uses a routed TUN tunnel, embedded CA/client certificate/private key, TLS 1.2 or newer, `tls-crypt-v2`, SHA-256 authentication, and AES-256-CBC. No private material from that profile is copied into this project.

The profile contains bare `auth-user-pass`. Set the credentials in the RouterOS container environment:

```routeros
/container/envs/add list=ovpn-env key=OVPN_USERNAME value="VPN_USERNAME"
/container/envs/add list=ovpn-env key=OVPN_PASSWORD value="VPN_PASSWORD"
```

At startup the entrypoint writes these values to an ephemeral `/run/openvpn/auth.txt` with mode `0600`, passes it to OpenVPN, and deletes it at shutdown. It exits with a clear error if either variable is absent. The values remain visible to sufficiently privileged RouterOS administrators, so use a dedicated VPN account and restrict RouterOS access. `OVPN_DATA_CIPHERS` includes modern AEAD ciphers and the profile's `AES-256-CBC`, which preserves compatibility with OpenVPN 2.6 negotiation.

## RouterOS installation

1. On RouterOS 7.24, install the matching `container` package and enable container device mode with `/system/device-mode/update container=yes` (physical confirmation is required).
2. Prefer external storage formatted for containers.
3. Install a certificate for `www-ssl`; use TLS verification in production.
4. Review and apply `routeros.rsc`.
5. Start the container and inspect `/log/print` and `/container/print`.

For an automated idempotent deployment, edit the three credentials at the top of `deploy-routeros.rsc`, upload the complete profile to the documented path, copy the script to the router, and run:

```routeros
/import file-name=deploy-routeros.rsc verbose=yes
```

The example initially sets `ROS_VERIFY_TLS=false` so a self-signed RouterOS certificate does not prevent first startup. For production, mount the issuing CA into `/config`, then set:

```routeros
/container/envs/set [find list=ovpn-env key=ROS_VERIFY_TLS] value=true
/container/envs/add list=ovpn-env key=ROS_CA_FILE value=/config/router-ca.crt
```

RouterOS REST uses `www-ssl`; MikroTik recommends HTTPS rather than the plain `www` service. REST route creation uses `PUT /rest/ip/route`, and removal uses the record ID returned by `GET /rest/ip/route`.

## Route controls

`OVPN_LEGACY_TAGS` accepts a comma- or space-separated list of previous route
tags. On every reconciliation, entries with the current tag, the container
name, or any legacy tag are replaced by entries carrying the current tag.
Changing `OVPN_ROUTE_TAG` is therefore automatic when the previous tag was the
container name; use `OVPN_LEGACY_TAGS` for any other historical custom tags.

- `ALLOW_DEFAULT_ROUTE=false` rejects a pushed `0.0.0.0/0` by default.
- `EXTRA_ROUTES="10.20.0.0/16 192.0.2.10/32"` adds explicit routes in addition to pushed routes.
- `ROS_ROUTE_TABLE=main` selects the RouterOS routing table. A non-main table must already exist with `fib=yes`.
- `ROS_ROUTE_DISTANCE=1` sets route distance.
- `OVPN_CONTAINER_NAME=ovpn-client-ros` is the default ownership tag. It is written to the `comment` field of routes and address-list entries.
- `OVPN_ROUTE_TAG` optionally overrides the ownership comment; an empty value uses `OVPN_CONTAINER_NAME`.
- `OVPN_SYNC_ROUTES=true|false` enables or disables creation of `/ip/route` entries. Default: `true`.
- `OVPN_SYNC_ADDRESS_LIST=true|false` enables or disables creation of firewall address-list entries. Default: `true`.
- `OVPN_ADDRESS_LIST_NAME` selects the RouterOS firewall address-list. If empty, its name is taken from `OVPN_CONTAINER_NAME`.
- `OVPN_ROUTE_TABLE=main` and `OVPN_ROUTE_DISTANCE=1` control generated routes.
- Older `ROS_*` synchronization ENV names remain accepted as compatibility aliases.
- `OVPN_RESTART_DELAY=10` controls the delay before restarting OpenVPN after a complete process exit.
- `OVPN_LOG_LEVEL=error|warn|info|debug` controls container logging. Default: `info`.
- `OVPN_VERB` optionally overrides the OpenVPN verbosity chosen from `LOG_LEVEL` (`1`, `2`, `3`, or `5`).

## Reconnect and logging

OpenVPN performs its normal in-process reconnect for transient transport failures. If OpenVPN exits completely, the entrypoint supervisor removes the managed RouterOS routes and owned address-list entries, writes the exit code and restart delay to the container log, and starts a new process. This repeats indefinitely until the container is stopped.

Keep `logging=yes` on the RouterOS container. OpenVPN output, route-sync actions, and timestamped supervisor lifecycle messages are written to stdout/stderr and appear in RouterOS logs. Useful commands are:

```routeros
/log/print where topics~"container"
/container/print detail where name="ovpn-client"
```

Typical supervisor messages contain the `[ovpn-supervisor]` marker. Route creation and removal messages contain `created RouterOS route` or `deleted RouterOS route`.

Only one persistent mount is required: `disk1/ovpn-config` to `/config`. The supplied profile embeds its CA, client certificate, private key, and tls-crypt-v2 material. VPN credentials are generated under the ephemeral `/run` filesystem from environment variables. A RouterOS REST CA file, if needed, can share `/config`.

To keep secrets out of RouterOS container startup logs while retaining
`logging=yes`, store them in the profile mount and use
`OVPN_PASSWORD_FILE=/config/openvpn-password` and
`OVPN_API_PASSWORD_FILE=/config/router-api-password`. File settings take
precedence over the corresponding plaintext environment variables.

The OpenVPN server endpoint must remain reachable through the WAN. If default routing is later enabled, add an explicit RouterOS host route for the VPN server through the normal WAN first.

## Security notes

- Replace the sample password before applying the script.
- Restrict `www-ssl` and the input firewall to the container address.
- `read,write,rest-api` is the smallest practical RouterOS policy combination for this REST workflow, but RouterOS policies are menu-wide rather than limited only to `/ip/route`.
- The container must run as root because OpenVPN, TUN, forwarding, and iptables require network administration privileges.
- Keep `client.ovpn`, keys, certificates, and `auth.txt` out of the image.

## Current assumptions

- RouterOS 7.24 on ARMv7 or ARM64. The same configuration targets RB4011 and RB5009; the registry manifest selects the correct image.
- `veth-ovpn` is directly connected as `172.31.255.0/30` and is not added to the LAN bridge.
- OpenVPN uses a routed `tun` tunnel, not TAP/bridging.
- Only server-pushed and explicitly configured destination routes are synchronized; policy rules and mangle rules remain under RouterOS administration.
