# Measured performance

Every figure here was measured on hardware, with the date it was taken. Where an
older number was superseded, the old one is shown struck through rather than
quietly deleted — knowing a figure changed is often more useful than the figure.

---

## CPU

| Cluster | Cores | Stock | This project | Rail |
|---|---|---|---|---|
| Cortex-A76 | 2 | 2002 MHz | **3000 MHz** (+50%) | 1540 mV (PMIC max) |
| Cortex-A55 | 6 | 1794 MHz | **2800 MHz** (+56%) | 1540 mV (PMIC max) |
| DSU / L3 | — | not exposed | **1352 MHz** | 1000 mV |

### Sustained load — no throttling, but plan for cooling

60 seconds, all 8 cores, performance governor pinned, 2026-08-24:

| elapsed | A76 | A55 | temp | cooling |
|---|---|---|---|---|
| 5 s | 3000 MHz | 2800 MHz | 62 °C | fan state 4 |
| 30 s | 3000 MHz | 2800 MHz | 69 °C | fan state 4 |
| 60 s | 3000 MHz | 2800 MHz | **76 °C, still rising** | fan state 4 |

**No frequency throttling occurred** — both clusters held full clocks for the
whole run. But 76 °C at 60 s against an **80 °C passive trip** is a narrow
margin, and the curve had not flattened. Active cooling is not optional at
these clocks. Critical trip is 110 °C. Idle is 37 °C.

> An earlier revision of this document claimed a 53 °C peak for this same test.
> Re-running it measured 76 °C. The old figure understated the thermal load
> substantially and should not be relied on.

---

## Local LLM (llama.cpp, `a7a-llm`)

Qwen3 4B Instruct Q4_0 — the shipped default — on the maximum-overclock image
with the performance governor pinned, as `a7a-llm serve` does. Measured
2026-08-24, `llama-bench`, 3 repetitions.

| phase | threads | tok/s |
|---|---|---|
| prompt processing (pp128) | 8 | **28.06 ± 0.04** |
| generation (tg32) | 2 | **4.67 ± 0.00** |

### The two phases want opposite thread counts

This is the single most counter-intuitive result on this board, and getting it
wrong costs 30–40% either way:

| threads | prompt (pp128) | generation (tg32) |
|---|---|---|
| 2 | 18.46 | **4.68** |
| 4 | 19.58 | 4.00 |
| 6 | 23.10 | 3.72 |
| 8 | **25.72** | 3.44 |

*(swept under schedutil, so absolute values are below the pinned figures above —
the trend is the point.)*

Generation is **memory-bound**: ggml splits work evenly and waits at a barrier
every layer, so adding the six slow A55 cores makes the two fast A76 cores wait.
Prompt processing is **compute-bound** and scales normally. llama.cpp accepts
`-t` for generation and `-tb` for batch, so `a7a-llm` sets `-t 2 -tb 8` and takes
the better half of both.

**This is not a thermal artefact.** Across the sweep the board warmed from 32 °C
to 64 °C, and prompt throughput *rose* over exactly that ramp while generation
fell. A thermal explanation would have depressed both.

### Quantisation matters more than usual here

**Use Q4_0, not Q4_K_M.** llama.cpp repacks Q4_0 into aarch64
dotprod-interleaved layouts and this SoC has `asimddp`: 17.1 tok/s prompt
processing against 7.5 for Q4_K_M, about 2.3×, at equal generation speed. (Both
halves measured 2026-08-13, before the memory and DSU overclocks — the ratio
holds, the absolute numbers are higher now.) A K-quant looks like the smarter
choice on paper and is the wrong one here.

---

## GPU — PowerVR BXM-4-64 MC1

| | |
|---|---|
| OpenGL ES | 3.2, validated on hardware |
| **glmark2-es2 (off-screen)** | **889** at GPU 1008 MHz + RAM 2040 MHz |
| | 745 at RAM 1800 MHz · 612 on a bare greeter |
| Daily clock | **1008 MHz @ 960 mV** — the efficient peak |
| Clock ladder | 600 / 800 / 1008 / 1200 MHz, voltage-matched, selectable at boot |
| Stability | 10-minute soak, zero hardware errors, peak 76 °C under CPU+GPU+RAM load |
| Driver | Imagination proprietary (`pvrsrvkm`) + R/B swap fix |

1200 MHz is stable but scores *lower* than 1008 for more power, so 1008 is the
default rather than the maximum.

> Figures published before the real bring-up ("Vulkan 1.3, glmark 32, OpenCL
> GFLOPS") were partly software-rendered through llvmpipe. They are superseded
> by the validated numbers above. **glmark2-es2 scores 889, not 32.**

---

## NPU — Vivante VIP9000

| | |
|---|---|
| Frequency | 1008 MHz |
| Throughput | 3 TOPS (INT8) |
| ResNet50 | ~7.8 ms, ~128 FPS (verified, `/v3` NBG models) |
| SDK | VIPLite 2.0 (ai-sdk) |

---

## Memory — 12 GB LPDDR5

| test | result |
|---|---|
| NEON copy | 5,057 MB/s |
| NEON fill | 8,369 MB/s |
| sysbench read, 1 thread | 13,477 MB/s |
| sysbench write, 1 thread | 10,335 MB/s |
| sysbench read, 8 threads | 18,237 MB/s |
| sysbench write, 8 threads | 33,300 MB/s |
| ZRAM swap | 6 GB, LZ4 |

Stock is 1800 MHz. **2040 MHz is validated and memtester-clean** (standard
image); **2136 MHz** ships in the maximum image. 2400 MHz **refused training**
on this 12 GB silicon across three configurations.

The wall was voltage, not timings — see [HARDWARE.md](HARDWARE.md).

---

## Storage

| test | result |
|---|---|
| SD card (SDR104) sequential write | ~80 MB/s |
| SD card sequential read | 87 MB/s (measured 2026-08-25, `dd`, direct I/O) |
| USB 3.1 SuperSpeed port | ~185 MB/s |
| USB 2.0 hub ports | 39 MB/s |

**Which USB port you use is a 5× difference.** The board exposes one 10 Gbit/s
SuperSpeed root hub and a 480 Mbit/s hub carrying wifi, bluetooth and HID. A
drive on the slow hub reads at 39 MB/s — *less than half the speed of the SD
card*. Put storage on the blue SuperSpeed port.

UFS is not available on SD-boot boards: the controller probes and
`ufshcd_async_scan` fails, because the chip is not populated.

---

## Network

| | |
|---|---|
| Ethernet | 1000 Mb/s full duplex (with the tx-delay fix; broken without it) |
| Wifi | AIC8800D80, Wi-Fi 6 |
| — measured link | 5220 MHz (ch 44), 80 MHz, HE-MCS 7, 360 Mbit/s rx · 288 Mbit/s tx |
| — regulatory | country code applied from the kernel's embedded `regulatory.db` |

Measured 2026-08-25 on the maximum image.
