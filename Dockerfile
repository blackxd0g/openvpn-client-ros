FROM alpine:latest

ARG TARGETARCH
ARG TARGETVARIANT

RUN apk add --no-cache openvpn iptables python3 ca-certificates tini \
    && mkdir -p /config /run/openvpn

COPY entrypoint.sh route-hook.sh route_sync.py /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/route-hook.sh /usr/local/bin/route_sync.py

ENV OVPN_CONFIG=/config/client.ovpn \
    OVPN_DATA_CIPHERS=AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC \
    OVPN_RESTART_DELAY=10 \
    OVPN_LOG_LEVEL=info \
    OVPN_API_URL=http://172.31.255.1 \
    OVPN_API_VERIFY_TLS=false \
    OVPN_ROUTE_TABLE=main \
    OVPN_ROUTE_DISTANCE=1 \
    OVPN_CONTAINER_NAME=ovpn-client-ros \
    OVPN_ROUTE_TAG= \
    OVPN_SYNC_ROUTES=true \
    OVPN_SYNC_ADDRESS_LIST=true \
    OVPN_ADDRESS_LIST_NAME= \
    OVPN_ALLOW_DEFAULT_ROUTE=false \
    OVPN_EXTRA_ROUTES=""

LABEL org.opencontainers.image.title="MikroTik OpenVPN client gateway" \
      org.opencontainers.image.description="Latest Alpine OpenVPN client with RouterOS REST route synchronization for ARMv7 and ARM64"

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
