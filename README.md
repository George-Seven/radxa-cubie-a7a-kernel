# Radxa Cubie A7A — Custom Kernel & Hardware Tuning

> ⚠️ **Flashed an image from before 2026-08-10 and it won't boot?** The system
> on your card is fine — the boot chain had two fixable defects (wrong U-Boot
> variant + empty EFI partition). **[boot-fix/](boot-fix/) repairs your card
> in place in ~5 minutes** — no re-download. Images released from 2026-08-10
> onward have both fixes baked in and boot hands-free (power → login ≈ 75 s,
> verified).

Custom Linux 6.6.98 kernel build with full hardware support and overclocking for the Radxa Cubie A7A (Allwinner A733 SoC).

This project started when Radxa shipped this board with Debian 11 and a 5.15 kernel; this repo has been Debian 13 + 6.6.98 since its first release. Radxa's official images have since caught up on the basics (6.6 kernel, Debian 13, GPU/NPU support) — so this repo's focus today is what the official images don't do: validated CPU and RAM overclocking, the GPU color fix, boot repair tooling, and update-proofing.

## What This Gives You

| Feature | Radxa Official | This Project |
|---------|---------------|--------------|
| **Kernel** | 5.15.147 / 6.6.98+ (newer images) | **6.6.98+** |
| **OS** | Debian 11 / Debian 13 (A7A/A7Z/A7S) | **Debian 13 Trixie** |
| **CPU A55** | 1794 MHz | **2800 MHz (+56%, schedutil)** |
| **CPU A76** | 2002 MHz | **3000 MHz (+50%, schedutil)** |
| **GPU** | Vulkan 1.3 + GLES 3.2 (PowerVR BXM-4-64) | **GLES 3.2 validated on hardware — glmark2-es2 889, color-correct, soak-stable** |
| **NPU** | 3 TOPS ([official tutorials](https://docs.radxa.com/en/cubie/a7a/app-dev/npu-dev)) | **3 TOPS, ResNet50 ~7.8 ms (~128 FPS), verified** |
| **RAM** | 1800 MHz | **2040 MHz overclock (LPDDR5-4080), memtester-clean** |
| **WiFi** | Working (auto-connect on boot) | **Working (auto-connect on boot)** |
| **HDMI** | Working (video + audio) | **Working (1080p + audio)** |
| **Boot** | Autonomous (new boot flow, no `boot0`) | **Autonomous (power → login ~75 s, verified)** |

## Hardware Specs

- **SoC:** Allwinner A733 (sun60iw2p1)
- **CPU:** 2x Cortex-A76 @ 2.0GHz + 6x Cortex-A55 @ 1.79GHz (big.LITTLE)
- **GPU:** Imagination PowerVR BXM-4-64 MC1 — GLES 3.2 validated (glamor on hardware); Vulkan/OpenCL provided by the Imagination DDK blob (not independently benchmarked here)
- **NPU:** Vivante VIP9000, 3 TOPS @ INT8
- **RAM:** 12GB LPDDR5 @ 1800 MHz stock — validated overclock to **2040 MHz** (LPDDR5-4080-effective, memtester-clean; 2400 refused training on this 12 GB silicon)
- **Co-processor:** RISC-V E906 @ 200MHz (SCP/power management)
- **Storage:** SD card (SDR104), eMMC, UFS (optional)
- **Display:** HDMI 2.0 (4K decode, 1080p output)
- **WiFi:** AIC8800D80 (WiFi 6 + BT 5.x via USB)
- **Ethernet:** Gigabit RGMII (STMMAC)


## Updating safely (read this before `apt upgrade`)

This image's kernel and boot config live **outside apt**. On images from
**2026-08-10 onward**, apt pins (`/etc/apt/preferences.d/99-a7a-custom-kernel`)
block the three package classes that would break the board — stock
`linux-image-*` kernels, `u-boot-menu`, and `flash-kernel` — so normal
updates (security patches, apps, libraries) are safe.

On **older images**, or if you want the boot chain verified every time, use
[`scripts/safe-update.sh`](scripts/safe-update.sh): it restores the pins if
missing, backs up the kernel + `extlinux.conf`, runs the upgrade, then
verifies nothing moved (and restores from backup if it did).

The custom kernel is now packaged as proper Debian packages -
`linux-image-6.6.98-a7a`, `linux-dtb-6.6.98-a7a`, `linux-headers-6.6.98-a7a`
and `a7a-board-config`. See [`packaging/`](packaging/) for the build script,
install instructions and the DKMS notes. They package the validated binaries
rather than rebuilding, and they deliberately leave `extlinux.conf` alone.

## Benchmark Results

### CPU (Overclocked)

| Cluster | Cores | Stock | Overclocked | Voltage |
|---------|-------|-------|-------------|---------|
| Cortex-A55 | 6 | 1794 MHz | **2800 MHz (+56%)** | 1540 mV (PMIC max) |
| Cortex-A76 | 2 | 2002 MHz | **3000 MHz (+50%)** | 1540 mV (PMIC max) |

Stress test (60s, all 8 cores): peak 53C, idle 30C, throttle point 80C.

### LLM Inference (llama.cpp)

| Metric | Value |
|--------|-------|
| Model | Qwen2.5 1.5B Q4_K_M |
| Prompt speed | 36 tok/s |
| Generation speed | 6 tok/s |
| Threads | 8 (A55+A76) |

### GPU — PowerVR BXM-4-64 MC1

| Metric | Value |
|--------|-------|
| OpenGL ES | 3.2 (glamor on PowerVR — validated) |
| **glmark2-es2 (off-screen)** | **889** at GPU 1008 MHz + RAM 2040 MHz (745 at RAM 1800; 612 bare greeter) |
| Daily clock | **1008 MHz @ 960 mV** — the efficient peak (1200 MHz is stable but scores lower for more power) |
| Clock ladder | 600 / 800 / 1008 / 1200 MHz selectable, voltage-matched, boot-menu |
| Stability | 10-min soak, 0 hardware errors, peak 76 °C under CPU+GPU+RAM load |
| Driver | Imagination proprietary (pvrsrvkm) + colorfix kernel (R/B swap) |
| Note | earlier "Vulkan 1.3 / glmark 32 / OpenCL GFLOPS" figures pre-date the real bring-up and were partly software-rendered (llvmpipe); superseded by the validated numbers above |

### NPU — Vivante VIP9000

| Metric | Value |
|--------|-------|
| Frequency | 1008 MHz |
| Performance | 3 TOPS (INT8) |
| ResNet50 | ~7.8 ms / ~128 FPS (verified, /v3 NBG models) |
| SDK | VIPLite 2.0 (ai-sdk) |

### Memory — 12GB LPDDR5

| Test | Result |
|------|--------|
| NEON Copy | 5,057 MB/s |
| NEON Fill | 8,369 MB/s |
| sysbench Read (1T) | 13,477 MB/s |
| sysbench Write (1T) | 10,335 MB/s |
| sysbench Read (8T) | 18,237 MB/s |
| sysbench Write (8T) | 33,300 MB/s |
| ZRAM Swap | 6 GB (LZ4 compressed) |

### Storage (SD Card SDR104)

| Test | Result |
|------|--------|
| Sequential Write | ~80 MB/s |
| Sequential Read | ~95 MB/s |

### Thermal (idle / stress)

| Zone | Idle | Full Load (30s) |
|------|------|-----------------|
| A55 | 30C | 50C |
| A76 | 29C | 45C |
| GPU | 29C | - |
| DDR | 29C | - |
| Throttle | - | 80C |

## Quick Start

### Prerequisites (on your x86_64 build machine)

```bash
# Fedora/RHEL
sudo dnf install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  bc dtc cpio kmod python3 swig flex bison openssl-devel \
  ncurses-devel elfutils-libelf-devel

# Ubuntu/Debian
sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  bc device-tree-compiler cpio kmod python3 swig flex bison \
  libssl-dev libncurses-dev libelf-dev
```

### Build

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/radxa-a7a-kernel.git
cd radxa-a7a-kernel

# Clone source repos
git clone --branch allwinner-aiot-linux-6.6 --depth 1 https://github.com/radxa/kernel.git kernel-6.6
git clone --branch cubie-aiot-v1.4.8 --depth 1 https://github.com/radxa/allwinner-bsp.git allwinner-bsp-1.4.8
git clone --branch device-a733-v1.4.8 --depth 1 https://github.com/radxa/allwinner-device.git allwinner-device-1.4.8

# Apply patches
./scripts/apply-patches.sh

# Build
cd kernel-6.6
ln -sfn ../allwinner-bsp-1.4.8 bsp
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ cubie_a7a_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ -j$(nproc) Image dtbs modules
```

### Deploy

```bash
# Copy to board via SSH
scp arch/arm64/boot/Image radxa@BOARD_IP:/tmp/
scp arch/arm64/boot/dts/allwinner/sun60i-a733-cubie-a7a.dtb radxa@BOARD_IP:/tmp/

# On the board
sudo cp /tmp/Image /boot/vmlinuz-6.6.98+-custom
sudo mkdir -p /usr/lib/linux-image-custom/allwinner
sudo cp /tmp/sun60i-a733-cubie-a7a.dtb /usr/lib/linux-image-custom/allwinner/
```

### GPU Module (Imagination BXM-4-64)

The GPU kernel module must be built separately:

```bash
cd allwinner-bsp-1.4.8/modules/gpu/img-bxm/linux/rogue_km

# Temporarily patch Kbuild.include for Make 4.4+ compatibility
sed -i 's/^.NOTINTERMEDIATE:/#.NOTINTERMEDIATE:/' ../../kernel-6.6/scripts/Kbuild.include

make PVR_BUILD_DIR=sunxi_linux BUILD=release \
  KERNELDIR=$(pwd)/../../kernel-6.6 \
  KERNEL_CROSS_COMPILE=aarch64-linux-gnu- \
  KERNEL_CC=aarch64-linux-gnu-gcc \
  KERNEL_LD=aarch64-linux-gnu-ld \
  KERNEL_NM=aarch64-linux-gnu-nm \
  KERNEL_AR=aarch64-linux-gnu-ar \
  KERNEL_OBJCOPY=aarch64-linux-gnu-objcopy \
  CROSS_COMPILE=aarch64-linux-gnu- \
  ARCH=arm64 -j$(nproc)

# Restore Kbuild.include
sed -i 's/^#.NOTINTERMEDIATE:/.NOTINTERMEDIATE:/' ../../kernel-6.6/scripts/Kbuild.include

# Install on board
scp binary_sunxi_linux_nulldrmws_release/target_aarch64/kbuild/pvrsrvkm.ko radxa@BOARD_IP:/tmp/
ssh radxa@BOARD_IP "sudo cp /tmp/pvrsrvkm.ko /lib/modules/6.6.98+/extra/ && sudo depmod -a"
```

### WiFi (AIC8800 USB)

The BSP v1.4.8 AIC8800 USB driver has bugs. Build from the v1.4.6 BSP instead:

```bash
git clone --branch cubie-aiot-v1.4.6 --depth 1 https://github.com/radxa/allwinner-bsp.git allwinner-bsp-1.4.6

cd kernel-6.6
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ \
  M=../allwinner-bsp-1.4.6/drivers/net/wireless/aic8800/usb -j$(nproc)
```

Firmware files are in `allwinner-target/debian/cubie_a7a/overlay/lib/firmware/aic8800D80/`.

### NPU (Vivante VIP9000)

```bash
# On the board
git clone https://github.com/ZIFENG278/ai-sdk.git ~/ai-sdk

# Install libraries
sudo cp ~/ai-sdk/viplite-tina/lib/glibc-gcc13_2_0/v2.0/*.so /usr/local/lib/
sudo ldconfig

# Build vpm_run test tool
cd ~/ai-sdk/examples/vpm_run
make AI_SDK_PLATFORM=a733

# Test (use v3 models for A733)
./vpm_run -s sample_v3.txt -l 10 -d 0
```

## BSP Patches Required

The Allwinner BSP has several issues when built outside their `longan/awbs` build wrapper. These patches fix them:

| File | Issue | Fix |
|------|-------|-----|
| `bsp/include/sunxi-autogen.h` | Missing auto-generated header | Create with `AW_BSP_VERSION` define |
| `drivers/usb/host/sunxi-hci.h` | Angle-bracket relative include | Change `<>` to `""` |
| `drivers/sound/platform/Makefile` | Missing self-include path | Add `-I$(srctree)/bsp/drivers/sound/platform` |
| `drivers/gmac/Makefile` | Missing trace header include | Add `CFLAGS_sunxi-gmac.o += -I$(src)` |
| `drivers/ve/cedar-ve/Makefile` | Commented-out include | Uncomment and fix to `-I$(src)` |
| `modules/nand/Makefile` | Missing `KERNEL_SRC_DIR` | Add `$(srctree)` fallback |
| `modules/gpu/Makefile` | Missing `KERNEL_SRC_DIR` | Add `$(srctree)` fallback |
| `modules/gpu/img-bxm/.../aicusb.h` | Missing struct field | Add `u32 fw_version_uint` |

### Kernel Config Conflicts

These upstream configs must be disabled to avoid duplicate symbol/driver conflicts with the BSP:

```
CONFIG_MMC_SUNXI=n
CONFIG_MFD_AXP20X=n
CONFIG_MFD_AXP20X_I2C=n
CONFIG_MFD_AXP20X_RSB=n
CONFIG_SPI_NOR=n
CONFIG_MTD_SPI_NOR=n
CONFIG_DRM_PANFROST=n
CONFIG_VIDEO_IMX219=n
CONFIG_CPUFREQ_DT=y (but CPUFREQ_DT_PLATDEV must be blocklisted)
CONFIG_AW_CPUFREQ_DT=n
CONFIG_AW_CRASHDUMP=n
CONFIG_TYPEC_MUX_FSA4480=n
CONFIG_SND_SOC_AC101B=m (not =y, conflicts with AC101)
CONFIG_AIC_WLAN_SUPPORT=n (use out-of-tree v1.4.6 USB driver instead)
```

### cpufreq Fix

The `sun50i-cpufreq-nvmem` driver handles Allwinner's VF-binned OPP tables. To prevent `cpufreq-dt-platdev` from racing it:

```c
// drivers/cpufreq/cpufreq-dt-platdev.c — add to blocklist[]
{ .compatible = "allwinner,sun60i-a733", },
{ .compatible = "arm,sun60iw2p1", },
```

## Overclocking

The CPU OPP tables are in `sun60iw2p1-cpu-vf.dtsi`. Overclock entries are added for:

- **A55:** 1900 MHz @ 1050mV, 2000 MHz @ 1100mV
- **A76:** 2100 MHz @ 1100mV, 2200 MHz @ 1150mV, 2300 MHz @ 1200mV
- **GPU:** 1200 MHz @ 1050mV (stock max: 1008 MHz)
- **Thermal throttle:** Raised from 60C to 80C

The PMIC (AXP8191) supports up to 1540mV on the CPU rails, so there is headroom to push further.

DRAM overclocking: **1800 → 2040 MHz is validated and stable** (memtester-clean; the Orange Pi Zero3W factory LPDDR5 profile, patched into boot0 with a re-signed eGON checksum). 2400 MHz **refused training** on this 12 GB silicon across three configs. Boot0 param editing + checksum works; the tooling is in the recovery kit.

## Upgrade Path: Debian 11 → 13

The OS upgrade is done in-place:

1. Hold kernel packages: `apt-mark hold linux-image-radxa-a733 u-boot-radxa-a733`
2. Switch sources from `bullseye` → `bookworm` → `trixie`
3. Disable Radxa repos (no bookworm/trixie packages available)
4. Handle conflicts: `usrmerge` firmware duplicates, `plymouth`, `zram-tools`
5. Fix `growroot` initramfs hook: `chmod -x /usr/share/initramfs-tools/hooks/growroot`

## Boot Configuration

**Critical:** The rootfs partition (partition 3) must have GPT type **EF00** (EFI System), not 8300. The Allwinner U-Boot only scans EFI-typed partitions for `extlinux.conf`. Changing this type will break auto-boot.

```
# /boot/extlinux/extlinux.conf (on partition 3)
default l0
menu title Radxa Cubie A7A Boot Menu
prompt 0
timeout 50

label l0
    menu label Debian 13 Linux 6.6.98+ (Overclocked)
    linux /boot/Image
    fdt /usr/lib/linux-image-custom/sun60i-a733-cubie-a7a.dtb
    fdtdir /usr/lib/linux-image-custom/
    append root=/dev/mmcblk0p3 rootwait rootfstype=ext4 console=ttyAS0,115200 loglevel=4 cma=128M
```

Protect from being overwritten: `sudo chattr +i /boot/extlinux/extlinux.conf`

Note: Custom kernel uses `root=/dev/mmcblk0p3` (not UUID) because there is no initramfs to resolve UUIDs.

## Memory Tuning

```bash
# ZRAM compressed swap (effectively doubles usable memory)
modprobe zram
echo lz4 > /sys/block/zram0/comp_algorithm
echo 6G > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0

# Kernel tuning
sysctl -w vm.swappiness=100          # Optimal for zram
sysctl -w vm.vfs_cache_pressure=50   # Keep dentries cached
sysctl -w vm.dirty_ratio=20          # SD card writeback
sysctl -w vm.dirty_background_ratio=5
```

## Known Limitations

- **3.5mm audio jack:** AC101B codec chip is not physically populated on the A7A board
- **HDMI via KVM switch:** KVM switches may not pass HPD/EDID correctly. Connect directly or use `modetest -M sunxi-drm -s 146@99:1920x1080` to force output
- **DRAM overclock:** Requires boot0 rebuild from Allwinner brandy-2.0 SDK (binary patching unreliable)
- **GPU glmark2:** Score of 32 is via glamor (X11 compositor acceleration). Direct PVR DRI rendering requires Imagination's Mesa fork

## Source Repos

| Repo | Branch | Purpose |
|------|--------|---------|
| [radxa/kernel](https://github.com/radxa/kernel) | `allwinner-aiot-linux-6.6` | Linux 6.6.98 BSP kernel |
| [radxa/allwinner-bsp](https://github.com/radxa/allwinner-bsp) | `cubie-aiot-v1.4.8` | BSP drivers, GPU, NPU |
| [radxa/allwinner-bsp](https://github.com/radxa/allwinner-bsp) | `cubie-aiot-v1.4.6` | WiFi USB driver (v1.4.8 has bugs) |
| [radxa/allwinner-device](https://github.com/radxa/allwinner-device) | `device-a733-v1.4.8` | DTS, defconfig, sys_config |
| [radxa/allwinner-target](https://github.com/radxa/allwinner-target) | `target-a733-v1.4.6` | WiFi firmware, rootfs overlay |
| [radxa/u-boot](https://github.com/radxa/u-boot) | `allwinner-aiot-v2018.07` | U-Boot bootloader |
| [ZIFENG278/ai-sdk](https://github.com/ZIFENG278/ai-sdk) | `main` | NPU SDK (VIPLite 2.0) |

## License

This project's original work (kernel patches, scripts, configs, docs) is licensed
**GPL-2.0** — see [LICENSE](LICENSE). Copyright © 2026 Rabs9.

- Kernel patches: GPL-2.0 (required — derived from the Linux kernel).
- BSP drivers: as shipped by Allwinner (GPL) and Imagination (proprietary DDK blob).
- Released disk images bundle Debian packages under their own upstream licenses.

You may use, modify, and redistribute under GPL-2.0; **please keep attribution to
this repository as the original source.** This is the upstream — improvements are
welcome as pull requests here.

> **Status: pre-release / beta.** The packaged-kernel (`.deb`) milestone is
> built and validated on the reference board - it boots from the packaged
> kernel and device tree, and the headers package builds out-of-tree modules -
> but it is not published as a release yet. Treat current releases as beta.

## Quick Flash (One Command)

```bash
wget https://raw.githubusercontent.com/Rabs9/radxa-cubie-a7a-kernel/main/scripts/easy-flash.sh
sudo bash easy-flash.sh /dev/sdX
```

Downloads everything automatically and flashes. No manual steps.

## Single Image File (for Etcher/RPi Imager)

A single `.img.xz` file is available in releases for use with Balena Etcher or RPi Imager. After flashing, expand the rootfs:

```bash
# Expand partition 3 to fill the card (must use type EF00!)
sudo sgdisk -d 3 /dev/sdX
sudo sgdisk -n 3:679936:0 -t 3:EF00 -c 3:"rootfs" /dev/sdX
sudo partprobe /dev/sdX
sudo e2fsck -fy /dev/sdX3
sudo resize2fs /dev/sdX3

# On first boot, regenerate SSH host keys
sudo ssh-keygen -A && sudo systemctl restart sshd
```

## Display color fix (R/B swap) — 2026-08-11

The PowerVR DDK GL stack (24.2@6603887 from `allwinner-target`) writes red and
blue swapped into every buffer it renders (server-side glamor and client EGL
alike; a blue YouTube logo is the telltale). CPU rendering through the same
display engine is correct, so the fix inverts the display engine's channel
interpretation for 32-bit RGB formats to match what the GL stack actually
writes: `patches/0001-sunxi-drm-de-swap-rb-channels-for-pvr-glamor.patch`
(swaps the four RGB returns in `drm_to_de_format()` in
`bsp/drivers/drm/sunxi_device/hardware/lowlevel_de/de_channel.c`, mirrors the
TFBC/AFBC RGB byte-order tables, leaves YUV and the fbdev/logo path untouched).

Known cosmetic side effect: the CPU-drawn boot logo/fbcon shows swapped colors
(the penguins' beaks go blue). The GPU desktop — the thing you look at all
day — is correct.

Full desktop bring-up for this stack (GPU firmware, glamor, compositor
workarounds for the DDK's deferred-kick cursor trails, clock ladder with
proper dcdc4 voltages, `a7a-clock` tool) is maintained in the recovery kit
repo alongside this one.
