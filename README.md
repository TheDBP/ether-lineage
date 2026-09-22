# Nextbit Robin — LineageOS 21 (Android 14)

**Skeleton. Nothing on this branch has been synced, built or flashed.** It is the released
[`lineage-20.0`](https://github.com/TheDBP/ether-lineage/tree/lineage-20.0) tree — same 50-patch
series, vendored trees and `PORT-LOG.md` — with `device.conf` and the local manifest retargeted to
`lineage-21.0`. What the port is, what it changes and how to install it: the 20.0 README.

21 is the Robin's last version. LineageOS 22 needs a 4.19+ kernel (`NetBpfLoad` exits on anything
older) and the Robin's is 3.10. The scoping, go/no-go criteria, patch-by-patch expected fate and
phase plan are in **[PLAN.md](PLAN.md)**; the eBPF/cgroup reading behind criterion 1 is in
`scoping/`.

## What differs from `lineage-20.0`

| | |
|---|---|
| `device.conf` | `BRANCH=lineage-21.0`, `LUNCH_TARGET=lineage_ether-ap2a-userdebug` (21 has `build/release`), JDK 17 |
| `overlay/local_manifests/ether.xml` | `hardware/sony/timekeep` at `lineage-21`; kernel, blobs and CAF HALs stay on their 18.1 pins |
| presets | `libre` = `fdroid`, `firefox`; `full` = + `gapps`. K-9, TermOne Plus and KDE Connect have no `lineage-21.0` option patches yet, so they are not in the presets |
| `PLAN.md`, `scoping/` | this branch only |

Expected to need work before the first build (from `PLAN.md`): `frameworks/libs/net` moved to
`packages/modules/Connectivity/staticlibs`; the Connectivity, netd and bpfloader patches re-derive
against 14's split loader; 13 of the 16 option patch sets have no `lineage-21.0/` directory in the
forge yet.

## Building

Do not, until phase 1 in `PLAN.md` says go. The command will be the same as on 20.0:

```sh
PRESET=clean ./forge/bootstrap.sh
```

## Layout

| | |
|---|---|
| `device.conf` | what this device is, and its presets |
| `overlay/patches/` | the 20.0 patch series, unchanged until phase 1 |
| `overlay/local_manifests/` | extra projects the manifest does not carry |
| `vendored/` | recovered 19.1 device tree and pre-rename qcom `sepolicy-legacy` — see `vendored/README.md` |
| `forge/` | the shared build engine, vendored (do not edit here) |
| `PLAN.md`, `scoping/` | the 21 scoping |
| `PORT-LOG.md` | the 20.0 port log, carried forward |

## License

Apache-2.0 — see `LICENSE`. The patches under `overlay/patches/` modify Apache-2.0 (AOSP/LineageOS)
and GPL-2.0 (kernel) code and carry those licenses; `vendored/` keeps its upstream licenses.
