#!/usr/bin/env bash
# 04-dcs-launch-vr.sh — DCS World VR launcher for CachyOS
# Requires WiVRn server running and Quest 3 connected before launch.
# See docs/07-vr.md and docs/04-dcs-world.md for documentation.
#
# Usage:
#   04-dcs-launch-vr.sh -n   launch DCS in VR mode (no launcher)
#
# Launch order (mandatory):
#   1. Start WiVRn dashboard and click Start
#   2. On Quest 3: open WiVRn app and connect — wait for "Connection ready"
#   3. Run this script

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

# ---------------------------------------------------------------------------
# CHANGEME_ variables — fill these in before running the script
# ---------------------------------------------------------------------------

GAMING_MOUNT="CHANGEME_GAMING_MOUNT"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ "${GAMING_MOUNT}" == "CHANGEME_GAMING_MOUNT" ]]; then
    error "Fill in GAMING_MOUNT with your gaming drive mount point name.\nFind it with: lsblk -o NAME,LABEL,MOUNTPOINT\nExample: games"
fi

# --- Paths (identical to pancake launch script) ---
PREFIX="/mnt/${GAMING_MOUNT}/dcs-world"
DIR_DCS="drive_c/Program Files/Eagle Dynamics/DCS World/bin-mt"
DCS_EXE="$PREFIX/$DIR_DCS/DCS.exe"

# --- Shared env vars (runner, display, input, Wine) ---
# shellcheck source=lib/dcs-env.sh
. "$(dirname "$0")/lib/dcs-env.sh"

# --- VR (WiVRn / pressure-vessel) ---
# CRITICAL: Do NOT use XR_RUNTIME_JSON here.
# pressure-vessel (the Steam Runtime container umu-run uses) cannot see host
# filesystem paths. XR_RUNTIME_JSON silently fails inside the container.
# These two vars are the correct mechanism:
export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1

# WiVRn IPC socket path. Verify with: ls $XDG_RUNTIME_DIR/wivrn*
# while wivrn-server is running. Version variance:
#   Recent WiVRn builds:  $XDG_RUNTIME_DIR/wivrn/comp_ipc
#   Older WiVRn builds:   $XDG_RUNTIME_DIR/wivrn_comp_ipc
export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"

# --- Pre-flight check ---
preflight_check() {
    if ! systemctl --user is-active --quiet wivrn.service 2>/dev/null; then
        warn "================================================================"
        warn "WiVRn service is not running."
        warn "Start it: systemctl --user start wivrn.service"
        warn "Or open the WiVRn dashboard and click Start."
        warn "Continuing anyway — DCS may launch in pancake mode."
        warn "================================================================"
    else
        ok "WiVRn service is active"
    fi
}

# --- Launch ---
launch_vr() {
    preflight_check
    umu-run "$DCS_EXE" --no-launcher --force_enable_VR --force_OpenXR
}

usage() {
    echo "Usage: $(basename "$0") [-n]"
    echo "  -n  Launch DCS in VR mode (no launcher)"
    exit 1
}

[[ $# -eq 0 ]] && usage

[[ -f "$DCS_EXE" ]] || error "DCS executable not found: $DCS_EXE\nCheck PREFIX path"

case "$1" in
    -n) launch_vr ;;
    *)  usage ;;
esac
