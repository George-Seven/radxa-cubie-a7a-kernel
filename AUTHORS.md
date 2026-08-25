# Authors and provenance

## Author

**Rabs9** — [github.com/Rabs9](https://github.com/Rabs9)

All original work in this repository — the device trees, kernel patches,
packaging, tooling and documentation — is by Rabs9 unless a file's own header
says otherwise.

## Identity across the history

Commits in this repository appear under more than one name. They are the same
person, and this note exists so that is verifiable rather than assumed:

| appears as | what it is |
|---|---|
| `Rabs9` | current GitHub account and git author name |
| `falcon` | git author name used on early commits, before the switch to the GitHub noreply address |
| `tittyyhead` | previous name of the same GitHub account, renamed to `Rabs9` |

The anchor is the GitHub account itself: **numeric id `241389662`, created
2025-11-01**. A GitHub account keeps its id across a rename, so the id ties the
old name and the new one to one account. Nothing in that chain depends on
taking anyone's word for it.

## Signing key

Releases from 2026-08-25 onward are signed with:

```
ed25519/EF8243C0E3ADC6EA
C9E8 FC3E 6B94 6616 B0BB  B09B EF82 43C0 E3AD C6EA
Rabs9 <241389662+Rabs9@users.noreply.github.com>
```

The public key is in this repository as
[`Rabs9-public-key.asc`](Rabs9-public-key.asc). Verification instructions are in
the [README](README.md#verifying-releases).

Publishing the fingerprint here, in the repository rather than only alongside
the release assets, is deliberate: a signature is only meaningful if the key can
be checked somewhere an attacker who controls the download does not also
control.

## Timeline

| date | what |
|---|---|
| 2025-11-01 | GitHub account created |
| 2025-11-05 | first published Radxa Cubie A7A work — overclocking research and configuration |
| 2026-05-01 | `radxa-cubie-a7a-kernel` created; custom 6.6.98 kernel and device trees |
| 2026-08-22 | gigabit Ethernet RGMII tx-delay defect found and fixed |
| 2026-08-25 | Debian 13 images and Debian packages published |

## Archive

The full repository, including its complete commit history, is preserved
independently by [Software Heritage](https://www.softwareheritage.org/) — a
UNESCO-backed archive for source code:

```
swh:1:snp:92c82a6182f9e7d78b7cc315e705990777464d7c
```

Archived 2026-08-25, visit status `full`. That identifier is derived from the
repository's contents, so it cannot be forged or reassigned. It can be resolved
at [archive.softwareheritage.org](https://archive.softwareheritage.org/).

## Third-party copies

This project is GPL-2.0, so copying, modifying and redistributing it is
explicitly permitted — that is the point of the licence. Two conditions come
with it: the licence must travel with the copy, and attribution to this
repository as the original source should be kept.

If you are running a copy of this work that arrived without a `LICENSE` file,
it was redistributed incorrectly. The original is at
[github.com/Rabs9/radxa-cubie-a7a-kernel](https://github.com/Rabs9/radxa-cubie-a7a-kernel),
and improvements are welcome as pull requests there.

## Upstream

This project builds on work that is not its own, and those copyrights stay
intact:

- **Allwinner** — the BSP, drivers and original device trees (GPL).
- **Imagination Technologies** — the PowerVR DDK userspace, which is a
  proprietary binary redistributed as shipped.
- **Radxa** — the board, the original BSP branches, and the hardware
  documentation.
- **The Linux kernel community** — everything the kernel patches derive from.

Where an upstream file has been modified, the modification note is added
alongside the original copyright header, never in place of it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Testing on hardware other than the
single board everything here is validated on is the single most useful
contribution.
