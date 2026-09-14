# ether-lineage

LineageOS for the **Nextbit Robin** (`ether`, msm8992 / Snapdragon 808, 2016). `main` carries no
build config; each Android version is its own branch, named after the upstream LineageOS branch.

| branch | Android | status |
|---|---|---|
| [`lineage-20.0`](../../tree/lineage-20.0) | 13 | released — see [Releases](../../releases) |
| [`lineage-21.0`](../../tree/lineage-21.0) | 14 | in progress; the last version this device will get |

LineageOS never carried ether past 18.1. These branches replay a patch series onto the recovered
19.1 device tree ([ether-trees](https://github.com/TheDBP/ether-trees)) and are built with
[rom-forge](https://github.com/TheDBP/rom-forge), vendored as `forge/` on each branch.

Installing, building, what is fixed and what is not: the README on the branch.
