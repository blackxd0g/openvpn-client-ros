#!/bin/sh
set -eu

log_info() {
  case "${OVPN_LOG_LEVEL:-${LOG_LEVEL:-info}}" in error|warn) return 0;; esac
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [ovpn-route-hook] [info] $*"
}

case "${script_type:-}" in
  route-up)
    log_info "tunnel is up; synchronizing RouterOS routes"
    exec /usr/local/bin/route_sync.py up
    ;;
  route-pre-down)
    log_info "tunnel is going down; withdrawing RouterOS routes"
    exec /usr/local/bin/route_sync.py down
    ;;
  *)
    echo "Ignoring OpenVPN hook: ${script_type:-unknown}" >&2
    ;;
esac
