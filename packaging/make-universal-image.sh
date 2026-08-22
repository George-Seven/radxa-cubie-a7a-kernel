#!/bin/bash
# make_universal_v4.sh — build the 2026-08-22 universal image from the golden-v3
# master: bakes in the kernel .debs and the RGMII tx-delay fix, adds first-boot
# auto-expand, then shrinks to fit any 16GB+ card.
# Adapted from make_universal.sh (2026-08-11). Every destructive step is gated on
# verified math. Works on a decompressed COPY; the master .xz is never touched.
set -euo pipefail

WORK=${WORK:?set WORK to a decompressed golden image (a working COPY)}
DEBS=${DEBS:?set DEBS to the directory holding the four .deb files}
OUTDIR=${OUTDIR:-$(dirname "$WORK")}
FINAL="$OUTDIR/radxa-cubie-a7a_debian13-custom-6.6.98_universal_20260822.img"
SECTOR=512
MNT=/tmp/uni4
ETH=/soc@3000000/ethernet@4500000

msg(){ echo; echo "=== $*"; }

msg "[1/9] attach loop"
LOOP=$(losetup -f --show -P "$WORK")
echo "loop: $LOOP"
cleanup(){
    umount "$MNT/dev/pts" 2>/dev/null || true
    umount "$MNT/dev"     2>/dev/null || true
    umount "$MNT/proc"    2>/dev/null || true
    umount "$MNT/sys"     2>/dev/null || true
    umount "$MNT"         2>/dev/null || true
    losetup -d "$LOOP"    2>/dev/null || true
}
trap cleanup EXIT

msg "[2/9] fsck + measure"
e2fsck -f -y "${LOOP}p3" || true
BLOCK=$(dumpe2fs -h "${LOOP}p3" 2>/dev/null | awk '/^Block size:/{print $3}')
USED=$(dumpe2fs -h "${LOOP}p3" 2>/dev/null | awk '/^Block count:/{bc=$3} /^Free blocks:/{fb=$3} END{print bc-fb}')
echo "block=$BLOCK used_blocks=$USED (~$((USED*BLOCK/1024/1024)) MB used)"

msg "[3/9] mount + prepare arm64 chroot"
mkdir -p "$MNT" && mount "${LOOP}p3" "$MNT"
cp /usr/bin/qemu-aarch64-static "$MNT/usr/bin/" 2>/dev/null || true
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts" 2>/dev/null || true
mount -t proc  proc "$MNT/proc"
mount -t sysfs sys  "$MNT/sys"
echo "arm64 exec test:"; chroot "$MNT" /bin/uname -m

msg "[4/9] install the kernel .debs inside the image"
mkdir -p "$MNT/tmp/debs"
cp "$DEBS"/*.deb "$MNT/tmp/debs/"
ls -la "$MNT/tmp/debs/"
chattr -i "$MNT/boot/extlinux/extlinux.conf" 2>/dev/null || true
if ! chroot "$MNT" /bin/bash -c "dpkg -i /tmp/debs/*.deb" 2>&1 | tee /tmp/dpkg_out.txt | grep -E "Unpacking|Setting up|dpkg:"; then
    echo "dpkg reported problems:"; cat /tmp/dpkg_out.txt; fi
if grep -qE "^dpkg: (error|dependency)" /tmp/dpkg_out.txt; then
    echo "FATAL: dpkg could not configure every package"; cat /tmp/dpkg_out.txt; exit 1
fi
echo "--- installed:"
chroot "$MNT" /bin/bash -c "dpkg -l | grep -E '^ii  (linux-image-6.6.98-a7a|linux-dtb-6.6.98-a7a|linux-headers-6.6.98-a7a|a7a-board-config) ' | awk '{print \$2, \$3}'"
rm -rf "$MNT/tmp/debs"

msg "[5/9] tx-delay: every device tree in the image"
for f in $(find "$MNT/usr/lib" -name 'sun60i-a733-cubie-a7a*.dtb' 2>/dev/null); do
    cur=$(fdtget "$f" $ETH tx-delay 2>/dev/null || echo "-")
    if [ "$cur" != "-" ] && [ "$cur" != "9" ]; then
        fdtput -t i "$f" $ETH tx-delay 9
        echo "   ${f#$MNT}: $cur -> $(fdtget "$f" $ETH tx-delay)"
    else
        echo "   ${f#$MNT}: already $cur"
    fi
done

msg "[6/9] first-boot auto-expand + armor exception"
cat > "$MNT/usr/local/sbin/firstboot-expand.sh" <<'EXP'
#!/bin/bash
# Grows partition 3 + filesystem to fill the card, once, then disables itself.
set -e
DISK=/dev/mmcblk0
PART=${DISK}p3
echo ", +" | sfdisk -N 3 --no-reread --force "$DISK" || true
partprobe "$DISK" || partx -u "$DISK" || true
resize2fs "$PART"
systemctl disable firstboot-expand.service
rm -f /etc/systemd/system/firstboot-expand.service /usr/local/sbin/firstboot-expand.sh
EXP
chmod +x "$MNT/usr/local/sbin/firstboot-expand.sh"
cat > "$MNT/etc/systemd/system/firstboot-expand.service" <<'SVC'
[Unit]
Description=One-time filesystem expansion to fill the SD card
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/firstboot-expand.sh
[Install]
WantedBy=multi-user.target
SVC
mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/firstboot-expand.service \
       "$MNT/etc/systemd/system/multi-user.target.wants/firstboot-expand.service"
echo "   firstboot-expand installed + enabled"

# the armor pins linux-image-* to -1; make our own package an explicit exception
# so a future apt-based update of it is possible (dpkg -i works regardless).
if [ -f "$MNT/etc/apt/preferences.d/99-boot-chain-armor" ] && \
   ! grep -q "linux-image-6.6.98-a7a" "$MNT/etc/apt/preferences.d/99-boot-chain-armor"; then
cat >> "$MNT/etc/apt/preferences.d/99-boot-chain-armor" <<'PIN'

# Exception: this image's own packaged kernel, maintained at
# github.com/Rabs9/radxa-cubie-a7a-kernel, is not part of the blanket ban above.
Package: linux-image-6.6.98-a7a
Pin: release *
Pin-Priority: 100
PIN
echo "   armor exception added for linux-image-6.6.98-a7a"
fi

msg "[7/9] clean for distribution"
chroot "$MNT" /bin/bash -c "apt-get clean" 2>/dev/null || true
rm -rf "$MNT"/var/lib/apt/lists/* 2>/dev/null || true
find "$MNT/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -rf "$MNT"/var/log/journal/* 2>/dev/null || true
rm -f  "$MNT"/home/radxa/core.* "$MNT"/root/core.* 2>/dev/null || true
rm -f  "$MNT"/home/radxa/.bash_history "$MNT"/root/.bash_history 2>/dev/null || true
: > "$MNT/etc/machine-id" 2>/dev/null || true
rm -f "$MNT/var/lib/dbus/machine-id" 2>/dev/null || true
rm -f "$MNT/usr/bin/qemu-aarch64-static"
sync
echo "   cleaned; rootfs now $(df -h "$MNT" | awk 'NR==2{print $3}') used"

msg "[8/9] unmount + shrink (math-gated)"
umount "$MNT/dev/pts" 2>/dev/null || true
umount "$MNT/dev"; umount "$MNT/proc"; umount "$MNT/sys"; umount "$MNT"
e2fsck -f -y "${LOOP}p3" || true
USED2=$(dumpe2fs -h "${LOOP}p3" 2>/dev/null | awk '/^Block count:/{bc=$3} /^Free blocks:/{fb=$3} END{print bc-fb}')
TARGET_BLOCKS=$(( USED2 + (1536*1024*1024)/BLOCK ))
echo "used_now=$USED2 target=$TARGET_BLOCKS blocks (~$((TARGET_BLOCKS*BLOCK/1024/1024)) MB)"
resize2fs "${LOOP}p3" "$TARGET_BLOCKS"
e2fsck -f -y "${LOOP}p3" || true
NEWFS_BLOCKS=$(dumpe2fs -h "${LOOP}p3" 2>/dev/null | awk '/^Block count:/{print $3}')
echo "fs now $NEWFS_BLOCKS blocks = $((NEWFS_BLOCKS*BLOCK/1024/1024)) MB"

P3_START=$(partx -g -o START -n 3 "$LOOP" | tr -d ' ')
FS_SECTORS=$(( NEWFS_BLOCKS * BLOCK / SECTOR ))
NEW_END=$(( P3_START + FS_SECTORS + 2048 ))
IMG_SECTORS=$(( $(stat -c %s "$WORK") / SECTOR ))
echo "p3_start=$P3_START fs_sectors=$FS_SECTORS new_end=$NEW_END img_sectors=$IMG_SECTORS"
[ "$NEW_END" -lt "$IMG_SECTORS" ] || { echo "MATH GATE 1 FAILED"; exit 1; }
if ! printf "yes
" | parted ---pretend-input-tty "$LOOP" resizepart 3 "${NEW_END}s"; then
    echo "resizepart failed"; exit 1
fi
partx -u "$LOOP" || true
losetup -d "$LOOP"; trap - EXIT

TRUNC=$(( (NEW_END + 34) * SECTOR ))
[ "$TRUNC" -gt $(( (P3_START + FS_SECTORS) * SECTOR )) ] || { echo "MATH GATE 2 FAILED"; exit 1; }
echo "truncating to $TRUNC bytes ($((TRUNC/1024/1024)) MB)"
truncate -s "$TRUNC" "$WORK"
sgdisk -e "$WORK" >/dev/null
sgdisk -v "$WORK" | tail -3

msg "[9/9] verify"
LOOP=$(losetup -f --show -P "$WORK")
trap 'umount /tmp/esp4 2>/dev/null||true; umount '"$MNT"' 2>/dev/null||true; losetup -d '"$LOOP"' 2>/dev/null||true' EXIT
e2fsck -f -n "${LOOP}p3"
mount -o ro "${LOOP}p3" "$MNT"
fail=0
# -e follows symlinks, and the unit symlink is absolute inside the image, so the
# host cannot resolve it. Accept a dangling symlink as present.
chk(){ if [ -e "$1" ] || [ -L "$1" ]; then echo "   OK   ${1#$MNT}"; else echo "   MISS ${1#$MNT}"; fail=1; fi; }
chk "$MNT/boot/vmlinuz-6.6.98+"
chk "$MNT/boot/vmlinuz-6.6.98+-colorfix"
chk "$MNT/boot/extlinux/extlinux.conf"
chk "$MNT/usr/lib/linux-image-6.6.98+/allwinner/sun60i-a733-cubie-a7a.dtb"
chk "$MNT/usr/lib/linux-image-gpu1008/allwinner/sun60i-a733-cubie-a7a.dtb"
chk "$MNT/etc/systemd/system/multi-user.target.wants/firstboot-expand.service"
chk "$MNT/etc/modules-load.d/a7a-bluetooth.conf"
chk "$MNT/usr/src/linux-headers-6.6.98-a7a"
echo "   tx-delay check:"
for f in $(find "$MNT/usr/lib" -name 'sun60i-a733-cubie-a7a*.dtb'); do
    v=$(fdtget "$f" $ETH tx-delay 2>/dev/null || echo "-")
    [ "$v" = "9" ] || [ "$v" = "-" ] || { echo "   BAD tx-delay=$v in ${f#$MNT}"; fail=1; }
done
[ "$fail" = 0 ] && echo "   all device trees at tx-delay 9"
umount "$MNT"
mkdir -p /tmp/esp4 && mount -o ro "${LOOP}p2" /tmp/esp4 && chk /tmp/esp4/boot.scr && umount /tmp/esp4
losetup -d "$LOOP"; trap - EXIT
[ "$fail" = 0 ] || { echo "VERIFY FAILED"; exit 1; }

mv "$WORK" "$FINAL"
echo
echo "IMAGE BUILT: $FINAL"
ls -la "$FINAL"
echo "raw size: $(( $(stat -c %s "$FINAL") / 1024 / 1024 )) MB"
