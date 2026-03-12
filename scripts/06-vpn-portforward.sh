#!/usr/bin/env bash
# =============================================================================
# ProtonVPN NAT-PMP Port Forward Keeper
# Runs inside the VPN namespace, renews the port lease every 45s,
# and updates qBittorrent via Web API when the port changes.
# =============================================================================

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

NS="vpn"
NATPMP_GW="10.2.0.1"
QBIT_URL="http://10.200.200.2:8080"
QBIT_USER="CHANGEME_QBIT_USER"
QBIT_PASS="CHANGEME_QBIT_PASS"
COOKIE_FILE="/tmp/qbit-cookie-$$"
CURRENT_PORT=0

cleanup() {
    rm -f "$COOKIE_FILE"
    info "Port forward keeper stopped."
}
trap cleanup EXIT

qbit_login() {
    curl -s -c "$COOKIE_FILE" \
        --data "username=$QBIT_USER&password=$QBIT_PASS" \
        "$QBIT_URL/api/v2/auth/login" > /dev/null
}

qbit_set_port() {
    local port="$1"
    curl -s -b "$COOKIE_FILE" \
        --data "{\"listen_port\": $port, \"upnp\": false, \"random_port\": false}" \
        -H "Content-Type: application/json" \
        "$QBIT_URL/api/v2/app/setPreferences" > /dev/null
}

get_mapped_port() {
    ip netns exec "$NS" natpmpc -a 1 0 udp 60 -g "$NATPMP_GW" 2>/dev/null \
        | awk '/Mapped public port/ { print $4 }'
}

info "Starting NAT-PMP port forward keeper..."
info "Gateway: $NATPMP_GW"
info "qBittorrent: $QBIT_URL"

# Login to qBittorrent
qbit_login
info "Logged in to qBittorrent Web UI."

while true; do
    # Renew UDP lease
    UDP_PORT=$(get_mapped_port)

    if [[ -z "$UDP_PORT" ]]; then
        warn "$(date): Failed to get port from NAT-PMP gateway. Retrying..."
        sleep 10
        continue
    fi

    # Renew TCP lease
    ip netns exec "$NS" natpmpc -a 1 0 tcp 60 -g "$NATPMP_GW" > /dev/null 2>&1

    # Update qBittorrent if port changed
    if [[ "$UDP_PORT" != "$CURRENT_PORT" ]]; then
        info "$(date): Port changed: $CURRENT_PORT -> $UDP_PORT"
        qbit_set_port "$UDP_PORT"
        CURRENT_PORT="$UDP_PORT"
        info "qBittorrent updated to port $CURRENT_PORT"
    fi

    sleep 45
done
