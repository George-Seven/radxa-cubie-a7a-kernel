# Contributing

Thanks for looking. This is an independent project maintained by one person on
one board, so help is genuinely useful — particularly testing on hardware I do
not have.

## The most useful things you can do

**Test on your board and tell me what happens.** Everything here is validated on
a single unit. Silicon varies, and the overclock profile especially may not hold
on yours. A report saying "this works" is as useful as one saying it does not.

**Tell me whether a bug also happens on Radxa's official image.** This single
question separates a problem I introduced from a problem in the board or the
BSP, and it is the first thing I will ask.

**Suggestions and requests are welcome**, not just bug reports. If there is
something you want this board to do that it does not do yet, open a
[suggestion](../../issues/new?template=feature_request.yml).

## Reporting a bug

Use the [bug report template](../../issues/new?template=bug_report.yml). It asks
for the board variant, the image version, and whether you have cooling fitted —
those three answers resolve most reports on their own.

**On cooling:** these images ship overclocked. A 60-second all-core load reaches
76 °C against an 80 °C throttle point *with a heatsink and fan fitted*. If you
are running without cooling, instability is expected rather than a bug — fit
cooling and retest before reporting.

## Sending code

Pull requests are welcome. A few things that will make yours easy to merge:

- **Say what you measured.** This project tries hard not to publish numbers it
  has not verified. If your change makes something faster or more stable, say
  how you know — and what the method was.
- **Keep kernel patches minimal and explain the reasoning in the commit
  message.** The patches here are deliberately small so they can be sent
  upstream to Allwinner or Radxa.
- **Do not touch `/boot/extlinux/extlinux.conf` from a package.** It is marked
  immutable on purpose. `u-boot-menu` regenerating it on kernel updates is what
  broke earlier images.
- **Never commit board identity.** No SSH host keys, no `machine-id`, no wifi
  credentials, no `authorized_keys`. The image build fails if any of those
  survive into a published image, and the same rule applies to the repo.

## Two testing traps worth knowing

These cost me real time, and they will silently mislead you too:

- **Do not test ethernet with constant-byte payloads.** The RGMII corruption is
  data-dependent — a payload of one repeated byte passes perfectly on a board
  that cannot hold an SSH session. Use random data.
- **Do not grep a kernel image for the string `regulatory.db`** to check whether
  the regulatory database is embedded. That string is just the filename cfg80211
  requests and appears in kernels that do not embed it at all. Check for the
  `RGDB` magic bytes instead.

And one about the hardware: **the board has no RTC battery**, so timestamps
across reboots are not comparable. Do not diagnose anything from a gap between
one boot's logs and the next.

## Building

See [docs/BUILDING.md](docs/BUILDING.md) for the kernel, GPU module, wifi driver
and NPU SDK. `BSP_TOP=bsp/` is not optional — without it the build dies with an
error that does not mention the missing variable.

## Licence

This project is GPL-2.0. By contributing you agree your contribution is licensed
the same way. Upstream copyright — Allwinner's and Imagination's — stays intact;
if you modify one of their files, add your note alongside theirs rather than
replacing it.
