# Boot Fix — image won't boot / hangs before login

Images of this project built **before 2026-08-10** can fail to boot on their
own. The system on the card is fine — the boot *chain* had two independent
defects. Both are fixable in place, no reflash needed. (Both are fixed in the
golden image released 2026-08-10; if you flash that, none of this applies.)

## Symptoms (serial console, UART0 @ 115200)

| What you see | Which defect you have |
|---|---|
| U-Boot starts, never scans the SD, dies trying PXE network boot (`Retrieving file: pxelinux.cfg/...` → `Config file not found`), `saveenv` loops `Saving Environment to SUNXI_FLASH... Failed (-19)` forever | **Defect A: wrong U-Boot variant** (a UFS/eMMC build that ignores SD) |
| U-Boot scans the SD (`mmc0 is current device` / `Scanning mmc 0:2...`) but finds nothing and halts silently | **Defect B: EFI partition is empty** (missing `boot.scr`) |

A card can have both (A masks B — after fixing A you may still need B).

## Defect B fix — put `boot.scr` on the EFI partition (2 minutes)

Partition 2 of the card ("boot", FAT32, ~300 MB) must contain the 132-byte
`boot.scr` from this directory. It chains U-Boot to the real boot menu:
`sysboot mmc 0:3 any 0x40200000 /boot/extlinux/extlinux.conf`.

On any Linux machine (card in a USB reader, shown here as `/dev/sdX`):

```bash
sudo mkfs.vfat -n efi /dev/sdX2        # ONLY if partition 2 has no filesystem
sudo mount /dev/sdX2 /mnt
sudo cp boot.scr /mnt/boot.scr
sudo mkdir -p /mnt/boot && sudo cp boot.scr /mnt/boot/boot.scr
sudo umount /mnt
```

## Defect A fix — replace the firmware region (5 minutes, read carefully)

The first 16 MiB of the card (before any partition) hold boot0 + BL31 +
U-Boot. Broken images carried a **UFS-variant** U-Boot (`2018.07-12`,
built Jan 2026) that never scans SD and cannot save its environment. The
working **SD-variant** (`2018.07-8`, built Aug 2025) is published as
`sd-firmware-region.img` in the release assets.

The copy must **preserve your card's GPT** (sectors 0–33), so it skips them:

```bash
# back up your current firmware region first — always:
sudo dd if=/dev/sdX of=firmware-backup.img bs=512 count=32768

# write the SD-variant firmware, GPT preserved:
sudo dd if=sd-firmware-region.img of=/dev/sdX bs=512 skip=34 seek=34 count=32734 conv=fsync
```

Sanity check before writing: `xxd -s 131076 -l 8 sd-firmware-region.img`
must show `eGON.BT0` (the Allwinner boot0 magic lives at 128 KiB on the
A733 — not 8 KiB as on older sunxi chips).

## While you're in there (optional but recommended)

If your image stalls ~90 s at boot with `Timed out waiting for device
dev-disk-by-uuid...`: the fstab UUIDs for `/config` and `/boot/efi` may not
match your card (they change when partitions are recreated). Boot the fixed
card, then:

```bash
lsblk -f                      # real UUIDs of p1 (config) and p2 (efi)
sudo nano /etc/fstab          # point both entries at the real UUIDs
                              # and add `nofail` to their option lists
```

## Verified result

With both fixes applied, the reference card boots **power → login in ~75 s,
fully hands-free**, with the display, 3.0 GHz A76 / 2.8 GHz A55 overclocks,
and 1200 MHz GPU clock all confirmed live (see benchmarks).
