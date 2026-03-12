#!/usr/bin/env bash
# launch-dcs.sh — DCS World launcher for CachyOS
# See dcs-world.md for documentation.
#
# Usage:
#   launch-dcs.sh -n   no launcher (normal play)
#   launch-dcs.sh -l   with launcher
#   launch-dcs.sh -u   update DCS
#   launch-dcs.sh -r   repair DCS

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

# --- Paths ---
PREFIX="/mnt/${GAMING_MOUNT}/dcs-world"
DIR_DCS="drive_c/Program Files/Eagle Dynamics/DCS World/bin-mt"
DCS_EXE="$PREFIX/$DIR_DCS/DCS.exe"
UPDATER_EXE="$PREFIX/drive_c/Program Files/Eagle Dynamics/DCS World/bin/DCS_updater.exe"
WINE_BIN="$PREFIX/runners/wine-11.1-staging-amd64/bin/wine"

# --- Shared env vars (runner, display, input, Wine) ---
# shellcheck source=lib/dcs-env.sh
. "$(dirname "$0")/lib/dcs-env.sh"

# --- Launch ---
launch_nolauncher() {
    umu-run "$DCS_EXE" --no-launcher
}

launch_launcher() {
    umu-run "$DCS_EXE"
}

launch_update() {
    "$WINE_BIN" "$UPDATER_EXE" update
}

launch_repair() {
    "$WINE_BIN" "$UPDATER_EXE" repair
}

usage() {
    echo "Usage: $(basename "$0") [-n|-l|-u|-r]"
    echo "  -n  Launch without launcher (normal play)"
    echo "  -l  Launch with launcher"
    echo "  -u  Update DCS"
    echo "  -r  Repair DCS"
    exit 1
}

[[ $# -eq 0 ]] && usage

[[ -f "$DCS_EXE" ]] || error "DCS executable not found: $DCS_EXE\nCheck PREFIX path"

case "$1" in
    -n) launch_nolauncher ;;
    -l) launch_launcher ;;
    -u) launch_update ;;
    -r) launch_repair ;;
    *)  usage ;;
esac
