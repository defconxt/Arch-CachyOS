# Battle.net via Lutris

This guide walks through installing Battle.net and all five Blizzard titles on CachyOS
using Lutris with the `proton-cachyos-slr` runner and `umu-launcher`.

> **Note:** This guide is entirely GUI-driven. No setup script is needed for Battle.net.

All five titles (World of Warcraft, WoW Classic, Diablo IV, Diablo II: Resurrected,
StarCraft II) are confirmed working with this configuration.

---

## Prerequisites

The following dependencies are installed by `scripts/02-gaming-setup.sh` and the
Phase 2 guide. Confirm they are in place before continuing.

| Dependency | Installed by | Verify |
|------------|-------------|--------|
| `lutris` | `scripts/02-gaming-setup.sh` (pacman) | `lutris --version` |
| `proton-cachyos-slr` | `cachyos-gaming-meta` (Phase 2) | appears in Lutris runners list |
| `umu-launcher` | `cachyos-gaming-meta` (Phase 2) | `umu-run --version` |
| `/mnt/gaming` mounted | Phase 1 storage setup | `findmnt /mnt/gaming` |

See [docs/01-storage.md](01-storage.md) for storage setup and
[docs/02-gaming.md](02-gaming.md) for the gaming setup script.

---

## Step 1: Download Battle.net Setup Executable

Download the Battle.net installer from the official Blizzard website:

1. Navigate to [https://www.blizzard.com/en-us/apps/battle.net/desktop](https://www.blizzard.com/en-us/apps/battle.net/desktop)
2. Download `Battle.net-Setup.exe`
3. Note the download path — you will point Lutris to this file in the next step

---

## Step 2: Create the Lutris Prefix

1. Open Lutris from your application menu
2. Click the **+** button (Add Game) in the toolbar
3. Select **Install a Windows game from media or setup file**
4. Fill in the game details:
   - **Name:** `Battle.net`
   - **Runner:** `Wine`
5. In the **Game Options** tab:
   - **Executable:** point to `Battle.net-Setup.exe` (the file downloaded in Step 1)
   - **Wine prefix:** set to your desired prefix location, e.g. `~/Games/battlenet`
6. In the **Runner Options** tab:
   - **Wine version:** select `proton-cachyos-slr` from the dropdown

   If `proton-cachyos-slr` does not appear, open **Lutris** -> **Manage Runners** ->
   **Wine** and confirm it is installed.

7. Click **Save**, then click **Play** to run the installer
8. Complete the Battle.net installation in the GUI that appears

**Finding your prefix path later:** If you need to confirm the exact prefix path Lutris
created, right-click the Battle.net entry -> **Configure** -> **Game Options** ->
**Wine prefix**.

---

## Step 3: Map the W: Drive

The W: drive mapping lets Battle.net see `/mnt/gaming` as a Windows drive letter,
so you can install games directly to the gaming drive without filling the OS drive.

Set a variable for your prefix path (replace with your actual path if different):

```bash
BATTLENET_PREFIX="${HOME}/Games/battlenet"
```

Create the symlink:

```bash
ln -s /mnt/gaming "${BATTLENET_PREFIX}/dosdevices/w:"
```

Verify the symlink was created:

```bash
ls -la "${BATTLENET_PREFIX}/dosdevices/w:"
# Expected: w: -> /mnt/gaming
```

If Lutris placed the prefix elsewhere, check the actual path first:

```bash
# Lutris > right-click Battle.net > Configure > Game Options > Wine prefix
```

---

## Step 4: Configure Game Install Paths

Before installing each title, open Battle.net settings and set the install directory:

1. Launch Battle.net from Lutris
2. Click the **Blizzard logo** -> **Settings** -> **Game Install/Update**
3. Set **Default Install Directory** to `W:\gaming\`

Install each title from its respective Battle.net tab, using the install paths in the
table below. Battle.net will place each game in a subdirectory of `W:\gaming\`
automatically if you set the default to `W:\gaming\`.

### Game Install Paths

| Title | Install Path on W: |
|-------|-------------------|
| World of Warcraft | `W:\gaming\World of Warcraft` |
| WoW Classic | `W:\gaming\World of Warcraft` (same install — Classic is a launcher option inside WoW) |
| Diablo IV | `W:\gaming\Diablo IV` |
| Diablo II: Resurrected | `W:\gaming\Diablo II Resurrected` |
| StarCraft II | `W:\gaming\StarCraft II` |

**Note:** WoW Classic does not have a separate installation. After installing World of
Warcraft, WoW Classic appears as a version selector inside the WoW tab in Battle.net.

---

## Step 5: Confirm All Titles Work

All five titles are confirmed working with `proton-cachyos-slr` and the W: drive
configuration described above. For each title:

1. Select the game in Battle.net and click **Play**
2. The game window should appear without an immediate crash
3. Confirm you can reach the login screen or character select

**Title-specific notes:**

| Title | Notes |
|-------|-------|
| World of Warcraft | Launches directly to login screen. No quirks. |
| WoW Classic | Select **WoW Classic** from the version dropdown in Battle.net before clicking Play. Same binary path as retail WoW. |
| Diablo IV | First launch compiles shaders — expect a longer initial load. Normal on subsequent launches. |
| Diablo II: Resurrected | First launch performs shader compilation. Allow extra time before the main menu appears. |
| StarCraft II | Launches directly to main menu. No quirks. |

---

## Troubleshooting

### Battle.net updater hangs or spins indefinitely

The updater process gets stuck; the progress bar does not advance.

1. Kill the Wine server:
   ```bash
   BATTLENET_PREFIX="${HOME}/Games/battlenet"
   WINEPREFIX="${BATTLENET_PREFIX}" wineserver -k
   ```
2. Close Lutris completely
3. Relaunch Battle.net from Lutris

### Games not seeing the gaming drive (W: not available inside Battle.net)

Battle.net install path dropdown does not show `W:\` or the path is missing.

1. Verify the symlink exists:
   ```bash
   BATTLENET_PREFIX="${HOME}/Games/battlenet"
   ls -la "${BATTLENET_PREFIX}/dosdevices/w:"
   ```
   Expected: `w: -> /mnt/gaming`

2. If the symlink is missing, recreate it:
   ```bash
   ln -s /mnt/gaming "${BATTLENET_PREFIX}/dosdevices/w:"
   ```

3. Restart Battle.net from Lutris

### proton-cachyos-slr not showing in Lutris runner list

The runner dropdown in Lutris Runner Options shows only standard Wine versions.

1. Open Lutris
2. Navigate to **Manage Runners** (top-left menu icon -> Manage Runners)
3. Select **Wine** from the list
4. Confirm `proton-cachyos-slr` appears and is marked as installed
5. If missing, check that `cachyos-gaming-meta` is installed:
   ```bash
   pacman -Q cachyos-gaming-meta
   ```
   Reinstall if necessary: `sudo pacman -S cachyos-gaming-meta`

### Prefix path mismatch

If you moved the prefix or are unsure of the path, always check Lutris first:

```
Lutris -> right-click Battle.net -> Configure -> Game Options -> Wine prefix
```

Use whatever path Lutris shows as the value for `BATTLENET_PREFIX` in the commands above.
