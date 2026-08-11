#!/bin/bash
# safe-update.sh — run apt updates WITHOUT letting Debian break the custom
# boot chain. Run ON the board:  sudo ./safe-update.sh
#
# Why: this image's kernel + extlinux.conf live outside apt. A plain
# `apt upgrade` can install a stock kernel and regenerate extlinux.conf
# (via u-boot-menu/flash-kernel), which kills display and boot. Images from
# 2026-08-10 onward ship apt pins that prevent this; this script verifies
# the pins, backs up the boot chain, upgrades, then PROVES nothing moved.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

PIN=/etc/apt/preferences.d/99-a7a-custom-kernel
KERNEL=$(awk '/^\tlinux/{print $2; exit}' /boot/extlinux/extlinux.conf)
CONF_SUM=$(sha256sum /boot/extlinux/extlinux.conf | cut -d' ' -f1)

# 1. pins present? (restore them if someone deleted them)
if [ ! -f "$PIN" ]; then
    echo "WARNING: apt pins missing — restoring $PIN"
    cat > "$PIN" <<'P'
Package: linux-image-*
Pin: release *
Pin-Priority: -1

Package: u-boot-menu
Pin: release *
Pin-Priority: -1

Package: flash-kernel
Pin: release *
Pin-Priority: -1
P
fi

# 2. backup the boot chain
BK=/root/bootchain-backup-$(date +%Y%m%d%H%M%S)
mkdir -p "$BK"
cp -a /boot/extlinux "$BK/"
cp -a "$KERNEL" "$BK/" 2>/dev/null || cp -a "/boot/$(basename "$KERNEL")" "$BK/"
echo "boot chain backed up to $BK"

# 3. the update itself
apt-get update
apt-get upgrade -y

# 4. prove the boot chain survived
FAIL=0
[ -f "$KERNEL" ] || [ -f "/boot/$(basename "$KERNEL")" ] || { echo "KERNEL MISSING"; FAIL=1; }
NEW_SUM=$(sha256sum /boot/extlinux/extlinux.conf | cut -d' ' -f1)
if [ "$NEW_SUM" != "$CONF_SUM" ]; then
    echo "extlinux.conf WAS MODIFIED by the upgrade — restoring backup"
    cp -a "$BK/extlinux/extlinux.conf" /boot/extlinux/extlinux.conf
    FAIL=1
fi
if dpkg -l 'linux-image-*' 2>/dev/null | grep -q '^ii'; then
    echo "WARNING: a stock Debian kernel package got installed — the pins were bypassed."
    echo "It will NOT boot by default (extlinux.conf still points at the custom kernel),"
    echo "but investigate how it got in. dpkg -l 'linux-image-*' to inspect."
fi
if [ "$FAIL" = 0 ]; then
    echo "OK: update complete, boot chain verified intact."
else
    echo "Update finished WITH boot-chain interventions (see above). Backup kept at $BK."
fi
