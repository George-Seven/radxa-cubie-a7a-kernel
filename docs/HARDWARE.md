# Hardware, tuning and configuration

---

## The board

| | |
|---|---|
| SoC | Allwinner A733 (`sun60iw2p1`) |
| CPU | 2× Cortex-A76 + 6× Cortex-A55 (big.LITTLE) |
| GPU | Imagination PowerVR BXM-4-64 MC1 |
| NPU | Vivante VIP9000, 3 TOPS INT8 |
| RAM | 12 GB LPDDR5 |
| Co-processor | RISC-V E906 @ 200 MHz (SCP / power management) |
| Storage | SD card (SDR104), eMMC; UFS on some variants only |
| Display | HDMI 2.0 (4K decode, 1080p output) |
| Wifi | AIC8800D80 (Wi-Fi 6 + BT 5.x, over USB) |
| Ethernet | Gigabit RGMII (STMMAC) |
| PMIC | AXP8191 |

---

## Overclocking

Use `a7a-clock` (GUI or CLI) rather than editing sysfs by hand — it validates
each value against the OPP tables and refuses anything the device tree does not
declare.

```bash
a7a-clock status          # everything, current and available
a7a-clock cpu performance # pin the governor
a7a-clock dsu 1352        # DSU/L3 in MHz
a7a-clock wifi 5          # lock to 5 GHz
```

### What ships

| rail | stock | standard image | maximum image |
|---|---|---|---|
| Cortex-A76 | 2002 MHz | 3000 MHz | 3000 MHz |
| Cortex-A55 | 1794 MHz | 2800 MHz | 2800 MHz |
| DSU / L3 | not exposed | 1352 MHz | 1352 MHz |
| GPU | 1008 MHz | 1008 MHz | 1008 MHz |
| RAM | 1800 MHz | 2040 MHz | **2136 MHz** |
| NPU | 1008 MHz | 1008 MHz | 1008 MHz |

The CPU rails run at 1540 mV, the PMIC maximum. The GPU sits at 960 mV for
1008 MHz — its efficient peak, since 1200 MHz draws more power and scores
*lower* on glmark2.

### The RAM wall was voltage, not timings

The obvious approach — loosening timings — got nowhere. What moved the ceiling
was the **VDD2 rail**: raising it, and setting proper `dcdc4` voltage floors in
the device tree, took DRAM from 1800 to 2040 and then 2136 MHz.

2400 MHz **refused training** across three configurations. That is a hard stop
on this 12 GB silicon, not a tuning problem.

### 3.0 GHz is a clock-driver limit, not a silicon one

The A76 ceiling was not thermal or electrical — it was the `sunxi-ng` clock
driver's dividers. Once that was addressed the cores hold 3000 MHz through
sustained all-core load without throttling (see [BENCHMARKS.md](BENCHMARKS.md)).

### DSU / L3 — the multiplier nobody mentions

The DSU (the interconnect and shared L3) has its own OPP table that is not
exposed by default. Raising it to 1352 MHz lifts memory-bound work across the
board — it is why the LLM generation figures improved without any CPU change.
`a7a-clock dsu` drives it through the `dsu_oc` module parameter.

---

## Boot configuration

**Partition 3 must have GPT type `EF00`** (EFI System), not `8300`. Allwinner's
U-Boot only scans EFI-typed partitions for `extlinux.conf`. Changing this type
breaks auto-boot, and it is the single most common way to brick a working card.

`/boot/extlinux/extlinux.conf` lives on partition 3 and selects the GPU clock:

```
default g1008
menu title Radxa Cubie A7A
prompt 0
timeout 50

label g1008
    menu label Debian 13, Linux 6.6.98+ (GPU 1008 MHz)
    linux /boot/vmlinuz-6.6.98+
    fdtdir /usr/lib/linux-image-gpu1008/
    append root=/dev/mmcblk0p3 rootwait rootfstype=ext4 console=ttyAS0,115200 loglevel=4 cma=128M
```

Entries `g800`, `g1008` and `g1200` differ **only** by `fdtdir` — each directory
holds a device tree with a different GPU ceiling and matching voltage.

The file is immutable (`chattr +i`) on shipped images. To edit it:

```bash
sudo chattr -i /boot/extlinux/extlinux.conf
# edit
sudo chattr +i /boot/extlinux/extlinux.conf
```

Root is specified as `/dev/mmcblk0p3` rather than by UUID because there is no
initramfs to resolve UUIDs.

---

## Memory tuning

ZRAM is configured by default (6 GB, LZ4 — roughly doubles usable memory):

```bash
sysctl -w vm.swappiness=100          # right for zram, wrong for disk swap
sysctl -w vm.vfs_cache_pressure=50   # keep dentries cached
sysctl -w vm.dirty_ratio=20          # SD card writeback
sysctl -w vm.dirty_background_ratio=5
```

---

## Display colour fix (R/B swap)

The PowerVR DDK GL stack (24.2@6603887) writes red and blue **swapped** into
every buffer it renders — server-side glamor and client EGL alike. A blue
YouTube logo is the telltale.

CPU rendering through the same display engine is correct, so the fix inverts the
display engine's channel interpretation for 32-bit RGB formats to match what the
GL stack actually writes:
`patches/0001-sunxi-drm-de-swap-rb-channels-for-pvr-glamor.patch`.

It swaps the four RGB returns in `drm_to_de_format()`, mirrors the TFBC/AFBC RGB
byte-order tables, and leaves YUV and the fbdev/logo path untouched.

**Known cosmetic side effect:** the CPU-drawn boot logo and fbcon show swapped
colours — the penguins' beaks go blue. The GPU desktop, which is what you look
at all day, is correct.

---

## Cursor trails, and why the desktop uses software 2D

The DDK defers its render kick, so glamor leaves cursor trails. The kernel-side
cause is a missing `DIRTYFB` callback in the sunxi DRM driver, fixed in
`patches/` — but the real cure was switching the X server to `AccelMethod "none"`,
which drops CPU use for the same workload from around 60% to 0.6%.

The consequence is that **anything drawn through X is software-rendered.**
Hardware GLES is reachable only through KMS/GBM, which is what `a7a-game` uses.

---

## Source repos

| repo | branch | purpose |
|---|---|---|
| [radxa/kernel](https://github.com/radxa/kernel) | `allwinner-aiot-linux-6.6` | Linux 6.6.98 BSP kernel |
| [radxa/allwinner-bsp](https://github.com/radxa/allwinner-bsp) | `cubie-aiot-v1.4.8` | BSP drivers, GPU, NPU |
| [radxa/allwinner-bsp](https://github.com/radxa/allwinner-bsp) | `cubie-aiot-v1.4.6` | wifi USB driver (1.4.8 has bugs) |
| [radxa/allwinner-device](https://github.com/radxa/allwinner-device) | `device-a733-v1.4.8` | DTS, defconfig, sys_config |
| [radxa/allwinner-target](https://github.com/radxa/allwinner-target) | `target-a733-v1.4.6` | wifi firmware, rootfs overlay |
| [radxa/u-boot](https://github.com/radxa/u-boot) | `allwinner-aiot-v2018.07` | U-Boot |
| [ZIFENG278/ai-sdk](https://github.com/ZIFENG278/ai-sdk) | `main` | NPU SDK (VIPLite 2.0) |
