#!/bin/bash
# fix-boot.sh — repair a non-booting Radxa Cubie A7A card in place.
# Usage:  sudo ./fix-boot.sh /dev/sdX [sd-firmware-region.img]
#   - always plants boot.scr on the EFI partition (Defect B)
#   - if a firmware image is given, also replaces the firmware region,
#     preserving the card's GPT (Defect A)
# Run from the boot-fix/ directory (needs ./boot.scr). See README.md.
set -euo pipefail

DEV="${1:?usage: sudo ./fix-boot.sh /dev/sdX [sd-firmware-region.img]}"
FW="${2:-}"
[ -b "$DEV" ] || { echo "error: $DEV is not a block device"; exit 1; }
[ -f boot.scr ] || { echo "error: run from boot-fix/ (needs ./boot.scr)"; exit 1; }
P2="${DEV}2"; [ -b "${DEV}p2" ] && P2="${DEV}p2"

echo "Target card: $DEV   EFI partition: $P2"
lsblk -o NAME,SIZE,TYPE,FSTYPE "$DEV"
read -rp "This will modify $DEV. Type YES to continue: " ok
[ "$ok" = "YES" ] || exit 1

# --- Defect A (optional): firmware region, GPT preserved -------------------
if [ -n "$FW" ]; then
    [ -f "$FW" ] || { echo "error: $FW not found"; exit 1; }
    if ! xxd -s 131076 -l 8 "$FW" | grep -q "eGON.BT0"; then
        echo "error: $FW lacks eGON.BT0 magic at 128KiB — wrong file"; exit 1
    fi
    echo "Backing up current firmware region to ./firmware-backup-$(date +%Y%m%d%H%M%S).img"
    dd if="$DEV" of="./firmware-backup-$(date +%Y%m%d%H%M%S).img" bs=512 count=32768 status=none
    echo "Writing SD-variant firmware (GPT sectors 0-33 preserved)..."
    dd if="$FW" of="$DEV" bs=512 skip=34 seek=34 count=32734 conv=fsync status=none
    echo "Firmware region replaced."
fi

# --- Defect B: boot.scr on the EFI partition -------------------------------
if ! blkid "$P2" >/dev/null 2>&1; then
    echo "EFI partition has no filesystem — creating FAT32..."
    mkfs.vfat -n efi "$P2"
fi
MNT=$(mktemp -d)
mount "$P2" "$MNT"
cp boot.scr "$MNT/boot.scr"
mkdir -p "$MNT/boot"
cp boot.scr "$MNT/boot/boot.scr"
sync
umount "$MNT"
rmdir "$MNT"
echo "boot.scr planted on EFI partition (both scan paths)."
echo "Done. Put the card in the board — it should boot to login hands-free."
