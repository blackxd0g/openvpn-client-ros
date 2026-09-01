# Compatibility result for the supplied OpenVPN profile

- Compatible platforms: ARMv7 (RB4011) and ARM64 (RB5009).
- Tunnel type: routed IPv4 TUN.
- OpenVPN package: latest version available in the current stable `alpine:latest` repository at image build time; the resolved version is logged at startup.
- TLS: minimum 1.2, server certificate verification enabled.
- Control-channel protection: inline tls-crypt-v2.
- Client identity: inline certificate and private key.
- User authentication: required; provide `OVPN_USERNAME` and `OVPN_PASSWORD` through the RouterOS container environment. A mode-0600 runtime file is generated under `/run` and removed on shutdown.
- Data cipher compatibility: AES-256-CBC is added to the OpenVPN 2.6 data-cipher negotiation list.
- Route behavior: the profile contains no local static route directives; server-pushed IPv4 routes are therefore the source for RouterOS REST synchronization.
- Secret handling: the original profile was inspected in place and was not copied into the project.
