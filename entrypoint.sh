#!/bin/sh
set -eu

case "${OVPN_LOG_LEVEL:-${LOG_LEVEL:-info}}" in
  error) LOG_THRESHOLD=0; OVPN_VERB_DEFAULT=1 ;;
  warn)  LOG_THRESHOLD=1; OVPN_VERB_DEFAULT=2 ;;
  info)  LOG_THRESHOLD=2; OVPN_VERB_DEFAULT=3 ;;
  debug) LOG_THRESHOLD=3; OVPN_VERB_DEFAULT=5 ;;
  *) echo "LOG_LEVEL must be one of: error, warn, info, debug" >&2; exit 1 ;;
esac

log() {
  level="$1"
  shift
  case "$level" in error) value=0;; warn) value=1;; info) value=2;; debug) value=3;; esac
  [ "$value" -le "$LOG_THRESHOLD" ] || return 0
  printf '%s [ovpn-supervisor] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$*"
}

case "$(uname -m)" in
  aarch64|armv7l|armv8l) ;;
  *)
    echo "Unsupported CPU architecture: $(uname -m); expected ARMv7 or ARM64" >&2
    exit 1
    ;;
esac

log info "OpenVPN client version: $(openvpn --version | sed -n '1p')"

if [ ! -r "$OVPN_CONFIG" ]; then
  echo "OpenVPN config not found: $OVPN_CONFIG" >&2
  exit 1
fi

read_secret() {
  secret_file="$1"
  secret_name="$2"
  if [ ! -r "$secret_file" ]; then
    echo "$secret_name file is not readable: $secret_file" >&2
    exit 1
  fi
  secret_value="$(cat "$secret_file")"
  if [ -z "$secret_value" ]; then
    echo "$secret_name file is empty: $secret_file" >&2
    exit 1
  fi
  printf '%s' "$secret_value"
}

ROS_URL="${OVPN_API_URL:-${ROS_URL:-}}"
ROS_USER="${OVPN_API_USER:-${ROS_USER:-}}"
if [ -n "${OVPN_API_PASSWORD_FILE:-}" ]; then
  ROS_PASSWORD="$(read_secret "$OVPN_API_PASSWORD_FILE" OVPN_API_PASSWORD)"
else
  ROS_PASSWORD="${OVPN_API_PASSWORD:-${ROS_PASSWORD:-}}"
fi
CONTAINER_GATEWAY="${OVPN_GATEWAY:-${CONTAINER_GATEWAY:-}}"
ROS_VERIFY_TLS="${OVPN_API_VERIFY_TLS:-${ROS_VERIFY_TLS:-true}}"
export ROS_URL ROS_USER ROS_PASSWORD CONTAINER_GATEWAY ROS_VERIFY_TLS

for name in ROS_URL ROS_USER ROS_PASSWORD CONTAINER_GATEWAY; do
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Required environment variable is missing: $name" >&2
    exit 1
  fi
done

# OpenVPN may sanitize the environment passed to route hooks. Persist only the
# RouterOS API settings in an ephemeral root-only file under /run.
python3 -c 'import json, os; p="/run/openvpn/routeros-api.json"; keys=("OVPN_CONTAINER_NAME","OVPN_ROUTE_TAG","OVPN_SYNC_ROUTES","OVPN_SYNC_ADDRESS_LIST","OVPN_ADDRESS_LIST_NAME","OVPN_ROUTE_TABLE","OVPN_ROUTE_DISTANCE","OVPN_ALLOW_DEFAULT_ROUTE","OVPN_EXTRA_ROUTES","OVPN_LOG_LEVEL"); d={"url":os.environ["ROS_URL"],"user":os.environ["ROS_USER"],"password":os.environ["ROS_PASSWORD"],"gateway":os.environ["CONTAINER_GATEWAY"],"verify_tls":os.environ["ROS_VERIFY_TLS"]}; d.update({k.lower():os.environ.get(k,"") for k in keys}); json.dump(d,open(p,"w"))'
chmod 0600 /run/openvpn/routeros-api.json

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Forward only traffic that enters through the RouterOS-facing veth.
iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -C FORWARD -i eth0 -o tun0 -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -C FORWARD -i tun0 -o eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i tun0 -o eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Remove leftovers from a previous unclean shutdown before OpenVPN connects.
/usr/local/bin/route_sync.py down || true

cleanup() {
  if [ -n "${OPENVPN_PID:-}" ] && kill -0 "$OPENVPN_PID" 2>/dev/null; then
    log info "stopping child process pid=$OPENVPN_PID"
    kill -TERM "$OPENVPN_PID" 2>/dev/null || true
    wait "$OPENVPN_PID" 2>/dev/null || true
  fi
  /usr/local/bin/route_sync.py down || true
  rm -f /run/openvpn/auth.txt
  rm -f /run/openvpn/routeros-api.json
}

STOP_REQUESTED=0
OPENVPN_PID=""
on_signal() {
  STOP_REQUESTED=1
  cleanup
}
trap on_signal INT TERM
trap cleanup EXIT

set -- \
  --config "$OVPN_CONFIG" \
  --script-security 2 \
  --route-up /usr/local/bin/route-hook.sh \
  --route-pre-down /usr/local/bin/route-hook.sh \
  --auth-retry nointeract \
  --auth-nocache \
  --pull-filter ignore dhcp-pre-release \
  --pull-filter ignore dhcp-renew \
  --pull-filter ignore dhcp-release \
  --pull-filter ignore register-dns \
  --persist-tun

if [ -n "${OVPN_PASSWORD_FILE:-}" ]; then
  OVPN_PASSWORD="$(read_secret "$OVPN_PASSWORD_FILE" OVPN_PASSWORD)"
fi

if [ -n "${OVPN_USERNAME:-}" ] && [ -n "${OVPN_PASSWORD:-}" ]; then
  umask 077
  printf '%s\n%s\n' "$OVPN_USERNAME" "$OVPN_PASSWORD" > /run/openvpn/auth.txt
  set -- "$@" --auth-user-pass /run/openvpn/auth.txt
  unset OVPN_USERNAME OVPN_PASSWORD
elif grep -Eq '^[[:space:]]*auth-user-pass[[:space:]]*$' "$OVPN_CONFIG"; then
  echo "Profile requires credentials; set OVPN_USERNAME and OVPN_PASSWORD or OVPN_PASSWORD_FILE" >&2
  exit 1
fi

if [ -n "${OVPN_DATA_CIPHERS:-}" ]; then
  set -- "$@" --data-ciphers "$OVPN_DATA_CIPHERS"
fi

# Command-line verb takes precedence over a value embedded in the profile.
set -- "$@" --verb "${OVPN_VERB:-$OVPN_VERB_DEFAULT}"

case "${OVPN_RESTART_DELAY:-10}" in
  ''|*[!0-9]*)
    echo "OVPN_RESTART_DELAY must be a non-negative integer" >&2
    exit 1
    ;;
esac

attempt=0
while [ "$STOP_REQUESTED" -eq 0 ]; do
  attempt=$((attempt + 1))
  log info "starting OpenVPN attempt=$attempt config=$OVPN_CONFIG verb=${OVPN_VERB:-$OVPN_VERB_DEFAULT}"
  openvpn "$@" &
  OPENVPN_PID=$!

  set +e
  wait "$OPENVPN_PID"
  status=$?
  set -e
  OPENVPN_PID=""

  if [ "$STOP_REQUESTED" -ne 0 ]; then
    break
  fi

  log warn "OpenVPN exited code=$status; withdrawing managed RouterOS routes"
  /usr/local/bin/route_sync.py down || log warn "failed to withdraw managed routes"
  log info "restarting OpenVPN in ${OVPN_RESTART_DELAY}s"
  sleep "$OVPN_RESTART_DELAY" &
  OPENVPN_PID=$!
  set +e
  wait "$OPENVPN_PID"
  set -e
  OPENVPN_PID=""
done

log info "supervisor stopped"
