#!/bin/bash
# add_extras.sh IMAGE VARIANT
#   VARIANT = standard | maximum
#
# standard : RAM 2040 (lab-E, as golden-v3), dsu_oc built and installed but NOT autoloaded
# maximum  : RAM 2136 (lab-V, VDD2 1120mV), dsu_oc autoloaded at boot
#
# Both get the DSU/L3 module, the GPU game launchers and the a7a-llm tooling.
set -euo pipefail

IMG=${1:?usage: add_extras.sh IMAGE standard|maximum}
VARIANT=${2:?usage: add_extras.sh IMAGE standard|maximum}
# Path to the recovery kit (firmware blobs, modules). Override for your setup:
#   KIT=/path/to/radxa-a7a-recovery ./add-image-extras.sh ...
KIT=${KIT:?set KIT to your radxa-a7a-recovery checkout}
# Path to the toolkit checkout (game launchers, helper binaries).
TOOLKIT=${TOOLKIT:?set TOOLKIT to your radxa-a7a-toolkit checkout}
FW_MAX="$KIT/firmware/lab-V-2136-vdd2-1120.img"
KREL=6.6.98+
MNT=/tmp/extras
SEC=512

msg(){ echo; echo "=== $*"; }
case "$VARIANT" in standard|maximum) ;; *) echo "bad variant"; exit 1;; esac

msg "[1/6] attach + mount ($VARIANT)"
LOOP=$(losetup -f --show -P "$IMG")
cleanup(){ umount "$MNT/dev/pts" 2>/dev/null||true; umount "$MNT/dev" 2>/dev/null||true
           umount "$MNT/proc" 2>/dev/null||true; umount "$MNT/sys" 2>/dev/null||true
           umount "$MNT" 2>/dev/null||true; losetup -d "$LOOP" 2>/dev/null||true; }
trap cleanup EXIT
mkdir -p "$MNT" && mount "${LOOP}p3" "$MNT"
cp /usr/bin/qemu-aarch64-static "$MNT/usr/bin/"
mount --bind /dev "$MNT/dev"; mount --bind /dev/pts "$MNT/dev/pts" 2>/dev/null || true
mount -t proc proc "$MNT/proc"; mount -t sysfs sys "$MNT/sys"

msg "[2/6] build dsu_oc.ko inside the image (proves the headers package works)"
mkdir -p "$MNT/tmp/dsu"
cp "$KIT/src/dsu_oc.c" "$MNT/tmp/dsu/"
printf 'obj-m := dsu_oc.o\n' > "$MNT/tmp/dsu/Makefile"
chroot "$MNT" /bin/bash -c "cd /tmp/dsu && make -C /lib/modules/$KREL/build M=/tmp/dsu modules BSP_TOP=bsp/ KBUILD_MODPOST_WARN=1 2>&1 | tail -4"
if [ ! -f "$MNT/tmp/dsu/dsu_oc.ko" ]; then echo "FATAL: dsu_oc.ko did not build"; exit 1; fi
install -D -m 0644 "$MNT/tmp/dsu/dsu_oc.ko" "$MNT/lib/modules/$KREL/extra/dsu_oc.ko"
chroot "$MNT" /bin/bash -c "depmod -a $KREL"
echo "   installed $(chroot "$MNT" /bin/bash -c "modinfo -F filename dsu_oc" 2>/dev/null || echo '/lib/modules/'$KREL'/extra/dsu_oc.ko')"
chroot "$MNT" /bin/bash -c "modinfo dsu_oc 2>/dev/null | head -4" || true
rm -rf "$MNT/tmp/dsu"

msg "[3/6] GPU game launchers + tools"
for f in "$TOOLKIT/games/supertuxkart/supertuxkart-gpu" \
         "$TOOLKIT/games/openarena/openarena-gpu"; do
    [ -f "$f" ] && install -m 0755 "$f" "$MNT/usr/local/bin/" && echo "   + $(basename "$f")"
done
for f in "$KIT/tools/a7a-llm" "$KIT/tools/a7a-llm-gui.py" "$KIT/tools/a7a-clock-gui.py"; do
    [ -f "$f" ] && install -m 0755 "$f" "$MNT/usr/local/bin/" && echo "   + $(basename "$f")"
done
[ -f "$KIT/tools/a7a-llm.service" ] && install -m 0644 "$KIT/tools/a7a-llm.service" \
    "$MNT/etc/systemd/system/" && echo "   + a7a-llm.service (not enabled)"
[ -f "$KIT/tools/a7a-llm-gui.desktop" ] && install -m 0644 "$KIT/tools/a7a-llm-gui.desktop" \
    "$MNT/usr/share/applications/" && echo "   + a7a-llm-gui.desktop"

msg "[4/6] variant-specific settings"
if [ "$VARIANT" = maximum ]; then
    cat > "$MNT/etc/modules-load.d/a7a-dsu-oc.conf" <<'EOF'
# Raise the DSU / L3 clock to its top vendor OPP (1352 MHz) at boot.
# Worth +31-38% memory bandwidth, but only in combination with the RAM
# overclock - at stock RAM speed it buys essentially nothing.
# Remove this file (or `rmmod dsu_oc`) to go back to the stock 780 MHz.
dsu_oc
EOF
    echo "   dsu_oc set to autoload"
    cat > "$MNT/etc/motd" <<'EOF'

  ###############################################################
  #   Radxa Cubie A7A  -  MAXIMUM OVERCLOCK IMAGE               #
  ###############################################################

  This image runs BEYOND the manufacturer's specification:

    RAM     2136 MHz  (Allwinner derates 12GB boards to 1800)
    DSU/L3  1352 MHz autoloaded  (stock 780)
    A76     3000 MHz  (datasheet 2002)     A55  2800 MHz (1794)

  READ THIS FIRST
  ---------------
  * The 2136 MHz RAM profile was validated on ONE board. Silicon
    varies. If your board cannot train it you will get
    "init dram fail" and it will NOT BOOT AT ALL.
  * The neighbouring 2112 MHz step was a coin flip - 4 passes in
    8 cold boots - so the margin here is genuinely thin.
  * It raises the DRAM core rail (VDD2) to 1120 mV.
  * Under heavy load the DSU overclock reached 88.6 C, above the
    80 C passive trip, so expect thermal throttling.
  * No warranty, expressed or implied. You accept the risk of
    instability, data loss and hardware wear.

  IF IT DOES NOT BOOT
  -------------------
  Flash the STANDARD image instead. It is the same system at the
  validated 2040 MHz, and the DSU overclock is one modprobe away:
      sudo modprobe dsu_oc

  Cold-boot it several times before trusting it with real work.
  Details: /etc/a7a-image-variant
  Report problems: github.com/Rabs9/radxa-cubie-a7a-kernel/issues

EOF
    chmod 0644 "$MNT/etc/motd"
    install -m 0644 "$MNT/etc/motd" "$MNT/usr/local/share/a7a-MAXIMUM-OC-DISCLAIMER.txt"
    echo "   maximum-OC disclaimer written to /etc/motd"
else
    rm -f "$MNT/etc/modules-load.d/a7a-dsu-oc.conf"
    mkdir -p "$MNT/usr/local/share"
    cat > "$MNT/usr/local/share/a7a-dsu-oc.README" <<'EOF'
The DSU/L3 overclock module is installed but not loaded.

    sudo modprobe dsu_oc      # L3 780 -> 1352 MHz
    sudo rmmod dsu_oc         # back to stock

It is worth +31-38% memory bandwidth, but only together with the RAM
overclock; at stock RAM speed it buys essentially nothing. Under a heavy
stress-ng load it reached 88.6 C, above the 80 C passive trip, so expect
some throttling in worst-case workloads.

To load it at every boot:
    echo dsu_oc | sudo tee /etc/modules-load.d/a7a-dsu-oc.conf
EOF
    echo "   dsu_oc installed but inert (README at /usr/local/share/a7a-dsu-oc.README)"
fi

cat > "$MNT/etc/a7a-image-variant" <<EOF
variant=$VARIANT
built=2026-08-22
kernel=$KREL
ram=$([ "$VARIANT" = maximum ] && echo "2136 MHz (lab-V, VDD2 1120mV)" || echo "2040 MHz (lab-E, OPi factory recipe, stock 560mV)")
dsu_l3=$([ "$VARIANT" = maximum ] && echo "1352 MHz, autoloaded" || echo "1352 MHz available via modprobe dsu_oc")
ethernet=RGMII tx-delay 9
EOF
echo "   /etc/a7a-image-variant written"

msg "[5/6] clean + unmount"
chroot "$MNT" /bin/bash -c "apt-get clean" 2>/dev/null || true
find "$MNT/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -f "$MNT/usr/bin/qemu-aarch64-static"
chattr +i "$MNT/boot/extlinux/extlinux.conf" 2>/dev/null || true
sync
umount "$MNT/dev/pts" 2>/dev/null || true
umount "$MNT/dev"; umount "$MNT/proc"; umount "$MNT/sys"; umount "$MNT"
losetup -d "$LOOP"; trap - EXIT

msg "[6/6] firmware region"
if [ "$VARIANT" = maximum ]; then
    [ -f "$FW_MAX" ] || { echo "FATAL: $FW_MAX missing"; exit 1; }
    # sectors 34..32767 only: never touch the GPT
    dd if="$FW_MAX" of="$IMG" bs=$SEC skip=34 seek=34 count=32734 conv=notrunc,fsync status=none
    echo "   boot0 swapped to lab-V-2136-vdd2-1120"
else
    echo "   boot0 left as lab-E-2040 (unchanged)"
fi
python3 - "$IMG" <<'PY'
import sys, struct
f=open(sys.argv[1],'rb'); f.seek(256*512); b=f.read(0x3C000); f.close()
for off in range(0,len(b)-4,4):
    if struct.unpack_from('<I',b,off)[0]==0xa11a:
        w=struct.unpack_from('<32I',b,off-24)
        if 300<=w[0]<=3000:
            print("   verified dram clk=%d tpr0=0x%08x tpr13=0x%05x" % (w[0],w[22],w[30])); break
PY
echo "DONE ($VARIANT)"
