# Gaming Setup Guide

This guide covers gaming setup on CachyOS with Steam, Proton, and performance
optimizations. It documents the manual configuration steps that `scripts/02-gaming-setup.sh`
cannot automate, and provides reference tables you will consult repeatedly.

## Prerequisites

- Storage setup complete: see [docs/01-storage.md](01-storage.md)
- Gaming drive mounted at `/mnt/gaming`
- `yay` AUR helper installed

## Setup Script

Run `scripts/02-gaming-setup.sh` first. It handles:

- Package installation (pacman and AUR)
- Steam library directory creation (`/mnt/gaming/SteamLibrary`)
- User group membership (`audio`, `plugdev`)
- NVIDIA shader cache configuration (`~/.config/environment.d/gaming.conf`)
- Disabling `ananicy-cpp` to prevent gamemode conflicts

After the script completes, follow this guide for the manual configuration steps.

---

## 1. Package Reference

### pacman Packages

| Package | Source | Purpose |
|---------|--------|---------|
| `steam` | pacman | Valve game platform |
| `lutris` | pacman | Game launcher for non-Steam titles (Battle.net, etc.) |
| `gamemode` | pacman | CPU/GPU performance boost during games (D-Bus activated) |
| `lib32-gamemode` | pacman | 32-bit game support for gamemode |
| `mangohud` | pacman | In-game FPS/GPU/CPU overlay |
| `lib32-mangohud` | pacman | 32-bit game support for mangohud |
| `exfatprogs` | pacman | exFAT filesystem support (USB drives) |
| `obs-studio-browser` | pacman | OBS with browser source (CachyOS patched — do **not** install `obs-studio`) |

### AUR Packages

| Package | Source | Purpose |
|---------|--------|---------|
| `protonplus` | AUR | GUI app: install and manage Proton runners |
| `cachyos-gaming-meta` | AUR | Meta-package: `wine-cachyos-opt`, `umu-launcher`, `proton-cachyos-slr`, codecs |
| `rusty-path-of-building` | AUR | Path of Exile 1+2 build planner (native, no Wine) |

**Note:** `cachyos-gaming-meta` pulls in `proton-cachyos-slr` and `umu-launcher` as
dependencies — no separate install needed for those packages.

---

## 2. Proton Setup (ProtonPlus)

The setup script installs the `protonplus` package, but runner installation is a manual
GUI step. ProtonPlus downloads and manages runners into
`~/.steam/root/compatibilitytools.d/`.

**Install runners:**

1. Launch ProtonPlus from your application menu
2. Install the following runners:
   - **GE-Proton** (latest) — for standalone games and DCS World
   - **Proton-CachyOS** (latest) — native CachyOS Proton build
3. Runners install to `~/.steam/root/compatibilitytools.d/`
4. Restart Steam after installing runners

**Configure Steam default Proton:**

1. Open Steam: **Settings** -> **Compatibility**
2. Enable **Steam Play for all titles**
3. Select **proton-cachyos-slr** as the default compatibility tool

**Note:** `proton-cachyos-slr` is installed by `cachyos-gaming-meta` and appears
automatically in Steam's Proton list without ProtonPlus. ProtonPlus is used for
additional runners (GE-Proton, Proton-CachyOS native).

---

## 3. Steam Library Setup

The setup script creates `/mnt/gaming/SteamLibrary` with correct ownership. Add it
to Steam manually:

1. Open Steam: **Settings** -> **Storage**
2. Click **Add Drive**
3. Select `/mnt/gaming/SteamLibrary`
4. Set it as the **Default** library

New game installs will go to the gaming drive by default.

---

## 4. Proton Version Guide

Use this table to select the correct runner for each game or use case.

| Game / Use Case | Runner | Notes |
|-----------------|--------|-------|
| Most Steam games (default) | `proton-cachyos-slr` | Recommended default; SLR-backed |
| Anti-cheat games (EAC/BattlEye) | `proton-cachyos-slr` | Required for HELLDIVERS 2, WoW, D4, D2R |
| DCS World (standalone) | GE-Proton10-32 | Launched via `umu-run`; see [docs/04-dcs-world.md](04-dcs-world.md) |
| Star Citizen (Lutris) | Proton-GE | RSI Launcher via Lutris |
| General fallback | `proton-cachyos-slr` | Safe choice when unsure |

To set a per-game runner: right-click the game in Steam -> **Properties** ->
**Compatibility** -> force a specific compatibility tool.

---

## 5. Performance Optimizations

### 5.1 NVIDIA Shader Cache

The setup script writes `configs/gaming/gaming.conf.example` to
`~/.config/environment.d/gaming.conf`.

**Contents:**

```ini
__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
__GL_SHADER_DISK_CACHE_SIZE=10737418240
```

**What these do:**

- `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1`: Prevents the NVIDIA driver from deleting
  cached shaders when the cache exceeds its default limit. Without this, the driver
  periodically purges the cache, causing stutter on next launch while shaders recompile.
- `__GL_SHADER_DISK_CACHE_SIZE=10737418240`: Sets the cache size limit to 10 GiB
  (the default is much smaller). Games accumulate large shader caches over time;
  10 GiB prevents premature eviction.

**Changes take effect on next login** (systemd user environment via `environment.d`).

Verify the config is in place:

```bash
cat ~/.config/environment.d/gaming.conf
```

### 5.2 EPP Performance Mode (CPU Tuning)

Energy Performance Preference (EPP) sets the CPU's power/performance bias via the
`cpufreq` subsystem. This is documented only — not scripted — because the optimal
setting is CPU-specific.

Set all CPU cores to performance mode:

```bash
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference
```

**Hardware note:** Tested on Zen 5 (9800X3D). Other CPUs may differ; verify your
CPU supports EPP via `ls /sys/devices/system/cpu/cpu0/cpufreq/` before applying.

**Persistence:** This setting resets on reboot. To make it persistent, create a
systemd service or use `cpupower` with a startup service. Most users apply it
per-session before heavy gaming sessions.

### 5.3 What NOT to Enable (9800X3D-Specific)

The following CachyOS kernel options are not applicable to this hardware
configuration:

| Option | Reason to Skip |
|--------|----------------|
| V-Cache optimizer | Not applicable — 9800X3D is a single-CCD chip |
| RCU Lazy | Desktop system; no latency benefit |
| ADIOS I/O scheduler | Experimental; skip for stability |
| ananicy-cpp | Conflicts with gamemode; disabled by the setup script |

### 5.4 GameMode

`gamemode` is D-Bus/socket activated — it starts automatically when a game client
connects. There is no systemd service to enable manually.

**Activation methods:**

- `game-performance %command%` — CachyOS wrapper that sets the system power profile
  to performance for the duration of the game, and activates gamemode
- `gamemoderun %command%` — activates gamemode only, without power profile switching

The setup script disables `ananicy-cpp` to prevent conflicts. Both ananicy-cpp and
gamemode manipulate process niceness values; running both leads to repeated niceness
resets that negate the benefit of either.

Verify ananicy-cpp is disabled:

```bash
systemctl is-enabled ananicy-cpp
# Expected: disabled
```

---

## 6. Steam Launch Options Reference

Set launch options per game: right-click game in Steam -> **Properties** ->
**General** -> **Launch Options**.

| Game Type | Launch Option | Notes |
|-----------|---------------|-------|
| Most games (default) | `game-performance %command%` | CachyOS wrapper: sets power profile to performance for game duration |
| DLSS-capable games | `PROTON_DLSS_UPGRADE=1 game-performance %command%` | Enables DLSS upscaling via Proton |
| Smooth Motion (no DLSS FG) | `NVPRESENT_ENABLE_SMOOTH_MOTION=1 game-performance %command%` | NVIDIA frame interpolation alternative to DLSS Frame Generation |
| Performance overlay | `mangohud game-performance %command%` | Shows FPS, GPU, CPU stats in-game |
| Anti-cheat titles | Use `proton-cachyos-slr` runner | Set per-game in Steam Properties -> Compatibility; no launch option needed |

**Note on `game-performance`:** This wrapper is pre-installed on CachyOS via
`cachyos-settings`. It temporarily switches `power-profiles-daemon` to performance
mode for the duration of the game process and also activates gamemode.

---

## 7. Path of Building (Path of Exile)

`rusty-path-of-building` is a native Linux Path of Exile 1 and PoE2 build planner.
No Wine or emulation layer is required.

**Installation:** Handled by the setup script (AUR package).

**Launch:**

- From your application menu, search for "Path of Building"
- Or from a terminal: `rusty-path-of-building`

**First run:** The application may take a moment on first launch to download and
build its asset cache. This is normal — subsequent launches are fast.

**Desktop entry category fix:** If Path of Building does not appear in the Games
category in your application menu, edit the desktop entry:

```bash
mkdir -p ~/.local/share/applications
cp /usr/share/applications/rusty-path-of-building.desktop ~/.local/share/applications/
```

Then edit `~/.local/share/applications/rusty-path-of-building.desktop` and change the
`Categories=` line to:

```ini
Categories=Game;
```

**Scope:** Covers both PoE1 and PoE2 build planning in a single application.

---

## 8. Post-Setup Checklist

Run through this after `scripts/02-gaming-setup.sh` and the manual steps above.

- [ ] `scripts/02-gaming-setup.sh` ran without errors
- [ ] ProtonPlus launched and GE-Proton installed
- [ ] ProtonPlus launched and Proton-CachyOS installed
- [ ] Steam restarted after ProtonPlus runner installs
- [ ] Steam: `/mnt/gaming/SteamLibrary` added and set as default
- [ ] Steam: `proton-cachyos-slr` selected as default compatibility tool
- [ ] Groups: `groups` shows `audio` and `plugdev`
- [ ] Shader cache: `cat ~/.config/environment.d/gaming.conf` shows both `__GL_SHADER` vars
- [ ] ananicy-cpp: `systemctl is-enabled ananicy-cpp` returns `disabled`
- [ ] Log out and back in (for group membership to take effect)
