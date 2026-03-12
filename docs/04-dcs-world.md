# DCS World Setup Guide

DCS World Standalone on CachyOS using `umu-run` with `GE-Proton10-32`. Wine prefix
at `/mnt/gaming/dcs-world`. Covers automated setup, launch script, HOTAS peripherals
(VKB), TrackIR 5 head tracking, F-18C keybind migration, VR registry keys, known
issues, and a verification checklist.

---

## Architecture

```
/mnt/gaming/dcs-world/                          ← Wine prefix root
├── drive_c/
│   ├── Program Files/
│   │   └── Eagle Dynamics/
│   │       └── DCS World/
│   │           └── bin-mt/
│   │               └── DCS.exe                 ← multithreaded executable (always use this)
│   └── users/CHANGEME_USERNAME/
│       └── Saved Games/
│           ├── DCS/                            ← actual config, logs, mods
│           └── DCS World -> DCS               ← symlink (required for settings persistence)
~/.config/dcs-on-linux/                         ← launcher config dir
~/.local/bin/launch-dcs.sh                      ← deployed launch script
~/.local/bin/linuxtrackx-ir.AppImage           ← LinuxTrack (TrackIR 5 bridge)
/etc/udev/rules.d/40-vkb.rules                 ← VKB HOTAS udev permissions
```

---

## Prerequisites

- Phase 2 gaming setup complete: see [docs/02-gaming.md](02-gaming.md)
  (`scripts/02-gaming-setup.sh` run, packages installed)
- GE-Proton10-32 installed via ProtonPlus (documented in docs/02-gaming.md)
- DCS World Standalone installer run, game installed to `/mnt/gaming/dcs-world`
  before running the setup script — the script configures the prefix but does not
  install the game itself

---

## Automated Setup

Run `scripts/04-dcs-setup.sh` after installing DCS to the prefix. The script is
idempotent — safe to re-run after reprovisioning or GE-Proton updates.

```bash
./scripts/04-dcs-setup.sh
```

**What the script does (9 steps):**

| Step | Function | What it does |
|------|----------|-------------|
| 1 | `step_config_dir()` | Creates `~/.config/dcs-on-linux/` with `prefix.cfg` and `firstrun.cfg` |
| 2 | `step_winetricks()` | Installs Wine dependencies into the prefix |
| 3 | `step_registry()` | Injects VR OpenXR registry keys for RTX 5090 (WiVRn runtime) |
| 4 | `step_symlink()` | Creates `DCS World → DCS` symlink in Saved Games |
| 5 | `step_options_lua()` | Fixes `options.lua` write permissions (chmod 644) |
| 6 | `step_udev()` | Installs VKB HOTAS udev rules and reloads |
| 7 | `step_launch_script()` | Copies `04-dcs-launch.sh` to `~/.local/bin/launch-dcs.sh` |
| 8 | `step_desktop_entry()` | Creates `~/.local/share/applications/dcs-world.desktop` |
| 9 | `step_linuxtrack()` | Downloads LinuxTrack AppImage, installs Wine bridge, creates desktop entry |

---

## Manual Setup Reference

If not using the setup script, these are the required steps in order. The script
automates all of them.

### Step 1: Winetricks Dependencies

Installs the DX11 compiler, Visual C++ runtime, fonts, and audio components that
DCS requires to run.

```bash
export WINEPREFIX=/mnt/gaming/dcs-world
winetricks d3dcompiler_47 vcrun2022 corefonts xact_x64 dxvk win10 consolas
```

### Step 2: Saved Games Symlink

DCS saves config to `Saved Games/DCS` but looks for settings at `Saved Games/DCS World`.
Without this symlink, settings do not persist between sessions.

```bash
ln -sf \
  "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS" \
  "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS World"
```

### Step 3: options.lua Permissions

DCS sometimes creates `options.lua` as read-only (0444), preventing settings saves.

```bash
chmod 644 "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS/Config/options.lua"
```

Note: the file may not exist on first run — it is created at first DCS launch. The
setup script warns if it is absent and skips silently.

### Step 4: VR Registry Keys (RTX 5090)

Required for OpenXR to select the correct Vulkan device. RTX 5090 VID/PID: `10DE:2B85`.

Create `/tmp/dcs-vr.reg`:

```
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\VR]
"openxr_vulkan_device_vid"=dword:000010de
"openxr_vulkan_device_pid"=dword:00002b85
"state"=dword:00000001
"openxr_runtime"="wivrn"
```

Apply:

```bash
export WINEPREFIX=/mnt/gaming/dcs-world
wine regedit /tmp/dcs-vr.reg
```

### Step 5: VKB HOTAS udev Rules

Grants your user access to VKB devices without requiring root.

```bash
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="231d", MODE="0664", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="231d", MODE="0664", TAG+="uaccess"' \
  | sudo tee /etc/udev/rules.d/40-vkb.rules

sudo udevadm control --reload-rules
sudo udevadm trigger
```

Replug your VKB devices after installing the rules.

### Step 6: Config Directory

```bash
mkdir -p ~/.config/dcs-on-linux
echo "WINEPREFIX=/mnt/gaming/dcs-world" > ~/.config/dcs-on-linux/prefix.cfg
echo "firstrun=done" > ~/.config/dcs-on-linux/firstrun.cfg
```

---

## Launch Script Usage

Reference: `scripts/04-dcs-launch.sh` (deployed to `~/.local/bin/launch-dcs.sh`).

```bash
~/.local/bin/launch-dcs.sh -n   # normal play (no launcher) — use this for flying
~/.local/bin/launch-dcs.sh -l   # with launcher
~/.local/bin/launch-dcs.sh -u   # update DCS
~/.local/bin/launch-dcs.sh -r   # repair DCS
```

| Flag | Action |
|------|--------|
| `-n` | Normal play (no launcher) |
| `-l` | With launcher |
| `-u` | Update DCS |
| `-r` | Repair DCS |

### Key Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `WINEPREFIX` | `/mnt/gaming/dcs-world` | Wine prefix path |
| `PROTONPATH` | `~/.local/share/Steam/compatibilitytools.d/GE-Proton10-32` | GE-Proton runner path |
| `GAMEID` | `umu-dcs-world` | umu-run game identifier |
| `PROTON_ENABLE_WAYLAND` | `0` | Forces XWayland — required for fullscreen without taskbar bleed on Wayland |
| `SDL_JOYSTICK_HIDAPI` | `0` | Prevents HOTAS devices registering twice (joydev + HIDAPI = phantom duplicates in DCS) |
| `WINEDLLOVERRIDES` | `wbemprox=n;NPClient64=b;NPClient=b;FreeTrackClient=b` | TrackIR bridge DLL overrides; `wbemprox=n` suppresses WMI log spam |
| `WINE_SIMULATE_WRITECOPY` | `1` | Prevents DCS write failures on btrfs copy-on-write filesystem paths |

---

## TrackIR 5 / LinuxTrack

### Setup

The setup script (`step_linuxtrack()`) handles this automatically. Manual steps:

```bash
# Download AppImage
wget -O ~/.local/bin/linuxtrackx-ir.AppImage \
  https://github.com/uglyDwarf/linuxtrack/releases/download/v0.99.29/linuxtrackx-ir-0.99.29-x86_64.AppImage
chmod +x ~/.local/bin/linuxtrackx-ir.AppImage

# Install Wine bridge into DCS prefix
export WINEPREFIX=/mnt/gaming/dcs-world
~/.local/bin/linuxtrackx-ir.AppImage --install-wine-bridge
```

The Wine bridge intercepts TrackIR DLL calls from DCS and routes them to the
LinuxTrack AppImage running on the host.

### Launch Order (Critical)

TrackIR **must** be started and tracking **before** DCS launches. DCS only
initializes the TrackIR connection at startup — if LinuxTrack is not active at
that moment, head tracking is unavailable for the entire session.

1. Launch `~/.local/bin/linuxtrackx-ir.AppImage`
2. Click **Start Tracking** — wait for head movement to register in the UI
3. Launch DCS: `~/.local/bin/launch-dcs.sh -n`

### DLL Overrides

Set in `launch-dcs.sh` via `WINEDLLOVERRIDES`:

```
NPClient64=b    ← TrackIR 64-bit bridge
NPClient=b      ← TrackIR 32-bit bridge
FreeTrackClient=b ← FreeTrack protocol fallback
```

`b` = builtin (Wine's stub that LinuxTrack intercepts). `n` = native (system DLL).
Do not change these values.

### Confirming TrackIR Detection

After DCS loads, check `dcs.log`:

```
INFO  INPUT: created [TrackIR]
```

If this line is absent, LinuxTrack was not tracking when DCS started. Quit DCS,
verify LinuxTrack is showing head movement, then relaunch.

---

## VKB HOTAS Device Reference

### Udev Rules File

```
/etc/udev/rules.d/40-vkb.rules
```

**Contents:**

```
SUBSYSTEM=="usb", ATTRS{idVendor}=="231d", MODE="0664", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="231d", MODE="0664", TAG+="uaccess"
```

All VKB devices share VID `231d`. The rules grant access via `uaccess` (automatic
seat-local access) rather than a fixed group.

### Device Reference Table

| Device | USB VID:PID | Linux GUID |
|--------|-------------|------------|
| T-Rudder | `231d:011f` | `9E573ED6-7734-11d2-8D4A-23903FB6BDF7` |
| S-TECS Modern Throttle Max Stem | `231d:012e` | `9E573EDE-7734-11d2-8D4A-23903FB6BDF7` |
| Space Gunfighter (stick) | `231d:0126` | `9E573EDF-7734-11d2-8D4A-23903FB6BDF7` |

VKB controller bindings are stored in firmware. No Linux-side axis or button
configuration is needed beyond udev permissions.

### Duplicate Device Fix

On Linux, Wine registers HOTAS devices twice: once via joydev and once via HIDAPI.
This causes each device to appear twice in the DCS controls screen. Attempting to
rebind with phantom duplicates present causes a crash-to-desktop (CTD).

Fix is applied in `launch-dcs.sh`:

```bash
export SDL_JOYSTICK_HIDAPI=0
```

This forces SDL to use joydev only, eliminating the duplicates.

**Detection:** If `SDL_JOYSTICK_HIDAPI=0` is not set, `dcs.log` will show the
throttle appearing twice with two different GUIDs on startup.

---

## F-18C Keybind Migration (Windows to Linux)

### Bind File Location

```
/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS/Config/Input/FA-18C_hornet/joystick/
```

### Process

Copy your Windows `.diff.lua` files from your Windows DCS installation into this
directory, then rename them from Windows GUIDs to Linux GUIDs.

### GUID Mapping Table

> **Find your Windows GUIDs** in your DCS `dcs.log` after connecting your controllers on
> Windows. Look for `INPUT: created [...]` lines — the GUID in braces is the Windows GUID.

| Device | Windows GUID | Linux GUID |
|--------|-------------|------------|
| S-TECS Throttle | `<YOUR_JOYSTICK_GUID>` | `9E573EDE-7734-11d2-8D4A-23903FB6BDF7` |
| T-Rudder | `<YOUR_JOYSTICK_GUID>` | `9E573ED6-7734-11d2-8D4A-23903FB6BDF7` |
| Space Gunfighter | `<YOUR_JOYSTICK_GUID>` | `9E573EDF-7734-11d2-8D4A-23903FB6BDF7` |

### Rename Commands

```bash
cd "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS/Config/Input/FA-18C_hornet/joystick"

# S-TECS Throttle — replace <YOUR_STECS_GUID> with the Windows GUID from dcs.log
mv "<YOUR_STECS_GUID>.diff.lua" \
   "9E573EDE-7734-11d2-8D4A-23903FB6BDF7.diff.lua"

# T-Rudder — replace <YOUR_TRUDDER_GUID> with the Windows GUID from dcs.log
mv "<YOUR_TRUDDER_GUID>.diff.lua" \
   "9E573ED6-7734-11d2-8D4A-23903FB6BDF7.diff.lua"

# Space Gunfighter — replace <YOUR_GUNFIGHTER_GUID> with the Windows GUID from dcs.log
mv "<YOUR_GUNFIGHTER_GUID>.diff.lua" \
   "9E573EDF-7734-11d2-8D4A-23903FB6BDF7.diff.lua"
```

### Throttle Axis Mapping Table

Linux axis names map 1:1 to DCS `JOY_` keys for the S-TECS. No `axisDiffs` changes
required in the `.diff.lua` files — the axis identifiers work as-is after the GUID
rename.

| Physical Control | evtest Axis | DCS JOY_ Key |
|-----------------|-------------|--------------|
| Left throttle | ABS_Y (code 1) | JOY_Y |
| Right throttle | ABS_X (code 0) | JOY_X |
| Scroll wheel / Zoom | ABS_Z (code 2) | JOY_Z |
| TDC Horizontal | ABS_RX (code 3) | JOY_RX |
| TDC Vertical | ABS_RY (code 4) | JOY_RY |

Verify axis assignments with `evtest /dev/input/by-id/usb-VKB-Sim...-event-joystick`
and move physical controls to confirm the mapping before flying.

### Confirming Device Detection at Launch

After DCS loads, check `dcs.log` for INPUT lines:

```
INFO  INPUT: created [Sim (C) Alex Oz 2023 VKBSim T-Rudder] ... {9E573ED6-7734-11d2-8D4A-23903FB6BDF7}
INFO  INPUT: created [ VKBSim Space Gunfighter ] ... {9E573EDF-7734-11d2-8D4A-23903FB6BDF7}
INFO  INPUT: created [S-TECS MODERN THROTTLE MAX STEM ] ... {9E573EDE-7734-11d2-8D4A-23903FB6BDF7}
INFO  INPUT: created [TrackIR]
```

If the throttle appears twice with different GUIDs, `SDL_JOYSTICK_HIDAPI=0` is not set.

---

## VR Mode (WiVRn + Meta Quest 3)

> **Prerequisites:** Before using VR mode below, complete the WiVRn setup in
> [docs/07-vr.md](07-vr.md) — WiVRn installed, Quest 3 paired.

### Session Launch Order

DCS initializes the OpenXR runtime at startup. If WiVRn is not serving when DCS
starts, DCS silently falls back to desktop (pancake) mode. Follow this order every
session:

1. **Start WiVRn** — open the WiVRn dashboard (`wivrn-dashboard`) and click Start,
   or:
   ```bash
   systemctl --user start wivrn.service
   ```
2. **Connect Quest 3** — open the WiVRn app on the headset, connect to PC, wait for
   "Connection ready"
3. **Launch DCS VR** — run the VR launch script:
   ```bash
   launch-dcs-vr.sh -n
   ```
   Or use the "DCS World (VR)" desktop entry.

### How the VR Stack Works

```
DCS.exe (OpenVR game, running inside Proton/pressure-vessel)
    → xrizer (OpenVR→OpenXR bridge — translates DCS's calls)
    → WiVRn Monado runtime (host, exposed via PRESSURE_VESSEL_FILESYSTEMS_RW)
    → Wi-Fi 6
    → Meta Quest 3 (AV1 decode)
```

The launch script sets two critical environment variables:

- `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` — tells umu-run's container to
  import the host OpenXR runtime
- `PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/wivrn/comp_ipc` — mounts the
  WiVRn socket into the container

**Do NOT set `XR_RUNTIME_JSON`** — pressure-vessel cannot see host filesystem
paths; it silently fails.

### DCS VR Graphics Settings (Starting Point)

Tested starting values for RTX 5090 + Quest 3 via WiVRn. Baseline only — the RTX
5090 has significant headroom to push higher.

A full VR settings block is available in `configs/vr/dcs-vr-options.lua.example` —
merge it into your `options.lua` or use it as a reference.

| Setting | Value | Notes |
|---------|-------|-------|
| Mirror Sequential | OFF | Prevents tearing in mirror window |
| Cockpit Display Resolution | 2048 | Good quality without excess VRAM cost |
| Every Frame | ON | Required for smooth VR rendering |
| MSAA | 4× | Solid anti-aliasing baseline |
| HMD Mask | ON | Saves GPU on peripheral pixels |
| Quad Views | ON | Foveated rendering — center high res, periphery lower |
| Track Eye | ON | Eye tracking for quad views (Quest 3 has eye tracking) |
| DLSS | Quality | Use with RTX 5090; off if judder appears |
| Depth of Field | OFF | High GPU cost in VR; causes discomfort |
| Pixel Density | 1.0 | Do NOT stack with WiVRn's resolution setting — WiVRn already renders at Quest 3 native res (2064×2208). PD>1.0 double-scales. |
| Scale GUI | 1.5–2.0 | GUI elements are small in VR; increase for readability |

### Verifying VR is Active

After launch, check `dcs.log`:

```bash
grep -i "openxr\|wivrn\|vr mode" "$WINEPREFIX/drive_c/users/$USER/Saved Games/DCS/Logs/dcs.log" | tail -20
```

Look for lines referencing OpenXR initialization and WiVRn. Absence of these lines
means DCS launched in pancake mode.

### Known Issues and Gotchas

- **Wrong Saved Games path:** DCS writes to `Saved Games/DCS` (no suffix) — not
  `Saved Games/DCS World`. Any script touching logs or keybinds must use the `DCS`
  directory name.
- **HOTAS axis swap after reboot:** VKB HOTAS GUIDs can re-enumerate after USB
  changes. Verify bindings before each VR session after a reboot.
- **WiVRn version mismatch:** After `pacman -Syu`, check that
  `pacman -Qi wivrn-server | grep Version` still matches the sideloaded Quest APK.
  Mismatch = connection failure.
- **Head tracking latency on NVIDIA:** A known baseline latency exists with
  Monado-based runtimes on NVIDIA 565+ drivers. Not misconfiguration — expected
  behavior.

### See Also

- [docs/07-vr.md](07-vr.md) — WiVRn system setup, dashboard settings, pairing
  procedure
- [scripts/04-dcs-launch-vr.sh](../scripts/04-dcs-launch-vr.sh) — the VR launch
  script (source)
- [scripts/07-vr-setup.sh](../scripts/07-vr-setup.sh) — WiVRn system install script

---

## Log Location and Kill Commands

### DCS Log

```bash
cat "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS/Logs/dcs.log"
```

The log captures INPUT device detection, shader loading, and error messages. Check
it first when diagnosing HOTAS, TrackIR, or performance issues.

### Kill Commands

```bash
# Kill DCS process
pkill -9 -f DCS.exe

# Force-stop the Wine server for the prefix (use when DCS hangs and pkill is insufficient)
WINEPREFIX="/mnt/gaming/dcs-world" wineserver -k
```

---

## Known Issues and Gotchas

| Issue | Detail |
|-------|--------|
| Duplicate HOTAS devices in DCS | `SDL_JOYSTICK_HIDAPI=0` in launch script. Wine registers devices via both joydev and HIDAPI without this. Attempting to rebind with duplicates causes CTD. |
| Settings not persisting | `DCS World → DCS` symlink missing, or `options.lua` is read-only (0444). Fix with `chmod 644`. |
| TrackIR not detected | LinuxTrack must be started and tracking **before** DCS launches. DCS only initializes the TrackIR connection at startup. |
| DX11 reports as ATI adapter | `ATI Adapter NVIDIA GeForce RTX 5090` in log — cosmetic. Wine's DX11 backend reports via the AGS (AMD GPU Services) path regardless of GPU vendor. |
| NvAPI not found | `NvAPI_Initialize Error: NVAPI_LIBRARY_NOT_FOUND` in log is expected. Wine does not implement NvAPI natively. No functional impact on DCS. |
| FXO shader cache path | DCS loads shaders from `c:/users/steamuser/saved games/dcs/fxo`. Normal — refers to the prefix user path, not a Steam install. |
| HTTP NORESULT errors | `ASYNCNET: HTTP request NORESULT failed with error 7` — DCS trying to phone home. Expected on offline or LAN sessions. |
| Afghanistan terrain zip errors | `No suitable driver found to mount modellighteffects.texture.zip` — cosmetic, terrain renders correctly. Known DCS bug. |
| bin vs bin-mt | Always use `bin-mt/DCS.exe`. The single-threaded `bin/DCS.exe` exists but offers no reason to use it on modern hardware. |

---

## Verification Checklist

Run these after setup to confirm everything is in place before launching DCS.

```bash
# VKB devices detected by kernel
ls /dev/input/by-id/ | grep -i vkb

# udev permissions on VKB devices (look for crw-rw---- or similar with uaccess)
stat /dev/input/by-id/usb-VKB-Sim*-joystick

# DCS Wine prefix exists
ls /mnt/gaming/dcs-world/drive_c/

# Saved Games symlink (DCS World -> DCS should appear)
ls -la "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/"

# options.lua writable (should be -rw-r--r-- / 644)
ls -la "/mnt/gaming/dcs-world/drive_c/users/$USER/Saved Games/DCS/Config/options.lua"

# GE-Proton10-32 present
ls ~/.local/share/Steam/compatibilitytools.d/ | grep GE-Proton

# LinuxTrack AppImage present and executable
ls -la ~/.local/bin/linuxtrackx-ir.AppImage

# Launch script present and executable
ls -la ~/.local/bin/launch-dcs.sh
```
