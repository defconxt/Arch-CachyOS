# Storage Setup: LUKS Multi-Drive Encryption with Keyfile Auto-Unlock

## Overview

This guide covers configuring encrypted secondary drives to unlock automatically at boot using a keyfile. The system uses three drives:

| Drive | Label | Role | Mount |
|---|---|---|---|
| nvme0n1p2 | root | OS (btrfs multi-subvol) | `/` |
| nvme1n1 | gaming | Games (Steam library) | `/mnt/gaming` |
| sda | media | Media (Plex) | `/mnt/media` |

All three drives are LUKS-encrypted. **Root drive encryption is handled by the CachyOS installer and is not covered here.**

### Unlock Chain

At boot, the sequence is:

1. Bootloader (GRUB/systemd-boot) unlocks the root drive using your passphrase
2. systemd reads `/etc/crypttab` and uses the keyfile to unlock the gaming and media drives
3. systemd reads `/etc/fstab` and mounts the decrypted dm-crypt devices to their mount points

This means you only enter one passphrase at boot (for root), and the secondary drives unlock silently in the background.

---

## Prerequisites

- CachyOS or Arch Linux installed with the root drive already LUKS-encrypted
- Secondary drives (`nvme1n1`, `sda`) already partitioned and formatted with LUKS (`cryptsetup luksFormat`) — this guide covers keyfile auto-unlock only, not initial drive formatting

**Initial LUKS formatting is a destructive one-time operation** that erases all data on the drive. If you have not yet formatted your secondary drives with LUKS, refer to the [Arch Wiki dm-crypt guide](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_disk) before continuing here.

---

## Step 1: Generate the Keyfile

Generate a 2 KB random keyfile and store it in `/etc/`:

```bash
sudo dd bs=512 count=4 if=/dev/urandom of=/etc/crypto_keyfile.bin
```

Set permissions to root-only read immediately after creation:

```bash
sudo chmod 600 /etc/crypto_keyfile.bin
```

**Why 600 matters:** Some versions of systemd and cryptsetup will refuse to use a keyfile that is world-readable (permissions wider than 600). Set this before doing anything else with the file.

---

## Step 2: Add the Keyfile to Each LUKS Volume

Register the keyfile as an unlock method on each secondary drive. You will be prompted for the existing LUKS passphrase for each drive to authorize adding the new key slot.

```bash
sudo cryptsetup luksAddKey /dev/nvme1n1 /etc/crypto_keyfile.bin
sudo cryptsetup luksAddKey /dev/sda /etc/crypto_keyfile.bin
```

Each drive retains its original passphrase as a backup unlock method. The keyfile is added as an additional key slot — it does not replace the passphrase.

---

## Step 3: Embed the Keyfile in the initramfs

Edit `/etc/mkinitcpio.conf` and add the keyfile to the `FILES` array:

```
FILES=(/etc/crypto_keyfile.bin)
```

If a `FILES=()` line already exists in the file, add the path inside the parentheses. If no `FILES=` line exists, add it.

Then regenerate all initramfs presets:

```bash
sudo mkinitcpio -P
```

The `-P` flag regenerates every preset (e.g., `linux`, `linux-lts`, `linux-cachyos`) in one pass.

> **WARNING: This step is mandatory.** Without embedding the keyfile in the initramfs, it is not available during early boot and the secondary drives will not auto-unlock. crypttab will fail silently or prompt for a passphrase at the console. Always run `mkinitcpio -P` after modifying `FILES=`.

---

## Step 4: Configure /etc/crypttab

`/etc/crypttab` tells systemd which encrypted devices to open at boot and how to open them. Add the following entries:

```
# Root is handled by initramfs, not listed here
gaming  UUID=CHANGEME_GAMING_LUKS_UUID  /etc/crypto_keyfile.bin  luks
media   UUID=CHANGEME_MEDIA_LUKS_UUID   /etc/crypto_keyfile.bin  luks
```

Replace `CHANGEME_GAMING_LUKS_UUID` and `CHANGEME_MEDIA_LUKS_UUID` with the LUKS container UUIDs of the raw block devices. See [Step 6: Finding Your UUIDs](#step-6-finding-your-uuids) for how to obtain these.

**Important:** The UUIDs in crypttab are the LUKS container UUIDs — the UUID of the raw device (e.g., `/dev/nvme1n1`) before decryption, where `TYPE="crypto_LUKS"` in `lsblk -f` output. Do not use filesystem UUIDs here.

---

## Step 5: Configure /etc/fstab

`/etc/fstab` tells systemd where to mount the decrypted devices. Add entries for the secondary drives only — root entries are managed by the CachyOS installer:

```
UUID=CHANGEME_GAMING_FS_UUID  /mnt/gaming  btrfs  defaults,compress=zstd,nofail  0  0
UUID=CHANGEME_MEDIA_FS_UUID   /mnt/media   btrfs  defaults,compress=zstd,nofail  0  0
```

Replace `CHANGEME_GAMING_FS_UUID` and `CHANGEME_MEDIA_FS_UUID` with the filesystem UUIDs of the decrypted dm-crypt devices. See [Step 6: Finding Your UUIDs](#step-6-finding-your-uuids).

**Mount options explained:**

- `compress=zstd` — btrfs transparent compression. Reduces disk usage with minimal CPU overhead on modern processors.
- `nofail` — If the drive is missing or fails to mount (e.g., temporarily disconnected), the boot process continues rather than dropping to an emergency shell. Recommended for secondary drives.

---

## Step 6: Create Mount Points

```bash
sudo mkdir -p /mnt/gaming /mnt/media
```

These directories must exist before fstab can mount to them. The `-p` flag creates parent directories as needed and does not error if they already exist.

---

## Step 7: Finding Your UUIDs

There are two types of UUID involved and they must not be mixed up:

| UUID type | Where it comes from | Goes in |
|---|---|---|
| LUKS UUID | Raw block device (`/dev/nvme1n1`), `TYPE="crypto_LUKS"` | `/etc/crypttab` |
| Filesystem UUID | Decrypted dm device (`/dev/dm-0`), `TYPE="btrfs"` | `/etc/fstab` |

### Using lsblk -f

```bash
lsblk -f
```

Example output (annotated):

```
NAME        FSTYPE      LABEL  UUID                                   MOUNTPOINT
nvme1n1     crypto_LUKS        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   <- LUKS UUID -> crypttab
└─gaming    btrfs              yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy   <- FS UUID   -> fstab
sda         crypto_LUKS        aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa   <- LUKS UUID -> crypttab
└─media     btrfs              bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb   <- FS UUID   -> fstab
```

The UUID on the line for `nvme1n1` (where `FSTYPE=crypto_LUKS`) goes in crypttab. The UUID on the line for `gaming` (the dm-crypt device, where `FSTYPE=btrfs`) goes in fstab.

### Using blkid (alternative)

```bash
# LUKS UUID (for crypttab) — query the raw block device
sudo blkid /dev/nvme1n1
sudo blkid /dev/sda

# Filesystem UUID (for fstab) — query the dm-crypt device after it is open
sudo blkid /dev/mapper/gaming
sudo blkid /dev/mapper/media
```

The dm-crypt devices (`/dev/mapper/gaming`, `/dev/mapper/media`) are only visible after the drives have been unlocked. If you are setting this up before the first reboot, use `lsblk -f` instead — it shows both levels together.

---

## Step 8: Verify

Reboot and confirm the drives are mounted:

```bash
findmnt /mnt/gaming
findmnt /mnt/media
```

Check LUKS device status:

```bash
sudo cryptsetup status gaming
sudo cryptsetup status media
```

Both commands should show the device as active with the cipher, key size, and device path listed.

---

## Troubleshooting

### Drive does not unlock at boot

The drive stays locked and either prompts for a passphrase at boot or is absent after login.

1. Verify the LUKS UUID in crypttab matches the raw device:
   ```bash
   sudo blkid /dev/nvme1n1   # gaming
   sudo blkid /dev/sda       # media
   ```
   Compare the UUID in the output against the UUID in `/etc/crypttab`. A single wrong character causes a mismatch.

2. Verify the keyfile exists in the initramfs:
   ```bash
   lsinitcpio /boot/initramfs-linux.img | grep crypto_keyfile
   ```
   If no output is returned, the keyfile was not embedded. See the next section.

### Keyfile not found in initramfs

The keyfile is missing from the initramfs image.

1. Check `/etc/mkinitcpio.conf` for the FILES line:
   ```bash
   grep FILES /etc/mkinitcpio.conf
   ```
   It should read `FILES=(/etc/crypto_keyfile.bin)`.

2. Verify the keyfile exists on disk:
   ```bash
   sudo ls -la /etc/crypto_keyfile.bin
   ```

3. Regenerate the initramfs:
   ```bash
   sudo mkinitcpio -P
   ```

4. Confirm the keyfile is now in the image:
   ```bash
   lsinitcpio /boot/initramfs-linux.img | grep crypto_keyfile
   ```

### Manual mount (emergency recovery)

If auto-unlock fails and you need to mount the drives manually from a running system:

```bash
# Unlock the LUKS container
sudo cryptsetup luksOpen /dev/nvme1n1 gaming --key-file /etc/crypto_keyfile.bin
sudo cryptsetup luksOpen /dev/sda media --key-file /etc/crypto_keyfile.bin

# Mount the decrypted devices
sudo mount /dev/mapper/gaming /mnt/gaming
sudo mount /dev/mapper/media /mnt/media
```

You can also unlock with the passphrase if the keyfile is unavailable:

```bash
sudo cryptsetup luksOpen /dev/nvme1n1 gaming
```

### Verify keyfile slot exists on LUKS volume

Confirm the keyfile was successfully added as a key slot:

```bash
sudo cryptsetup luksDump /dev/nvme1n1
sudo cryptsetup luksDump /dev/sda
```

Look for multiple `Key Slot X: ENABLED` entries in the output. Slot 0 is typically the passphrase; the keyfile occupies a subsequent slot. If only one slot is enabled, the `luksAddKey` step did not complete successfully and must be re-run.

---

## Summary: UUID Reference

| Placeholder | Type | Source command | Destination |
|---|---|---|---|
| `CHANGEME_GAMING_LUKS_UUID` | LUKS container UUID | `blkid /dev/nvme1n1` | `/etc/crypttab` |
| `CHANGEME_MEDIA_LUKS_UUID` | LUKS container UUID | `blkid /dev/sda` | `/etc/crypttab` |
| `CHANGEME_GAMING_FS_UUID` | Filesystem UUID | `blkid /dev/mapper/gaming` | `/etc/fstab` |
| `CHANGEME_MEDIA_FS_UUID` | Filesystem UUID | `blkid /dev/mapper/media` | `/etc/fstab` |

After filling in all four placeholders, reboot to confirm the configuration works.
