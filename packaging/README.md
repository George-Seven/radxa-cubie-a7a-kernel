# Debian packages for the Radxa Cubie A7A 6.6.98 kernel

`build-a7a-kernel-debs.sh` turns the validated kernel on a running A7A into four
real `.deb` packages, so the image stops depending on hand-placed files in
`/boot` and `/lib/modules`, and DKMS / out-of-tree modules get a headers tree
that actually exists.

| package | contents |
|---|---|
| `linux-image-6.6.98-a7a` | `/boot/vmlinuz-6.6.98+`, `System.map`, `config`, `/lib/modules/6.6.98+/` |
| `linux-dtb-6.6.98-a7a` | device trees, one dir per GPU-clock boot variant |
| `linux-headers-6.6.98-a7a` | build tree in `/usr/src/`, with `/lib/modules/6.6.98+/build` pointing at it |
| `a7a-board-config` | `/etc/modules-load.d/a7a-bluetooth.conf` (loads `aic_btusb`) |

## Why it packages binaries instead of rebuilding

The shipped kernel was cross-compiled elsewhere. This script wraps the exact
image and modules that were validated on hardware, so what users install is what
was tested. The on-board source tree in `/home/radxa/kernel-6.6` is used only for
the headers package; its `.config` is byte-identical to the running kernel's
`/proc/config.gz` once toolchain-derived symbols (`CONFIG_CC_*`, `CONFIG_AS_*`,
`CONFIG_GCC_*`) are excluded.

## Build

On the board:

```sh
mkdir -p ~/debbuild/src
cp System.map-6.6.98+ ~/debbuild/src/      # from the tree that built the kernel
cp build-a7a-kernel-debs.sh ~/debbuild/
cd ~/debbuild && ./build-a7a-kernel-debs.sh
```

Output lands in `~/debbuild/out`. Overridable variables: `PKGVER`, `MAINT`,
`SRCKERNEL`, `SYSMAP`, `KTREE`, `TXDELAY`, `B`.

## Install

```sh
sudo apt install ./linux-dtb-6.6.98-a7a_*.deb ./linux-image-6.6.98-a7a_*.deb \
                 ./linux-headers-6.6.98-a7a_*.deb ./a7a-board-config_*.deb
```

The packages do **not** touch `/boot/extlinux/extlinux.conf`. That file is
deliberately `chattr +i` on this image so `u-boot-update` cannot regenerate it
and lose the GPU-clock variant entries. To boot the packaged kernel, add:

```
label pkg
	menu label Packaged kernel (6.6.98+)
	linux /boot/vmlinuz-6.6.98+
	fdtdir /usr/lib/linux-image-6.6.98+/
	append root=/dev/mmcblk0p3 console=ttyAS0,115200n8 rootwait clk_ignore_unused loglevel=7 rw earlycon consoleblank=0 console=tty1 coherent_pool=2M irqchip.gicv3_pseudo_nmi=0
```

(`sudo chattr -i` first, `sudo chattr +i` after.) This kernel boots without an
initramfs.

## Gigabit Ethernet: tx-delay

The device trees built by this script set the RGMII `tx-delay` of
`ethernet@4500000` to **9**. The vendor value is 12, which leaves the MAC-to-PHY
transmit timing marginal.

**What the fault looks like.** The link negotiates 1000/full, `ip link` shows
`LOWER_UP`, `tx_errors` and `collisions` stay at zero, and short pings reply. But
SSH completes key exchange, the server logs `Accepted publickey` and opens the
session, and the client then hangs forever. `apt` hangs. Bulk transfers hang. It
reads exactly like a bad cable or a flaky switch.

**It is transmit-only, and it is data-dependent.** Marginal RGMII timing corrupts
frames according to the bit pattern being clocked out, so the failure rate rises
both with the number of bits on the wire and with the entropy of the payload.
One-way UDP, 50 datagrams per cell, 1472-byte payload, at tx-delay 12:

| payload pattern | received |
|---|---|
| one repeated byte | 49/50 |
| incrementing bytes | 0/50 |
| random | 1/50 |

At tx-delay 9 all three are 50/50. **This is why a naive test can report
success:** a payload of a single repeated byte has few signal transitions and
survives, while real traffic does not.

Loss by frame size with random payloads, one-way UDP, 50 datagrams per size:

| payload bytes | 64 | 128 | 300 | 400 | 600 | 1000 | 1200 | 1472 |
|---|---|---|---|---|---|---|---|---|
| loss at tx-delay 12 | 12% | 44% | 72% | 78% | 98% | 98% | 100% | 100% |
| loss at tx-delay 9 | 0% | 2% | 0% | 0% | 4% | 0% | 2% | 2% |

There is no clean size threshold — even minimum-size frames lose 12%.

**Receive is unaffected.** With tx-delay at 12, the board received 100 of 100
inbound 1400-byte UDP datagrams, every sequence id intact. During a ping run that
reported 95% loss, the board's own counters showed 20 echo requests queued to the
NIC and only 1 reply returning — the requests were leaving corrupted, so the peer
never answered.

**Working window.** Sweeping the runtime knob, 20 pings of 1472 bytes per step:

| tx-delay | 5 | 6 | 7 | **8** | **9** | **10** | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|---|
| loss | 100% | 100% | 100% | **0%** | **0%** | **0%** | 35% | 90% | 100% | 100% |

9 is the centre of the passing window and is what ships. Throughput at 8/9/10 is
415/407/376 Mbit/s with TCP retransmits under 0.01%.

**Ruled out.** Two different Ethernet cables give the same window and the same
failure at 12. Removing USB peripherals changes nothing. Packet pacing changes
nothing (100% loss at 2 ms, 10 ms, 50 ms and 200 ms gaps). The delay is a
MAC-to-PHY timing register on the board, upstream of the RJ45 jack, so no cable
can cause or cure it.

**Runtime override**, no reboot needed:

```sh
echo 9 | sudo tee /sys/class/net/end0/device/tx_delay
```

The source fix is in `configs/board-overclocked.dts`.

### Reproducing

Receiver, on another machine:

```sh
python3 - <<'EOF'
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(("0.0.0.0",5003)); s.settimeout(5)
n=0
try:
    while True:
        s.recvfrom(65535); n+=1
except socket.timeout:
    print("received", n)
EOF
```

Sender, on the board (swap 12 for 9 to see it pass):

```sh
echo 12 | sudo tee /sys/class/net/end0/device/tx_delay
python3 -c '
import socket,os,time
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
for i in range(50): s.sendto(os.urandom(1472),("<receiver-ip>",5003)); time.sleep(0.004)'
echo 9 | sudo tee /sys/class/net/end0/device/tx_delay
```

## Known gaps

* `Module.symvers` is not shipped, because the on-board tree was never used for a
  full module build. Out-of-tree builds therefore need `KBUILD_MODPOST_WARN=1`
  and will print unresolved-symbol warnings. `CONFIG_MODVERSIONS` is off in this
  kernel, so the modules still load correctly.
* BSP-aware builds must pass `BSP_TOP=bsp/`; `bsp/Kconfig` sources
  `$(BSP_TOP)platform/Kconfig` and fails without it.

## Board identity

These images are produced by dumping a working development card, so without a
deliberate step every board flashed from one inherits that card's identity: the
SSH host keys, the snakeoil TLS certificate, the machine-id, the fwupd client
key, saved network profiles and the desktop's caches. Two boards from the same
image are then indistinguishable on the network.

`packaging/sanitise-image.sh SRC OUT MARKER` handles this at build time. It
resets the user profile wholesale rather than deleting known-bad files one at a
time, then copies the surviving tree into a **virgin ext4** with the same UUID,
because deleting a file leaves its blocks, its journal records and its directory
entry behind. Nothing is published from a filesystem that ever held the data.

The gate at the end deliberately does two different kinds of check:

  * a raw byte scan for strings that could never legitimately appear in a
    distributed image, which is what catches deleted-file residue;
  * a structural walk for actual credential *files*.

Byte-grepping for `BEGIN PRIVATE KEY` or `klipper` does not work and was tried:
`ssh-keygen`, `libgnutls`, `libnm` and friends all contain those PEM headers as
literal strings because they are the programs that write them, and `klipper` is
a KDE package the image is supposed to ship. Those patterns cannot tell a key
file apart from a program that knows what a key looks like. The structural check
can, and is what found `/var/lib/fwupd/pki/secret.key`.

`tools/a7a-reset-identity` is the same job for a board that is already running.
It regenerates host keys, the TLS certificate, the machine-id and the fwupd key
without asking, and prompts before touching saved network profiles or
`authorized_keys`, since those may be the owner's. `--check` reports only.
