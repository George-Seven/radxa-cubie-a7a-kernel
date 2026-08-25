# Installing on an existing system

If you already have Debian 13 running on your A7A and don't want to reflash, the
whole system ships as Debian packages.

---

> **Cooling and risk.** The `maximum` package overclocks CPU, GPU, memory and
> interconnect beyond manufacturer specification. A 60-second all-core load
> reaches 76 °C against an 80 °C throttle point *with a fan fitted* — active
> cooling is required, not optional. This is provided with **no warranty of any
> kind**; it may void yours, and I accept no responsibility for damage or data
> loss. See the [disclaimer](../README.md#disclaimer).

## The easy way — one package

Two bundles, matching the two images. Pick one; they conflict with each other by
design.

```bash
# more headroom, less margin — adds RAM 2136, DSU 1352, and a7a-clock
sudo apt install ./a7a-maximum_<date>_arm64.deb

# or the conservative one
sudo apt install ./a7a-standard_<date>_arm64.deb
```

Each bundle `Provides` and `Replaces` every individual package below, so you can
switch between them with a single `apt install` and apt resolves the rest.

Dependencies (`python3-pyqt6`, `iw`, `network-manager`, `kmod`) are pulled from
Debian automatically — which is why installing with `apt` and a path is better
than `dpkg -i`, since `dpkg` will not fetch them for you.

**Reboot after installing.** The kernel, device tree and boot entry all change.

---

## The granular way — individual packages

| package | what it does |
|---|---|
| `linux-image-6.6.98-a7a` | the kernel |
| `linux-dtb-6.6.98-a7a` | device trees, including the **gigabit ethernet fix** and the GPU clock ladder |
| `linux-headers-6.6.98-a7a` | headers for building out-of-tree modules |
| `a7a-board-config` | board-level fixes: suspend disabled, core dumps discarded, IRQ affinity, first-boot identity reset |
| `a7a-desktop-config` | display configuration and the compositor workarounds |
| `a7a-llm` | llama.cpp built natively, plus the `a7a-llm` CLI and GUI |
| `a7a-clock` | clock control panel — CPU, GPU, DSU, RAM, NPU, wifi band (maximum only) |
| `a7a-oc-profile` | the maximum overclock profile (maximum only) |

If you only want the ethernet fix and nothing else, `linux-dtb-6.6.98-a7a` is
the one package you need.

---

## Games

```bash
sudo apt install ./a7a-game_<version>_all.deb
```

This does **not** bundle a game. It `Depends: supertuxkart` from Debian and
ships only what makes it work on this hardware: a KMS launcher, a systemd unit,
a sudoers rule and a desktop entry.

The reason it needs a launcher at all: hardware OpenGL ES on the A733 is only
reachable **outside X**. The desktop deliberately runs `AccelMethod "none"`
because glamor on the PowerVR DDK produces cursor trails, so anything drawn
through X gets software rendering. `a7a-game` switches to a KMS/DRM session,
runs the game on the GPU, and hands the desktop back afterwards.

Launch it from the menu like any other application.

---

## Verifying what you downloaded

```bash
sha256sum -c SHA256SUMS
```

---

## Boot chain safety

These packages deliberately **do not touch `/boot/extlinux/extlinux.conf`**.
That file is marked immutable (`chattr +i`) on the images, because `u-boot-menu`
regenerating it on kernel updates is what broke earlier systems.

The apt pins in `/etc/apt/preferences.d/99-a7a-custom-kernel` block stock
`linux-image-*`, `u-boot-menu` and `flash-kernel` at priority `-1`. Every image
build tests a full `apt upgrade` and verifies by hash that the kernel was not
replaced, so "safe to update" is a tested claim rather than an assurance.

---

## Board identity

Images ship with **no SSH host keys** and a blank `machine-id`. On first boot,
`a7a-firstboot` generates host keys for your board and systemd creates a fresh
machine-id.

This matters: if an image shipped with host keys baked in, every board flashed
from it would present the same SSH identity, and anyone holding the image could
impersonate any of them. You will see the usual "authenticity of host can't be
established" prompt on your first connection — that is the mechanism working.

If you have connected to that address before, clear the stale entry:

```bash
ssh-keygen -R <board-ip>
```
