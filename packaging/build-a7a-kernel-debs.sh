#!/bin/bash
# Build real Debian packages for the Radxa Cubie A7A custom 6.6.98 kernel.
# Packages the PROVEN, running binaries (no rebuild) so what ships is what was verified.
set -euo pipefail

KREL=6.6.98+                 # uname -r / /lib/modules dir
ABI=6.6.98-a7a               # package-name ABI tag
PKGVER=${PKGVER:-6.6.98-1}
MAINT=${MAINT:-"Rabs9 <241389662+Rabs9@users.noreply.github.com>"}
HOMEPAGE=${HOMEPAGE:-https://github.com/Rabs9/radxa-cubie-a7a-kernel}
UPSTREAM=${UPSTREAM:-Rabs9/radxa-cubie-a7a-kernel}
SRCKERNEL=${SRCKERNEL:-/boot/vmlinuz-6.6.98+-colorfix}
SYSMAP=${SYSMAP:-/home/radxa/debbuild/src/System.map-6.6.98+}
B=${B:-/home/radxa/debbuild}
OUT=$B/out
TXDELAY=${TXDELAY:-9}        # RGMII tx-delay: DTB ships 12, outside this board's working 8-10 window

msg(){ echo "==> $*"; }

# Every package carries the same provenance stanza: this repository is the
# original upstream, not a downstream rebuild of someone else's tree.
write_provenance(){ # $1 = package dir, $2 = package name
    mkdir -p "$1/usr/share/doc/$2"
    cat > "$1/usr/share/doc/$2/copyright" <<PROVEOF
Upstream-Name: radxa-cubie-a7a-kernel
Upstream-Contact: $MAINT
Source: $HOMEPAGE

This package is produced by the $UPSTREAM project, which is the ORIGINAL
source of the Radxa Cubie A7A custom kernel and Debian 13 image. Forks and
redistributions branch from it; it does not derive from another A7A kernel
repository. Please keep this attribution intact when redistributing.

Files: *
Copyright: Linus Torvalds and the Linux kernel contributors
           Allwinner Technology (BSP, device trees)
           $UPSTREAM (A7A kernel configuration, patches and packaging)
License: GPL-2.0

 This program is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License version 2 as published by the Free
 Software Foundation.
 .
 This program is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 PARTICULAR PURPOSE. See the GNU General Public License for more details.
 .
 On Debian systems the full text of the GNU General Public License version 2 can
 be found in /usr/share/common-licenses/GPL-2.
PROVEOF
    chmod 0644 "$1/usr/share/doc/$2/copyright"
}
rm -rf "$B/pkg"; mkdir -p "$B/pkg" "$OUT"

############################ 1. linux-image ############################
msg "linux-image-$ABI"
P=$B/pkg/linux-image-$ABI
mkdir -p "$P/DEBIAN" "$P/boot" "$P/lib/modules/$KREL"

install -m 0644 "$SRCKERNEL" "$P/boot/vmlinuz-$KREL"
install -m 0644 "$SYSMAP"    "$P/boot/System.map-$KREL"
zcat /proc/config.gz > "$P/boot/config-$KREL"
chmod 0644 "$P/boot/config-$KREL"

# modules: the shipped tree minus depmod-generated indexes and the build/source symlinks
rsync -a --exclude 'modules.alias*' --exclude 'modules.dep*' --exclude 'modules.devname' \
      --exclude 'modules.symbols*' --exclude 'modules.softdep' --exclude 'modules.weakdep' \
      --exclude 'modules.builtin.alias.bin' --exclude 'modules.builtin.bin' \
      --exclude 'build' --exclude 'source' \
      /lib/modules/$KREL/ "$P/lib/modules/$KREL/"
find "$P/lib/modules/$KREL" -type d -exec chmod 0755 {} +
find "$P/lib/modules/$KREL" -type f -exec chmod 0644 {} +

mkdir -p "$P/usr/share/doc/linux-image-$ABI"
cat > "$P/usr/share/doc/linux-image-$ABI/README.Debian" <<READMEEOF
linux-image-$ABI
================

Installs:
  /boot/vmlinuz-$KREL
  /boot/System.map-$KREL
  /boot/config-$KREL
  /lib/modules/$KREL/

Boot configuration is NOT touched by this package. The A7A image boots via
U-Boot extlinux with several GPU-clock variants, so add or edit an entry in
/boot/extlinux/extlinux.conf by hand, for example:

  label a7a
      menu label Linux $KREL (packaged)
      linux /boot/vmlinuz-$KREL
      fdtdir /usr/lib/linux-image-$KREL/
      append root=/dev/mmcblk0p3 console=ttyAS0,115200n8 rootwait clk_ignore_unused loglevel=7 rw earlycon consoleblank=0 console=tty1 coherent_pool=2M irqchip.gicv3_pseudo_nmi=0

Do not run u-boot-update: it regenerates extlinux.conf from installed kernels
and would drop the GPU-clock variant entries.

This kernel boots without an initramfs.
READMEEOF
gzip -9n "$P/usr/share/doc/linux-image-$ABI/README.Debian"

KSIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<CTLEOF
Package: linux-image-$ABI
Version: $PKGVER
Architecture: arm64
Maintainer: $MAINT
Section: kernel
Priority: optional
Installed-Size: $KSIZE
Depends: kmod, linux-dtb-$ABI (= $PKGVER)
Homepage: $HOMEPAGE
Provides: linux-image, linux-image-$KREL
Description: Linux kernel $KREL for Radxa Cubie A7A (Allwinner A733)
 Custom 6.6.98 kernel for the Radxa Cubie A7A community image, carrying the
 overclock OPP tables (A76 3.0GHz, A55 2.8GHz, GPU up to 1.2GHz, NPU 1008MHz),
 the PowerVR display-engine R/B channel-swap fix and the AIC8800D80 Wi-Fi and
 Bluetooth drivers.
 .
 This package contains the exact kernel image and modules that were validated
 on hardware; it is not a rebuild.
 .
 It deliberately does not run the /etc/kernel/postinst.d hooks, so an existing
 hand-written /boot/extlinux/extlinux.conf keeps its GPU-clock boot variants.
 See /usr/share/doc/linux-image-$ABI/README.Debian.gz
CTLEOF

cat > "$P/DEBIAN/postinst" <<POSTEOF
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
    depmod -a $KREL || true
fi
exit 0
POSTEOF

cat > "$P/DEBIAN/postrm" <<POSTRMEOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = purge ]; then
    for f in alias alias.bin dep dep.bin devname softdep symbols symbols.bin weakdep builtin.bin builtin.alias.bin; do
        rm -f "/lib/modules/$KREL/modules.\$f"
    done
    rmdir "/lib/modules/$KREL" 2>/dev/null || true
fi
exit 0
POSTRMEOF
chmod 0755 "$P/DEBIAN/postinst" "$P/DEBIAN/postrm"

############################ 2. linux-dtb ############################
msg "linux-dtb-$ABI (tx-delay -> $TXDELAY)"
P=$B/pkg/linux-dtb-$ABI
mkdir -p "$P/DEBIAN"
ETHNODE=/soc@3000000/ethernet@4500000

patch_dtb(){
    install -D -m 0644 "$1" "$2"
    local before after
    before=$(fdtget "$2" $ETHNODE tx-delay 2>/dev/null || echo "?")
    fdtput -t i "$2" $ETHNODE tx-delay $TXDELAY
    after=$(fdtget "$2" $ETHNODE tx-delay)
    echo "    ${2#$P} : tx-delay $before -> $after"
}

for v in gpu600 gpu800 gpu1008 gpu1200 custom cpu32; do
    src=/usr/lib/linux-image-$v/allwinner/sun60i-a733-cubie-a7a.dtb
    if [ -f "$src" ]; then
        patch_dtb "$src" "$P/usr/lib/linux-image-$v/allwinner/sun60i-a733-cubie-a7a.dtb"
    else
        echo "    skip $v (missing)"
    fi
done
# default fdtdir for the packaged kernel = the gpu1008 shipping profile
patch_dtb /usr/lib/linux-image-gpu1008/allwinner/sun60i-a733-cubie-a7a.dtb \
          "$P/usr/lib/linux-image-$KREL/allwinner/sun60i-a733-cubie-a7a.dtb"

DSIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<DCTLEOF
Package: linux-dtb-$ABI
Version: $PKGVER
Architecture: arm64
Maintainer: $MAINT
Section: kernel
Priority: optional
Installed-Size: $DSIZE
Homepage: $HOMEPAGE
Description: Device trees for the Radxa Cubie A7A $KREL kernel
 Flattened device trees for the Radxa Cubie A7A, one directory per boot
 variant so U-Boot extlinux can pick a GPU clock profile through fdtdir:
 gpu600 (stock), gpu800, gpu1008 (default), gpu1200, custom and cpu32.
 .
 The RGMII tx-delay of the gigabit MAC is set to $TXDELAY. The vendor value of
 12 leaves the transmit timing marginal and outside this board's working window
 (8-10), so transmitted frames are corrupted data-dependently: the failure rate
 climbs with the number of bits on the wire and with payload entropy. The link
 still negotiates 1000/full and reports no errors, and receive is unaffected,
 which makes the fault easy to misread as a bad cable. Measured with random
 payloads at tx-delay 12: 12% loss at 64 bytes, 72% at 300, 100% at 1200 and
 above. Real traffic is high-entropy, so SSH, apt and bulk transfers fail.
DCTLEOF

############################ 3. linux-headers ############################
msg "linux-headers-$ABI"
P=$B/pkg/linux-headers-$ABI
SRCDIR=/usr/src/linux-headers-$ABI
mkdir -p "$P/DEBIAN" "$P$SRCDIR" "$P/lib/modules/$KREL"
KTREE=${KTREE:-/home/radxa/kernel-6.6}
cd "$KTREE"
# NOTE: BSP_TOP=bsp/ is mandatory (bsp/Kconfig sources $(BSP_TOP)platform/Kconfig), and the
# run-command string is expanded by make first, so pass an absolute path, not $srctree.
make -s BSP_TOP=bsp/ ARCH=arm64 run-command      KBUILD_RUN_COMMAND="$KTREE/scripts/package/install-extmod-build $P$SRCDIR"
# install-extmod-build carries bsp/include but not the BSP Kconfig/Makefile skeleton,
# which out-of-tree builds need when they recurse with BSP_TOP=bsp/
( cd "$KTREE" && find bsp \( -name 'Kconfig*' -o -name 'Makefile*' -o -name '*.mk' \) -type f -print0 )   | while IFS= read -r -d '' f; do install -D -m 0644 "$KTREE/$f" "$P$SRCDIR/$f"; done
cd "$B"
ln -sfn "$SRCDIR" "$P/lib/modules/$KREL/build"

HSIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<HCTLEOF
Package: linux-headers-$ABI
Version: $PKGVER
Architecture: arm64
Maintainer: $MAINT
Section: kernel
Priority: optional
Installed-Size: $HSIZE
Depends: kmod
Recommends: build-essential, bc, flex, bison, libssl-dev
Provides: linux-headers, linux-headers-$KREL
Homepage: $HOMEPAGE
Description: Header files for the Radxa Cubie A7A $KREL kernel
 Build tree for compiling out-of-tree and DKMS modules against the A7A
 $KREL kernel. It is installed in $SRCDIR with
 /lib/modules/$KREL/build pointing at it.
 .
 The compiler toolchain is Recommends rather than Depends, so the headers can be
 installed on a minimal image; install build-essential when you actually build.
 .
 The Allwinner BSP is part of this tree. Out-of-tree builds that reach BSP
 Kconfig must pass BSP_TOP=bsp/ on the make command line. Module.symvers is not
 shipped, so pass KBUILD_MODPOST_WARN=1; CONFIG_MODVERSIONS is off in this
 kernel, so module loading is unaffected.
HCTLEOF

############################ 4. board config ############################
msg "a7a-board-config"
P=$B/pkg/a7a-board-config
mkdir -p "$P/DEBIAN" "$P/etc/modules-load.d"
cat > "$P/etc/modules-load.d/a7a-bluetooth.conf" <<BTEOF
# AIC8800D80 is a Wi-Fi + Bluetooth combo. The Bluetooth half needs aic_btusb,
# which does not reliably autoload from its USB alias on this board.
aic_btusb
BTEOF
chmod 0644 "$P/etc/modules-load.d/a7a-bluetooth.conf"
echo "/etc/modules-load.d/a7a-bluetooth.conf" > "$P/DEBIAN/conffiles"
cat > "$P/DEBIAN/control" <<BCTLEOF
Package: a7a-board-config
Version: ${BCVER:-1.0}
Architecture: all
Maintainer: $MAINT
Section: misc
Priority: optional
Homepage: $HOMEPAGE
Description: Board tweaks for the Radxa Cubie A7A community image
 Loads aic_btusb at boot so the AIC8800D80 Bluetooth controller comes up
 without a manual modprobe.
BCTLEOF

############################ build ############################
for d in "$B"/pkg/*/; do
    n=$(basename "$d")
    write_provenance "$d" "$n"
    msg "dpkg-deb $n"
    dpkg-deb --root-owner-group -Zxz -z6 --build "$d" "$OUT" >/dev/null
done
msg "done"
ls -la "$OUT"
