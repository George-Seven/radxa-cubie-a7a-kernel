# A year of getting one board to work properly

Building a custom kernel and device tree for the Radxa A7A to work on Debian 13
has been a long and rewarding journey that I am very proud of, and it is the
first real thing I have published on GitHub.

A year ago I bought this board. I looked at the specs and thought *wow, this has
serious hardware for the price*, and bought it immediately. I went on the Radxa
site and found tons of documentation — but they had only shipped Debian 11. I
downloaded it, and yes, it worked. But there was a lot of mismatch in how the
software and the hardware were talking to each other.

I did some researching and found that the fix was not in the operating system at
all. It was in the **device tree** — the file that tells the kernel what hardware
is actually present and how it is wired. If that description is wrong, Linux does
the wrong thing with real silicon, and nothing above it can save you. So I
started editing the DTB. And I found I could update the kernel too.

What followed was a lot of tireless nights. Edit the device tree, compile it,
write it to the card, put the card in the board, watch it fail, pull the card,
put it back in the computer, edit again. Over and over. Some of those loops took
a very long time and told me nothing at the end of it. A few times I got nearly
to the end and the image got overwritten or corrupted, and **months of work were
gone**.

> I am proud to announce that Debian 13 for the Radxa A7A is here, and it is more
> stable than ever.

---

## What it took to get here

The parts below are the ones people ask about. Each of them looked like one
problem and turned out to be another.

### The RAM was never about timings

The board ships its LPDDR5 at 1800 MHz. Getting more out of it looked like a
timing problem, so that is where I spent my time — and got nowhere, for a long
time.

The wall turned out to be a **voltage rail**. VDD2. Nothing I did to timings moved
anything until that rail came up: 1080 mV, then 1120, then 1200. Once it was
raised, the memory trained at speeds it had refused before.

What made this so slow is where the setting lives. The DRAM frequency is not in
the device tree, or anywhere Linux can reach. It is in the **boot0 parameter
table** — firmware that runs before the kernel exists. So every attempt meant
flashing firmware, booting, and reading the training result over the serial
console, because storage was not up yet to write a log to. Get it wrong and the
board does not boot at all; it just sits there, and the only way to know why is
the serial cable.

| DRAM | clock | sequential read |
|---|---:|---:|
| stock | 1800 MHz | 2865 MB/s |
| now | 2136 MHz | ~3.3 GB/s |
| tried, refused | 2400 MHz | would not train |

2400 MHz refused to train across three different configurations. That one is a
real limit on this silicon, not something I was doing wrong — and I would rather
say so than keep pretending there is more in it.

### The GPU: colours reversed, trails everywhere, and a driver ignoring me

The graphics were three separate problems wearing one coat.

**Red and blue were swapped.** Everything the GPU rendered came out with the red
and blue channels reversed — the giveaway is a blue YouTube logo. What made it
confusing is that CPU-drawn things were fine, so the display engine clearly
worked; only the GPU path was wrong. The fix inverts how the display engine
interprets 32-bit RGB, to match what the graphics stack actually writes.

**The cursor left trails** across the screen. That turned out to be a missing
callback in the kernel's display driver: the X server asks the kernel whether it
can track damaged screen regions, the kernel said no, and X silently gave up on
damage tracking for the rest of the session — logging a line that reads like a
decision rather than a failure.

**And the GPU kept resetting at higher clocks**, which looked like the clock being
unstable. It was not. My voltage table was being *ignored entirely*, because the
graphics driver Allwinner ships is built without DVFS support compiled in — so
the code that reads those voltages does not exist in the binary. The GPU was
asking for 800 mV no matter what I wrote. The workaround was to set a floor on
the rail itself, so the regulator brings it up at boot and the driver's low
request gets clamped upward. Clocks that had been producing artefacts and resets
ran clean after that.

> **Still true today.** That last one affects every A7A, not just overclocked
> ones. If a future Allwinner BSP built the driver with DVFS enabled, proper GPU
> power management would work and the workaround could be thrown away.

### The board would not boot from SD — and it was not my fault

Early on I lost a lot of time to cards that simply would not boot, with no
message. The images carried the **wrong U-Boot variant** — the one built for UFS
storage, which never scans the SD card at all. There was nothing wrong with the
system on the card; the bootloader was never going to look for it.

Related: the root partition has to be marked as an EFI System partition, because
Allwinner's U-Boot only scans EFI-typed partitions for its boot config. Change
that partition type to what looks correct and the board stops booting.

### Gigabit ethernet that looked like a bad cable

SSH would connect and then hang. `apt` would stall partway. Pings were fine. The
link reported 1000/full with no errors. I replaced cables.

The device tree sets a transmit timing value for the ethernet PHY, and the
shipped value sits outside the window the PHY accepts. Frames above a certain
size get corrupted on the way out. The cruel part is that the corruption is
**data-dependent** — if you test with a payload of repeated bytes it passes
perfectly, which is exactly what a quick sanity test does. You have to test with
random data or you will convince yourself the board is fine.

### Wi-Fi locked out of 5 GHz, and unfixable from userspace

The Wi-Fi was stuck in the world regulatory domain, which forces passive scanning
on every 5 GHz channel and makes reconnecting slow. The usual fix is to set your
country — except that silently did nothing, because the kernel could not resolve
a country code at all.

The regulatory database is requested during kernel startup, before the root
filesystem is mounted, and these images have no initramfs — so the request always
failed and the world domain latched in. The fix was to compile the database into
the kernel itself. Link rates went from 144 Mbit/s to 288–360.

### Everything else

- **Suspend never came back.** The board would go to sleep and simply not
  return — dark display, no network, power cycle the only way out. The journal
  showed suspend entries with no matching exits. The desktop asks for it on an
  idle timer by default, so an unattended board hits it within the hour and it
  looks exactly like a crash.
- **Core dumps ate the SD card.** Crash dumps were being written into home
  directories at 400–600 MB each. One board had 14 of them — 2.6 GB — and
  eventually died of a full disk, which of course looks like a completely
  different problem.
- **Every interrupt landed on one small core.** Network, USB and storage all
  queued on a single A55 while both big cores did nothing — and since the Wi-Fi
  is USB-attached, Wi-Fi was queued behind the SD card.
- **The A76 ceiling was the clock driver**, not the silicon and not heat. Once
  that was addressed the cores hold 3.0 GHz.
- **The DSU — the interconnect and shared L3 — has its own clock** that nothing
  documents and nothing exposes. Raising it from 780 to 1352 MHz is worth about a
  third of memory bandwidth, but only once the DRAM is overclocked too. At stock
  DRAM it measures under 1%, which is presumably why nobody mentions it.
- **The whole OS had to move from Debian 11 to 13 in place**, through Bookworm,
  holding kernel packages so the upgrade could not replace the thing keeping the
  board alive.

---

## What you get now

- **Debian 13, kernel 6.6.98** — two image variants, a conservative one and a
  maximum overclock. Single file, flash and go, grows to fill your card on first
  boot.
- **Real overclocking** — A76 at 3.0 GHz, A55 at 2.8, DSU at 1352 MHz, RAM at
  2136. Validated, not guessed.
- **A clock control panel** — GUI and command line for every tunable rail: CPU,
  GPU, DSU, memory, NPU, Wi-Fi band. It refuses values the hardware never
  declared.
- **A local LLM** — llama.cpp built for this board with a desktop app. Runs a 4B
  model at conversational speed, entirely offline.
- **Games on the GPU** — SuperTuxKart running on the PowerVR hardware, not
  software rendering.
- **Update-proof** — apt cannot replace the kernel or rewrite the boot config,
  which is how earlier images died.

It outperforms a Pi 5 by a mile, and it is genuinely pleasant for everyday tasks
and games.

---

## You need active cooling. This is not optional.

These images run the board **overclocked out of the box**. A 60-second all-core
load reaches **76 °C and is still climbing**, against an 80 °C throttle point —
measured with a heatsink and PWM fan already fitted and running.

Without cooling you will hit thermal throttling quickly, and sustained load on a
bare board risks damaging it. Fit cooling before you flash this, not after.

## Please tell me what breaks

I hope you enjoy it. If there are any issues, please let me know — open an issue
on the repository. **Suggestions and requests are welcome too**, not just bug
reports. If there is something you want this board to do that it does not do yet,
say so.

One thing I will be upfront about: all of this is validated on **one board**.
Silicon varies. If your unit behaves differently, especially at the overclocked
settings, I want to hear about it.

## Disclaimer

This software is provided **as is, with no warranty of any kind**, express or
implied. You use it entirely at your own risk. Overclocking can cause
instability, data loss, shortened component life, or permanent damage, and will
almost certainly **void any warranty** you have. This project is not affiliated
with Radxa or Allwinner.

**I accept no responsibility for any damage, data loss, or other harm resulting
from the use of these images, packages, or instructions.** If you are not
comfortable with that, use Radxa's official images instead — they are supported
by the vendor, and I would rather you had a working board than a bricked one.
