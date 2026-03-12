#!/usr/bin/env bash
# 07-vr-setup.sh — Idempotent WiVRn + xrizer setup for CachyOS
# Run after 04-dcs-setup.sh. See docs/07-vr.md for documentation.
#
# Usage: ./scripts/07-vr-setup.sh

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

# ---------------------------------------------------------------------------
# CHANGEME_ variables — fill these in before running the script
# ---------------------------------------------------------------------------

# Network interface facing the Quest 3 (WiFi or USB).
# Without this, the firewall rules below open WiVRn ports on ALL interfaces.
# Find your interface with: ip link show | grep -E '^[0-9]+:' | awk '{print $2}'
# Common examples: wlan0, wlp5s0, enp6s0 (USB tethering)
WIFI_IF="CHANGEME_WIFI_IF"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ "${WIFI_IF}" == "CHANGEME_WIFI_IF" ]]; then
    error "Fill in WIFI_IF with the network interface used by your Quest 3.\nFind it with: ip link show | grep -E '^[0-9]+:' | awk '{print \$2}'\nExample: wlan0"
fi

# --- Steps ---

step_packages_system() {
    info "Installing system packages (avahi, nss-mdns)..."
    pacman_install_if_missing avahi
    pacman_install_if_missing nss-mdns
}

step_packages_aur() {
    # Note: wivrn-server, wivrn-dashboard, and xrizer-git must match the Quest 3 APK version.
    # As of this writing the current version is 26.2.3. If you update the APK on the headset,
    # reinstall these AUR packages to match. Mismatched versions will fail to connect.
    info "Installing AUR packages (wivrn-server, wivrn-dashboard, xrizer-git)..."
    yay_install_if_missing wivrn-server
    yay_install_if_missing wivrn-dashboard
    yay_install_if_missing xrizer-git
}

step_avahi_mdns_conflict() {
    info "Checking for systemd-resolved mDNS conflict..."
    if resolvectl status 2>/dev/null | grep -q "MulticastDNS: yes"; then
        warn "systemd-resolved mDNS is active — this conflicts with avahi."
        warn "Disable it: edit /etc/systemd/resolved.conf, set MulticastDNS=no"
        warn "Then: sudo systemctl restart systemd-resolved"
        warn "Re-run this script after disabling systemd-resolved mDNS."
        exit 1
    fi
    ok "No systemd-resolved mDNS conflict detected"
}

step_avahi_service() {
    info "Enabling avahi-daemon..."
    if systemctl is-active avahi-daemon &>/dev/null; then
        ok "avahi-daemon is already active"
        return
    fi
    sudo systemctl enable --now avahi-daemon
    ok "avahi-daemon enabled and started"
}

step_wivrn_service() {
    info "Enabling WiVRn user service..."
    if systemctl --user is-enabled wivrn.service &>/dev/null; then
        ok "wivrn.service is already enabled"
        return
    fi
    systemctl --user enable --now wivrn.service
    ok "wivrn.service enabled and started"
}

step_firewall_ports() {
    info "Checking nftables firewall rules for WiVRn..."
    if nft list ruleset 2>/dev/null | grep -q "WiVRn"; then
        ok "Firewall rules already present for WiVRn"
        return
    fi
    info "Adding nftables rules for WiVRn (ports 5353/udp and 9757) scoped to ${WIFI_IF}..."
    sudo nft add rule inet filter input iif "$WIFI_IF" udp dport 5353 accept comment '"mDNS/avahi for WiVRn"'
    sudo nft add rule inet filter input iif "$WIFI_IF" tcp dport 9757 accept comment '"WiVRn stream"'
    sudo nft add rule inet filter input iif "$WIFI_IF" udp dport 9757 accept comment '"WiVRn stream"'
    ok "Firewall rules added (interface: ${WIFI_IF})"
    warn "These rules are not persistent. See docs/07-vr.md for persistent firewall setup."
}

# Socket path note: WiVRn socket path has version-dependent variance.
# Recent builds (26.x+): $XDG_RUNTIME_DIR/wivrn/comp_ipc
# Older builds:          $XDG_RUNTIME_DIR/wivrn_comp_ipc
# Verify against installed version if using PRESSURE_VESSEL_FILESYSTEMS_RW.
step_openxr_runtime() {
    info "Verifying OpenXR active_runtime.json..."
    local runtime_json
    # Check user-scoped path first (more reliable inside pressure-vessel)
    if [[ -f "$HOME/.config/openxr/1/active_runtime.json" ]]; then
        runtime_json="$HOME/.config/openxr/1/active_runtime.json"
    elif [[ -f "/etc/xdg/openxr/1/active_runtime.json" ]]; then
        runtime_json="/etc/xdg/openxr/1/active_runtime.json"
    else
        warn "No active_runtime.json found. WiVRn may not be registered as OpenXR runtime."
        warn "Try: systemctl --user restart wivrn.service and re-run this script."
        return
    fi
    if grep -q "wivrn" "$runtime_json"; then
        ok "OpenXR runtime registered: WiVRn ($runtime_json)"
    else
        warn "active_runtime.json exists but does not reference WiVRn: $runtime_json"
        warn "Check WiVRn installation and re-run."
    fi
}

step_group_warning() {
    echo ""
    warn "====================================================="
    warn "IMPORTANT: Log out and back in (or reboot) before"
    warn "first use. New group membership (wivrn/render) is"
    warn "not active in the current session."
    warn "Verify with: groups | grep -E 'wivrn|render'"
    warn "====================================================="
    echo ""
}

# --- Main ---

main() {
    step "Starting WiVRn + xrizer setup..."
    step_packages_system
    step_packages_aur
    step_avahi_mdns_conflict
    step_avahi_service
    step_wivrn_service
    step_firewall_ports
    step_openxr_runtime
    step_group_warning
    ok "WiVRn setup complete. See docs/07-vr.md for next steps."
}

main "$@"
