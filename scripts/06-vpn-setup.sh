#!/usr/bin/env bash
# =============================================================================
# CachyOS VPN Namespace Setup - Infrastructure as Code
# =============================================================================
# Idempotently provisions the full ProtonVPN WireGuard namespace isolation
# setup for Brave and qBittorrent on CachyOS / Arch Linux with KDE Plasma.
#
# What this deploys:
#   - ~/scripts/vpn-namespace.sh       WireGuard namespace manager
#   - ~/scripts/vpn-portforward.sh     NAT-PMP port forward keeper
#   - /etc/systemd/system/vpn-namespace.service
#   - /etc/systemd/system/vpn-portforward.service
#   - ~/.config/systemd/user/qbittorrent-vpn.service
#   - /etc/sudoers.d/vpn-namespace     NOPASSWD rule for the script
#   - /etc/brave/policies/             Managed + recommended policies
#   - ~/.config/brave-flags.conf       --password-store=basic
#   - ~/.local/share/applications/     Desktop entry overrides for Brave + qBit
#   - UFW rules for veth forwarding
#
# PREREQUISITES (run before this script):
#   1. Copy configs/vpn/proton-vpn.conf.example to configs/vpn/proton-vpn.conf
#      and fill in your values from the ProtonVPN WireGuard dashboard.
#      Download config from: account.protonvpn.com -> Downloads -> WireGuard
#   2. Install packages:
#      sudo pacman -S wireguard-tools qbittorrent libnatpmp ufw
#      yay -S brave-bin
#   3. Set qBittorrent Web UI (Tools -> Preferences -> Web UI):
#      - Enable Web UI, port 8080, bind to 0.0.0.0
#      - Set username/password (update QBIT_USER/QBIT_PASS below)
#      - Disable UPnP/NAT-PMP in Connection tab
#
# Usage:
#   chmod +x setup-vpn-namespace.sh
#   ./setup-vpn-namespace.sh
# =============================================================================

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

[[ "$EUID" -eq 0 ]] && error "Do not run as root. Script uses sudo internally where needed."

# =============================================================================
# Config — fill in your values (run: grep -r 'CHANGEME_' . to find all)
# =============================================================================
REAL_USER="CHANGEME_USERNAME"
REAL_UID="1000"
PHY_IF="CHANGEME_PHY_IF"          # your physical interface (e.g. eno1, enp0s3, eth0) — run: ip route show default
SCRIPTS_DIR="${HOME}/scripts"
CONF_FILE="${HOME}/configs/vpn/proton-vpn.conf"

# WireGuard (from your proton-vpn.conf)
WG_ADDR="10.2.0.2/32"
WG_DNS="10.2.0.1"
WG_ENDPOINT="CHANGEME_WG_ENDPOINT"
WG_ENDPOINT_IP="CHANGEME_WG_ENDPOINT_IP"
WG_PUBKEY="CHANGEME_WG_PUBKEY"

# veth pair
VETH_HOST_IP="10.200.200.1/24"
VETH_NS_IP="10.200.200.2/24"
VETH_GW="10.200.200.1"

# qBittorrent Web UI
QBIT_URL="http://10.200.200.2:8080"
QBIT_USER="CHANGEME_QBIT_USER"
QBIT_PASS="CHANGEME_QBIT_PASS"

# =============================================================================
# STEP 1: SCRIPTS DIRECTORY
# =============================================================================
info "Creating scripts directory..."
mkdir -p "${SCRIPTS_DIR}"

[[ -f "${CONF_FILE}" ]] || error "WireGuard config not found at ${CONF_FILE}. Copy configs/vpn/proton-vpn.conf.example to ${CONF_FILE} and fill in your values."

# =============================================================================
# STEP 2: vpn-namespace.sh
# =============================================================================
info "Writing vpn-namespace.sh..."
cat > "${SCRIPTS_DIR}/vpn-namespace.sh" << 'SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# ProtonVPN WireGuard Network Namespace
# Isolates Brave and qBittorrent in a VPN-only namespace.
# System traffic (games, etc.) is completely unaffected.
#
# Usage:
#   sudo ./vpn-namespace.sh up     - Create namespace and bring up VPN
#   sudo ./vpn-namespace.sh down   - Tear down namespace
#        ./vpn-namespace.sh status - Show namespace, WireGuard, and IP status
#        ./vpn-namespace.sh brave  - Launch Brave in VPN namespace
#        ./vpn-namespace.sh qbit   - Launch qBittorrent in VPN namespace
# =============================================================================

HOME="${HOME:-/root}"
set -euo pipefail

# =============================================================================
# Config — fill in your values (run: grep -r 'CHANGEME_' . to find all)
# =============================================================================
CONF_FILE="${HOME}/configs/vpn/proton-vpn.conf"
NS="vpn"
PHY_IF="CHANGEME_PHY_IF"
WG_IF="wg0"
VETH_HOST="veth-host"
VETH_NS="veth-ns"
VETH_HOST_IP="10.200.200.1/24"
VETH_NS_IP="10.200.200.2/24"
VETH_GW="10.200.200.1"

WG_ADDR="10.2.0.2/32"
WG_DNS="10.2.0.1"
WG_ENDPOINT="CHANGEME_WG_ENDPOINT"
WG_PUBKEY="CHANGEME_WG_PUBKEY"
WG_ENDPOINT_IP="CHANGEME_WG_ENDPOINT_IP"

REAL_USER="CHANGEME_USERNAME"
REAL_UID="1000"

# =============================================================================
# HELPERS
# =============================================================================
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; exit 1; }

ns_exec() { ip netns exec "$NS" "$@"; }

get_privkey() {
    grep -m1 "^PrivateKey" "$CONF_FILE" | awk '{print $3}'
}

# =============================================================================
# UP
# =============================================================================
cmd_up() {
    [[ "$EUID" -ne 0 ]] && error "Run 'up' with sudo."
    [[ -f "$CONF_FILE" ]] || error "Config not found: $CONF_FILE"

    PRIVKEY=$(get_privkey)
    [[ -z "$PRIVKEY" ]] && error "Could not read PrivateKey from $CONF_FILE"

    info "Creating network namespace: $NS"
    if ip netns list | grep -q "^$NS "; then
        warn "Namespace $NS already exists, tearing down first..."
        cmd_down 2>/dev/null || true
    fi
    ip netns add "$NS"

    info "Creating veth pair..."
    ip link add "veth-host" type veth peer name "veth-ns"
    ip link set "veth-ns" netns "$NS"

    info "Configuring host-side veth..."
    ip addr add "$VETH_HOST_IP" dev "veth-host"
    ip link set "veth-host" up

    info "Configuring namespace-side veth..."
    ns_exec ip addr add "$VETH_NS_IP" dev "veth-ns"
    ns_exec ip link set "veth-ns" up
    ns_exec ip link set lo up
    ns_exec ip route add default via "$VETH_GW"

    info "Enabling IP forwarding and masquerade..."
    sysctl -qw net.ipv4.ip_forward=1
    nft add table inet vpn-nat 2>/dev/null || true
    nft add chain inet vpn-nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null || true
    nft add rule inet vpn-nat postrouting ip saddr 10.200.200.0/24 oif "$PHY_IF" masquerade 2>/dev/null || true
    nft add chain inet vpn-nat forward '{ type filter hook forward priority 0; }' 2>/dev/null || true
    nft add rule inet vpn-nat forward iif "veth-host" accept 2>/dev/null || true
    nft add rule inet vpn-nat forward oif "veth-host" accept 2>/dev/null || true

    info "Creating WireGuard interface in namespace..."
    ns_exec ip link add "$WG_IF" type wireguard

    info "Configuring WireGuard..."
    ns_exec wg set "$WG_IF" \
        private-key <(echo "$PRIVKEY") \
        peer "$WG_PUBKEY" \
        endpoint "$WG_ENDPOINT" \
        allowed-ips "0.0.0.0/0,::/0" \
        persistent-keepalive 25

    ns_exec ip addr add "$WG_ADDR" dev "$WG_IF"
    ns_exec ip link set "$WG_IF" up

    info "Setting up routes inside namespace..."
    ns_exec ip route add "${WG_ENDPOINT_IP}/32" via "$VETH_GW"
    ns_exec ip route del default
    ns_exec ip route add default dev "$WG_IF"

    info "Configuring DNS inside namespace..."
    mkdir -p "/etc/netns/${NS}"
    echo "nameserver $WG_DNS" > "/etc/netns/${NS}/resolv.conf"

    info "Applying UFW forwarding rules..."
    ufw route allow in on veth-host 2>/dev/null || true
    ufw route allow out on veth-host 2>/dev/null || true
    ufw allow in on veth-host to any port 8080 2>/dev/null || true

    info "Verifying WireGuard handshake..."
    sleep 2
    if ns_exec wg show "$WG_IF" | grep -q "latest handshake"; then
        info "Handshake established."
    else
        warn "No handshake yet - may take a few seconds. Run 'status' to check."
    fi

    info "Namespace $NS is up."
}

# =============================================================================
# DOWN
# =============================================================================
cmd_down() {
    [[ "$EUID" -ne 0 ]] && error "Run 'down' with sudo."

    info "Tearing down namespace $NS..."
    nft delete table inet vpn-nat 2>/dev/null || true
    ip link del "veth-host" 2>/dev/null || true
    ip netns del "$NS" 2>/dev/null || true
    rm -f "/etc/netns/${NS}/resolv.conf"
    rmdir "/etc/netns/${NS}" 2>/dev/null || true
    info "Namespace $NS removed."
}

# =============================================================================
# STATUS
# =============================================================================
cmd_status() {
    echo ""
    echo "=== Namespace ==="
    ip netns list | grep "$NS" || echo "Namespace $NS not found."

    echo ""
    echo "=== WireGuard ==="
    if ip netns list | grep -q "^$NS "; then
        ns_exec wg show "$WG_IF" 2>/dev/null || echo "WireGuard interface not up."
    fi

    echo ""
    echo "=== Routes inside namespace ==="
    if ip netns list | grep -q "^$NS "; then
        ns_exec ip route show 2>/dev/null || true
    fi

    echo ""
    echo "=== IP check (should show ProtonVPN IP) ==="
    if ip netns list | grep -q "^$NS "; then
        ns_exec curl -s --max-time 5 https://ipinfo.io/ip || echo "Could not reach ipinfo.io"
    fi
    echo ""
}

# =============================================================================
# LAUNCH APPS
# Passes Wayland/X11/DBus env so GUI apps render correctly in KDE Plasma
# =============================================================================
launch_in_ns() {
    local app="$1"
    shift
    local real_user="${SUDO_USER:-$USER}"
    local uid
    uid=$(id -u "$real_user")

    local env_vars=(
        "HOME=/home/$real_user"
        "USER=$real_user"
        "DISPLAY=${DISPLAY:-:0}"
        "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}"
        "XDG_RUNTIME_DIR=/run/user/$uid"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus"
        "PULSE_SERVER=unix:/run/user/$uid/pulse/native"
        "XDG_CONFIG_HOME=/home/$real_user/.config"
        "XDG_DATA_HOME=/home/$real_user/.local/share"
        "XDG_CACHE_HOME=/home/$real_user/.cache"
    )

    ip netns list | grep -q "^$NS " || error "Namespace $NS is not up. Run: sudo ./vpn-namespace.sh up"

    echo -e "${GREEN}[+]${NC} Launching $app in VPN namespace..."
    sudo ip netns exec "$NS" sudo -u "$real_user" env "${env_vars[@]}" "$app" "$@" &
    disown
}

cmd_brave() {
    command -v brave &>/dev/null || error "brave not found."
    launch_in_ns brave "$@"
}

cmd_qbit() {
    command -v qbittorrent &>/dev/null || error "qbittorrent not found. Install: sudo pacman -S qbittorrent"
    launch_in_ns qbittorrent
}

# =============================================================================
# ENTRY POINT
# =============================================================================
case "${1:-help}" in
    up)     cmd_up ;;
    down)   cmd_down ;;
    status) cmd_status ;;
    brave)  cmd_brave "${@:2}" ;;
    qbit)   cmd_qbit ;;
    *)
        echo "Usage: $0 {up|down|status|brave|qbit}"
        echo ""
        echo "  sudo $0 up       - Create VPN namespace and connect WireGuard"
        echo "  sudo $0 down     - Tear down VPN namespace"
        echo "       $0 status   - Show namespace, WireGuard, and IP status"
        echo "       $0 brave    - Launch Brave in VPN namespace"
        echo "       $0 qbit     - Launch qBittorrent in VPN namespace"
        ;;
esac
SCRIPT

chmod +x "${SCRIPTS_DIR}/vpn-namespace.sh"
info "vpn-namespace.sh written."

# =============================================================================
# STEP 3: vpn-portforward.sh
# =============================================================================
info "Writing vpn-portforward.sh..."
cat > "${SCRIPTS_DIR}/vpn-portforward.sh" << SCRIPT
#!/usr/bin/env bash
# =============================================================================
# ProtonVPN NAT-PMP Port Forward Keeper
# Renews port lease every 45s, updates qBittorrent via Web API on change.
# Requires: libnatpmp (sudo pacman -S libnatpmp)
# =============================================================================

NS="vpn"
NATPMP_GW="${WG_DNS}"
QBIT_URL="${QBIT_URL}"
QBIT_USER="${QBIT_USER}"
QBIT_PASS="${QBIT_PASS}"
COOKIE_FILE="/tmp/qbit-cookie-\$\$"
CURRENT_PORT=0

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "\${GREEN}[+]\${NC} \$1"; }
warn()  { echo -e "\${YELLOW}[!]\${NC} \$1"; }
error() { echo -e "\${RED}[-]\${NC} \$1"; exit 1; }

cleanup() {
    rm -f "\$COOKIE_FILE"
    info "Port forward keeper stopped."
}
trap cleanup EXIT

qbit_login() {
    curl -s -c "\$COOKIE_FILE" \
        --data "username=\$QBIT_USER&password=\$QBIT_PASS" \
        "\$QBIT_URL/api/v2/auth/login" > /dev/null
}

qbit_set_port() {
    local port="\$1"
    curl -s -b "\$COOKIE_FILE" \
        --data "{\"listen_port\": \$port, \"upnp\": false, \"random_port\": false}" \
        -H "Content-Type: application/json" \
        "\$QBIT_URL/api/v2/app/setPreferences" > /dev/null
}

get_mapped_port() {
    ip netns exec "\$NS" natpmpc -a 1 0 udp 60 -g "\$NATPMP_GW" 2>/dev/null \
        | awk '/Mapped public port/ { print \$4 }'
}

info "Starting NAT-PMP port forward keeper..."
info "Gateway: \$NATPMP_GW"
info "qBittorrent: \$QBIT_URL"

qbit_login
info "Logged in to qBittorrent Web UI."

while true; do
    UDP_PORT=\$(get_mapped_port)

    if [[ -z "\$UDP_PORT" ]]; then
        warn "\$(date): Failed to get port from NAT-PMP gateway. Retrying..."
        sleep 10
        continue
    fi

    ip netns exec "\$NS" natpmpc -a 1 0 tcp 60 -g "\$NATPMP_GW" > /dev/null 2>&1

    if [[ "\$UDP_PORT" != "\$CURRENT_PORT" ]]; then
        info "\$(date): Port changed: \$CURRENT_PORT -> \$UDP_PORT"
        qbit_set_port "\$UDP_PORT"
        CURRENT_PORT="\$UDP_PORT"
        info "qBittorrent updated to port \$CURRENT_PORT"
    fi

    sleep 45
done
SCRIPT

chmod +x "${SCRIPTS_DIR}/vpn-portforward.sh"
info "vpn-portforward.sh written."

# =============================================================================
# STEP 4: SYSTEMD SYSTEM SERVICES
# =============================================================================
info "Installing system systemd services..."

sudo tee /etc/systemd/system/vpn-namespace.service > /dev/null << SERVICE
[Unit]
Description=ProtonVPN WireGuard Network Namespace
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=HOME=/root
ExecStart=/bin/bash ${SCRIPTS_DIR}/vpn-namespace.sh up
ExecStop=/bin/bash ${SCRIPTS_DIR}/vpn-namespace.sh down
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

sudo tee /etc/systemd/system/vpn-portforward.service > /dev/null << SERVICE
[Unit]
Description=ProtonVPN NAT-PMP Port Forward Keeper
After=vpn-namespace.service
Requires=vpn-namespace.service

[Service]
Type=simple
User=root
ExecStartPre=/bin/sleep 5
ExecStart=${SCRIPTS_DIR}/vpn-portforward.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable vpn-namespace.service vpn-portforward.service
info "System services installed and enabled."

# =============================================================================
# STEP 5: SYSTEMD USER SERVICE (qBittorrent autostart)
# =============================================================================
info "Installing qBittorrent user service..."

mkdir -p "${HOME}/.config/systemd/user"
cat > "${HOME}/.config/systemd/user/qbittorrent-vpn.service" << SERVICE
[Unit]
Description=qBittorrent in VPN Namespace
After=xdg-desktop-autostart.target
Wants=xdg-desktop-autostart.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/${REAL_UID}
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/sudo ${SCRIPTS_DIR}/vpn-namespace.sh qbit
Restart=on-failure
RestartSec=15

[Install]
WantedBy=xdg-desktop-autostart.target
SERVICE

systemctl --user daemon-reload
systemctl --user enable qbittorrent-vpn.service
info "qBittorrent user service installed and enabled."

# =============================================================================
# STEP 6: SUDOERS
# =============================================================================
info "Writing sudoers rule..."
echo "${REAL_USER} ALL=(ALL) NOPASSWD: ${SCRIPTS_DIR}/vpn-namespace.sh" \
    | sudo tee /etc/sudoers.d/vpn-namespace > /dev/null
sudo chmod 440 /etc/sudoers.d/vpn-namespace
info "Sudoers rule written."

# =============================================================================
# STEP 7: UFW RULES
# =============================================================================
info "Applying UFW rules..."
sudo ufw route allow in on veth-host 2>/dev/null || true
sudo ufw route allow out on veth-host 2>/dev/null || true
sudo ufw allow in on veth-host to any port 8080 2>/dev/null || true
info "UFW rules applied."

# =============================================================================
# STEP 8: BRAVE FLAGS
# =============================================================================
info "Writing Brave launch flags..."
echo "--password-store=basic" > "${HOME}/.config/brave-flags.conf"
info "brave-flags.conf written (disables KWallet hang)."

# =============================================================================
# STEP 9: BRAVE POLICIES
# =============================================================================
info "Deploying Brave managed policies..."
sudo mkdir -p /etc/brave/policies/managed
sudo mkdir -p /etc/brave/policies/recommended

sudo tee /etc/brave/policies/managed/privacy.json > /dev/null << 'EOF'
{
  "MetricsReportingEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "SearchSuggestEnabled": false,
  "WebRtcIPHandlingPolicy": "disable_non_proxied_udp",
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,
  "PasswordManagerEnabled": false,
  "DefaultNotificationsSetting": 2,
  "DefaultGeolocationSetting": 2,
  "DefaultWebBluetoothGuardSetting": 2,
  "DefaultWebUsbGuardSetting": 2,
  "BackgroundModeEnabled": false,
  "DnsOverHttpsMode": "secure",
  "SafeBrowsingEnabled": true,
  "ImportAutofillFormData": false
}
EOF

sudo tee /etc/brave/policies/recommended/defaults.json > /dev/null << 'EOF'
{
  "HttpsOnlyMode": "force_enabled",
  "BlockThirdPartyCookies": true,
  "DefaultPopupsSetting": 2,
  "PromptForDownloadLocation": true
}
EOF

info "Brave policies written. Verify at brave://policy after launch."

# =============================================================================
# STEP 10: DESKTOP ENTRY OVERRIDES
# =============================================================================
info "Overriding Brave desktop entry..."
BRAVE_DESKTOP_SRC="/usr/share/applications/brave-browser.desktop"
BRAVE_DESKTOP_DST="${HOME}/.local/share/applications/brave-browser.desktop"

mkdir -p "${HOME}/.local/share/applications"

if [[ -f "$BRAVE_DESKTOP_SRC" ]]; then
    cp "$BRAVE_DESKTOP_SRC" "$BRAVE_DESKTOP_DST"
    # Override all Exec= lines to route through VPN namespace
    sed -i "s|^Exec=.*brave.*%U|Exec=/usr/bin/sudo ${SCRIPTS_DIR}/vpn-namespace.sh brave %U|g" "$BRAVE_DESKTOP_DST"
    sed -i "s|^Exec=.*brave.*--incognito.*%U|Exec=/usr/bin/sudo ${SCRIPTS_DIR}/vpn-namespace.sh brave --incognito %U|g" "$BRAVE_DESKTOP_DST"
    info "Brave desktop entry overridden."
else
    warn "Brave desktop entry not found at $BRAVE_DESKTOP_SRC - skipping."
fi

info "Overriding qBittorrent desktop entry..."
QBIT_DESKTOP_SRC="/usr/share/applications/org.qbittorrent.qBittorrent.desktop"
QBIT_DESKTOP_DST="${HOME}/.local/share/applications/org.qbittorrent.qBittorrent.desktop"

if [[ -f "$QBIT_DESKTOP_SRC" ]]; then
    cp "$QBIT_DESKTOP_SRC" "$QBIT_DESKTOP_DST"
    sed -i "s|^Exec=.*|Exec=/usr/bin/sudo ${SCRIPTS_DIR}/vpn-namespace.sh qbit|g" "$QBIT_DESKTOP_DST"
    info "qBittorrent desktop entry overridden."
else
    warn "qBittorrent desktop entry not found at $QBIT_DESKTOP_SRC - skipping."
fi

update-desktop-database "${HOME}/.local/share/applications/" 2>/dev/null || true

# =============================================================================
# DONE
# =============================================================================
echo ""
echo "============================================================"
info "Setup complete. Summary:"
echo "============================================================"
echo ""
echo "  System services (auto-start on boot):"
echo "    vpn-namespace.service   - WireGuard namespace"
echo "    vpn-portforward.service - NAT-PMP port keeper"
echo ""
echo "  User services (auto-start on login):"
echo "    qbittorrent-vpn.service - qBittorrent in namespace"
echo ""
echo "  Scripts:"
echo "    ${SCRIPTS_DIR}/vpn-namespace.sh"
echo "    ${SCRIPTS_DIR}/vpn-portforward.sh"
echo "    ${CONF_FILE}   <-- WireGuard config (must be created from .example)"
echo ""
echo "  Brave: Launched via app menu or sudo vpn-namespace.sh brave"
echo "         Policies: /etc/brave/policies/"
echo "         Flags:    ~/.config/brave-flags.conf"
echo ""
echo "  KDE Session: Set to 'Start with empty session' to prevent"
echo "               apps from restoring outside the namespace."
echo ""
echo "  Verify after reboot:"
echo "    pgrep -a qbittorrent"
echo "    set pid (pgrep qbittorrent)"
echo "    sudo nsenter -t \$pid -n ip route   # should show: default dev wg0"
echo ""
warn "MANUAL BRAVE STEPS (brave://settings):"
echo "  Shields:  Trackers & Ads -> Aggressive"
echo "  Privacy:  Disable P3A, usage ping, Google push messaging"
echo "  Rewards:  Disable entirely"
echo "  Web3:     Default wallets -> Extensions (no fallback)"
echo "  Verify:   brave://policy -> all entries Active"
echo ""
