#!/usr/bin/env python3
import base64
import ipaddress
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing environment variable: {name}")
    return value


RUNTIME_CONFIG = "/run/openvpn/routeros-api.json"
try:
    with open(RUNTIME_CONFIG, encoding="utf-8") as config_file:
        runtime = json.load(config_file)
except (FileNotFoundError, json.JSONDecodeError):
    runtime = {}


def setting(primary, legacy, runtime_key):
    value = os.environ.get(primary) or os.environ.get(legacy) or runtime.get(runtime_key, "")
    if not str(value).strip():
        raise RuntimeError(f"missing setting: {primary}")
    return str(value).strip()


def optional(primary, legacy, runtime_key, default=""):
    if primary in os.environ:
        return os.environ[primary]
    if legacy in os.environ:
        return os.environ[legacy]
    return str(runtime.get(runtime_key, default))


def secret(primary, file_setting, legacy, runtime_key):
    filename = os.environ.get(file_setting, "").strip()
    if filename:
        try:
            with open(filename, encoding="utf-8") as secret_file:
                value = secret_file.read().rstrip("\r\n")
        except OSError as exc:
            raise RuntimeError(f"cannot read {file_setting}: {exc}") from exc
        if not value:
            raise RuntimeError(f"secret file is empty: {filename}")
        return value
    return setting(primary, legacy, runtime_key)


BASE = setting("OVPN_API_URL", "ROS_URL", "url").rstrip("/") + "/rest"
USER = setting("OVPN_API_USER", "ROS_USER", "user")
PASSWORD = secret("OVPN_API_PASSWORD", "OVPN_API_PASSWORD_FILE", "ROS_PASSWORD", "password")
CONTAINER_NAME = (optional("OVPN_CONTAINER_NAME", "CONTAINER_NAME", "ovpn_container_name").strip()
                  or "ovpn-client-ros")
TAG = (optional("OVPN_ROUTE_TAG", "ROS_TAG", "ovpn_route_tag").strip()
       or os.environ.get("ROS_ROUTE_COMMENT", "").strip()
       or CONTAINER_NAME)
LEGACY_TAGS = {
    item for item in optional("OVPN_LEGACY_TAGS", "ROS_LEGACY_TAGS", "ovpn_legacy_tags")
    .replace(",", " ").split() if item
}
# The container name was the historical default tag.  Keeping it in the
# ownership set makes changing OVPN_ROUTE_TAG self-healing on the next sync.
OWNED_TAGS = {TAG, CONTAINER_NAME} | LEGACY_TAGS
TABLE = optional("OVPN_ROUTE_TABLE", "ROS_ROUTE_TABLE", "ovpn_route_table", "main").strip() or "main"
DISTANCE = optional("OVPN_ROUTE_DISTANCE", "ROS_ROUTE_DISTANCE", "ovpn_route_distance", "1").strip() or "1"
ADDRESS_LIST = (optional("OVPN_ADDRESS_LIST_NAME", "ROS_ADDRESS_LIST_NAME", "ovpn_address_list_name").strip()
                or os.environ.get("ROS_ADDRESS_LIST_NAME", "").strip()
                or os.environ.get("ROS_ADDRESS_LIST", "").strip()
                or CONTAINER_NAME)
GATEWAY = setting("OVPN_GATEWAY", "CONTAINER_GATEWAY", "gateway")
VERIFY_TLS = str(os.environ.get("OVPN_API_VERIFY_TLS", os.environ.get("ROS_VERIFY_TLS", runtime.get("verify_tls", "true")))).lower() in ("1", "yes", "true", "on")
ALLOW_DEFAULT = optional("OVPN_ALLOW_DEFAULT_ROUTE", "ALLOW_DEFAULT_ROUTE", "ovpn_allow_default_route", "false").lower() in ("1", "yes", "true", "on")
SYNC_ROUTES = optional("OVPN_SYNC_ROUTES", "ROS_SYNC_ROUTES", "ovpn_sync_routes", "true").lower() in ("1", "yes", "true", "on")
SYNC_ADDRESS_LIST = optional("OVPN_SYNC_ADDRESS_LIST", "ROS_SYNC_ADDRESS_LIST", "ovpn_sync_address_list", "true").lower() in ("1", "yes", "true", "on")
LEVELS = {"error": 0, "warn": 1, "info": 2, "debug": 3}
LOG_LEVEL = optional("OVPN_LOG_LEVEL", "LOG_LEVEL", "ovpn_log_level", "info").lower()
if LOG_LEVEL not in LEVELS:
    raise RuntimeError("LOG_LEVEL must be one of: error, warn, info, debug")


def log(level, message):
    if LEVELS[level] <= LEVELS[LOG_LEVEL]:
        stream = sys.stderr if level in ("error", "warn") else sys.stdout
        print(f"[route-sync] [{level}] {message}", file=stream, flush=True)


def context():
    if VERIFY_TLS:
        cafile = os.environ.get("ROS_CA_FILE")
        return ssl.create_default_context(cafile=cafile or None)
    return ssl._create_unverified_context()


def request(method, path, body=None):
    auth = base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"},
    )
    log("debug", f"RouterOS REST request {method} {path}")
    try:
        with urllib.request.urlopen(req, context=context(), timeout=10) as response:
            payload = response.read()
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"RouterOS REST {method} {path}: HTTP {exc.code}: {detail}") from exc


def owned_routes():
    routes = request("GET", "/ip/route") or []
    return [r for r in routes if r.get("comment") in OWNED_TAGS]


def owned_address_entries():
    entries = request("GET", "/ip/firewall/address-list") or []
    return [e for e in entries if e.get("comment") in OWNED_TAGS and e.get("list") == ADDRESS_LIST]


def delete_owned():
    for route in owned_routes():
        # RouterOS REST record identifiers start with "*" and that character
        # must remain literal in the resource path.
        route_id = urllib.parse.quote(route[".id"], safe="*")
        request("DELETE", f"/ip/route/{route_id}")
        log("info", f"deleted RouterOS route {route.get('dst-address', route['.id'])}")
    if ADDRESS_LIST:
        for entry in owned_address_entries():
            entry_id = urllib.parse.quote(entry[".id"], safe="*")
            request("DELETE", f"/ip/firewall/address-list/{entry_id}")
            log("info", f"deleted RouterOS address-list entry {entry.get('address', entry['.id'])}")


def pushed_routes():
    result = set()
    index = 1
    while True:
        network = os.environ.get(f"route_network_{index}")
        if network is None:
            break
        mask = os.environ.get(f"route_netmask_{index}", "255.255.255.255")
        result.add(str(ipaddress.IPv4Network((network, mask), strict=False)))
        index += 1
    extra_routes = optional("OVPN_EXTRA_ROUTES", "EXTRA_ROUTES", "ovpn_extra_routes")
    for item in extra_routes.replace(",", " ").split():
        result.add(str(ipaddress.IPv4Network(item, strict=False)))
    if not ALLOW_DEFAULT:
        result.discard("0.0.0.0/0")
    return sorted(result, key=lambda value: (ipaddress.ip_network(value).prefixlen, value), reverse=True)


def add_routes():
    desired = pushed_routes()
    desired_set = set(desired)
    routes = request("GET", "/ip/route") or []
    entries = request("GET", "/ip/firewall/address-list") or []
    kept_routes = set()
    kept_addresses = set()

    # Preserve an already-correct record with the current tag. Remove only
    # stale, changed, disabled, or legacy-tagged records owned by this client.
    for route in routes:
        if route.get("comment") not in OWNED_TAGS:
            continue
        destination = route.get("dst-address")
        current = (
            SYNC_ROUTES
            and route.get("comment") == TAG
            and destination in desired_set
            and route.get("gateway") == GATEWAY
            and route.get("routing-table", "main") == TABLE
            and str(route.get("distance", "1")) == DISTANCE
            and route.get("disabled", "false") != "true"
        )
        if current:
            kept_routes.add(destination)
            log("debug", f"kept current RouterOS route {destination}")
        else:
            route_id = urllib.parse.quote(route[".id"], safe="*")
            request("DELETE", f"/ip/route/{route_id}")
            log("info", f"deleted stale RouterOS route {destination or route['.id']}")

    for entry in entries:
        if entry.get("list") != ADDRESS_LIST or entry.get("comment") not in OWNED_TAGS:
            continue
        address = entry.get("address")
        current = (
            SYNC_ADDRESS_LIST
            and entry.get("comment") == TAG
            and address in desired_set
            and entry.get("disabled", "false") != "true"
        )
        if current:
            kept_addresses.add(address)
            log("debug", f"kept current RouterOS address-list entry {ADDRESS_LIST}:{address}")
        else:
            entry_id = urllib.parse.quote(entry[".id"], safe="*")
            request("DELETE", f"/ip/firewall/address-list/{entry_id}")
            log("info", f"deleted stale RouterOS address-list entry {address or entry['.id']}")

    # Non-owned list entries are never changed. They satisfy the requested
    # address and prevent RouterOS duplicate-entry errors.
    foreign_addresses = {
        entry.get("address") for entry in entries
        if entry.get("list") == ADDRESS_LIST and entry.get("comment") not in OWNED_TAGS
    }
    for destination in desired:
        if SYNC_ROUTES and destination not in kept_routes:
            body = {
                "dst-address": destination,
                "gateway": GATEWAY,
                "routing-table": TABLE,
                "distance": DISTANCE,
                "comment": TAG,
            }
            request("PUT", "/ip/route", body)
            log("info", f"created RouterOS route {destination} via {GATEWAY} table {TABLE}")
        if SYNC_ADDRESS_LIST and ADDRESS_LIST:
            if destination in kept_addresses:
                continue
            if destination in foreign_addresses:
                log("warn", f"kept existing non-owned RouterOS address-list entry {ADDRESS_LIST}:{destination}")
            else:
                request("PUT", "/ip/firewall/address-list", {
                    "list": ADDRESS_LIST,
                    "address": destination,
                    "comment": TAG,
                })
                kept_addresses.add(destination)
                log("info", f"created RouterOS address-list entry {ADDRESS_LIST}:{destination}")
    log("info", f"sync complete: destinations={len(desired)} routes={'on' if SYNC_ROUTES else 'off'} address-list={'on' if SYNC_ADDRESS_LIST and ADDRESS_LIST else 'off'}")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("up", "down"):
        raise SystemExit("usage: route_sync.py up|down")
    try:
        add_routes() if sys.argv[1] == "up" else delete_owned()
    except Exception as exc:
        log("error", f"route sync failed: {exc}")
        raise SystemExit(1)
