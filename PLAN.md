# lineage-21.0 (Android 14) on the Robin — scoping plan

Status: **skeleton, not started.** This branch is the released `lineage-20.0` tree (same patch series,
vendored trees and port log) with `device.conf` and the local manifest retargeted. Nothing has been
synced or built. Do not build from it until phase 1 says so.

Trigger: the 20.0 release is out. Then 21 starts straight away — it is the Robin's last version, so
finish it while the tree and the hardware are still in hand, rather than wait for 20.0 to lose
support. 21 is the *next* step, not the newest one available.

## Why 21 is the ceiling, not just the next step

`packages/modules/Connectivity/netbpfload/NetBpfLoad.cpp` on `lineage-21.0` (read 2026-09-14):

```
if (isAtLeastU && !isAtLeastKernelVersion(4, 14, 0))  ALOGW("Android U requires kernel 4.14.");   // warning
if (isAtLeastV && !isAtLeastKernelVersion(4, 19, 0))  { ALOGE(...); return 1; }                   // fatal
```

On a 3.10 kernel, 21 (U) warns; 22.x (V) exits and the network stack never comes up. There is no
22 for this phone without a kernel that does not exist. So 21 is where the Robin ends, and the
question this plan answers is only whether 21 is reachable.

## Go / no-go

Go when all three hold after phase 1; otherwise stay on 20.0 and close this branch.

1. `netd` + `Connectivity` on 21 have a non-eBPF path that can be reached with patches of the same
   shape as the 20.0 series (stub, not reimplement). If per-UID stats, data saver or the firewall
   chains *require* BPF maps to exist, that is a no.
2. Every 20.0 device patch (`overlay/patches/device/nextbit/ether/`) and kernel patch applies with
   at most fuzz. These are version-agnostic; a real conflict means the base tree moved under us.
3. The 18.1-pinned CAF HALs (`hardware/qcom-caf/msm8994/{audio,display,media}`) still build against
   14's `hardware/interfaces`. If display (HWC) or audio need a new HAL major version, that is a
   port of the HAL, not of the device, and it is a no.

## Phase 1 — dry scoping, no build, no phone (one afternoon, one resync)

1. `./forge/bootstrap.sh` up to the patch step only (`repo init -b lineage-21.0`, sync, replay).
   Expect it to stop at `git am` failures. Record every failing patch in the table below.
2. Missing projects. Known already:
   - `frameworks/libs/net` is gone on 21 — moved to `packages/modules/Connectivity/staticlibs`.
     Both patches (pinned-map abort, `IFA_FLAGS`) retarget there. Drop it from `PATCHED_PROJECTS`.
   - `hardware/sony/timekeep` is not in 21's default manifest; the local manifest pins
     `lineage-21` (branch exists, checked).
   - The three `hardware/qcom-caf/msm8994/*` and `kernel/nextbit/msm8992` stay on their 18.1 pins.
3. Read, do not guess — the four files that decide criterion 1:
   - `system/netd/server/TrafficController.cpp` — is there still a `!bpf` construction path, or
     is `initMaps()` failure fatal?
   - `packages/modules/Connectivity/service/src/com/android/server/BpfNetMaps.java` — what does
     every public method do when the maps are null. On 20.0 three patches carried us: tolerate no
     eBPF, do not throw on ENOSYS, report empty stats instead of an error.
   - `packages/modules/Connectivity/netbpfload/NetBpfLoad.cpp` — what it does with a 3.10 kernel
     *after* the warning (map creation on a kernel with no `bpf(2)` — ENOSYS handling, exit code,
     and what `init` does with that exit; on 20.0 `bpfloader` failure rebooted the device).
   - `system/core/libprocessgroup/` + `frameworks/base/services/core/java/com/android/server/am/CachedAppOptimizer.java`
     — is the cgroup-v2 freezer a hard dependency or gated on `ro.cached_apps_freezer` /
     `/sys/fs/cgroup/uid_*/freezer` presence.
4. Option patches. Sixteen options carry `patches/lineage-20.0/` and only `dark-default`, `gapps` and
   `nav-icons` have `lineage-21.0/`. Each needs a `lineage-21.0/` directory in rom-forge (try the 20.0 patch, then
   the 22.2 one, then re-derive). That is forge work, done on `rom-forge/main`, not here.
5. Fill in the table, decide go/no-go, commit this file either way.

## Patch inventory and expected fate

| Project | Patches on 20.0 | Expected on 21 | Phase-1 result |
|---|---|---|---|
| `device/nextbit/ether` 0001–0017 | 17 | carry (`git am`, fuzz at most) | |
| `kernel/nextbit/msm8992` 0001–0005 | 5 | carry unchanged (same kernel pin) | |
| `device/lineage/sepolicy` (pre-UM exclusion) | 1 | re-port; 14 added neverallows | |
| `frameworks/base` hwui binder/RenderThread lock | 1 | **re-verify** — 14 reworked frame metrics; the bug may be gone or moved. Must be tested on hardware either way (this was the 4 s freeze) | |
| `frameworks/native` binder threadpool shrink | 1 | re-port | |
| `frameworks/libs/net` | 2 | retarget to `Connectivity/staticlibs` | 1.3: content unchanged, paths only (`staticlibs/native/bpf_headers/include/bpf/BpfMap.h`, `staticlibs/device/.../netlink/`) |
| `packages/modules/Connectivity` | 3 | **re-derive** (criterion 1) | 1.3: re-derive, larger — `BpfNetMaps` is pure Java and its ctor now throws; needs a `sBpfUnavailable` early-out in every public method (~80 lines), `NetworkStatsService.getIfaceStatsMap` null (3 lines), `BpfNetworkStats.cpp` `isValid()` early-outs (~25), `BpfHandler::init` return ok (~10); netbpfload lives here now (rc `reboot_on_failure` + `createSysFsBpfSubDir` fatal + self-test) |
| `system/netd` | 2 | **re-derive** (criterion 1) | 1.3: 0001 carries verbatim; 0002 one token (`CGROUPV2_CONTROLLER_NAME` → `CGROUPV2_HIERARCHY_NAME`) |
| `system/bpf` | 2 | re-derive; loader split into `bpfloader` + `netbpfload` | 1.3: 0001 (rc) moves to Connectivity; 0002 keeps the `break`, drops the self-test hunk (self-test moved to netbpfload) |
| `system/core` libprocessgroup cgroup-v1 | 3 | re-port; check freezer (phase 1.3) | 1.3: 0001/0003 carry verbatim (json identical); 0002 same guard, anchor moves to `createProcessGroupInternal`; freezer self-disables (`CachedAppOptimizer.isFreezerSupported` wants `cgroup.freeze`, v1 has `freezer.state`) — no frameworks/base patch |
| `packages/modules/adb` FunctionFS no-AIO | 1 | re-port; the daemon's USB code moved little in 14 | |
| `packages/modules/Bluetooth` LE vendor caps | 1 | re-port | |
| `packages/services/Telephony` USSD revert | 1 | re-port or drop (cellular is out of scope) | |
| `hardware/qcom-caf/msm8994/display` libbfqio | 1 | carry (same pin) | |
| `build/make` presigned APK, `build/soong` preprocessed | 2 | re-port, trivial | |
| `vendor/lineage` msm8992 restorations | 4 | re-port; check `QCOM_BOARD_PLATFORMS` and `B64_FAMILY` still exist in 14's `vendor/lineage` | |
| `vendor/qcom/opensource/power` | 1 | re-port | |

## Phase 1.3 result (read 2026-09-14, from the `lineage-21.0` files on GitHub, no sync)

Criterion 1: **go**, pending a build for completeness of the Java stub. Full line-referenced notes
and the shape of every re-derived patch: `scoping/criterion-1-bpf-cgroup.md`.

- netd no longer owns per-UID policy at all; `TrafficController.cpp` is gone. Our two patches
  still land (one identifier rename).
- `BpfNetMaps.java` is the whole per-UID firewall/stats layer and is pure Java on 21. Its ctor
  throws `IllegalStateException` when a map fails to open, and three system_server boot paths
  construct it — that is the one thing that would kill boot. Once it stops throwing, every public
  method NPEs on the null map, so the stub is "flag + early return everywhere", not the 20.0
  `maybeThrow` trick. Callers (ConnectivityService, NPMS) already tolerate exceptions.
- `netbpfload` (now in Connectivity's apex) exits 1 on 3.10 before loading anything because
  `/sys/fs/bpf` cannot be mkdir'd, and its rc has `reboot_on_failure`. Patch: early-out + publish
  `bpf.progs_loaded` (something must, `waitForProgsLoaded` spins on it).
- libprocessgroup still accepts a v1-only `cgroups.json`; freezer gates itself off.

## Phase 2 — first build to first boot (only after go)

Order matters; one variable per flash as always.

1. Build-breaks first, with `OPTIONS=""` (no options) so option patches cannot be the cause.
2. First flash: `clean` preset equivalent, wiped. Success = boot animation ends and the lock
   screen appears. Pull `/sys/fs/pstore` and `/data/tombstones` before anything else.
3. Then in this order, each its own build+flash: network (WiFi up, DHCP, DNS — the BPF question in
   practice), the HWUI freeze check (`touch-rate`, 10 min of launcher use), camera, audio,
   Bluetooth, LEDs.
4. Only then options, then `full`.

## Phase 3 — parity with 20.0

Everything under README "Status" on `lineage-20.0` at the same level, plus the thermal/turbo table
values unchanged (they are in the device patches; verify with `cat` on the booted phone, not by
reading `vendored/`). Cellular stays out of scope.

## Known differences to expect on 14, not bugs

- `netbpfload` logs `Android U requires kernel 4.14.` every boot. Expected.
- ART's userfaultfd GC is unavailable on 3.10; it falls back to concurrent-copying. Expected.
- Camera stays on `camera.provider@2.4-legacy`; lights on `light@2.0` HIDL. Both still build on 21.

## Bookkeeping

- Repo: `ether-lineage`, branch `lineage-21.0`, local dir `ether-21.0/`. `main` is the landing page
  (branch table only).
- Option patches for 21 live in `rom-forge/options/<opt>/patches/lineage-21.0/`; sync the forge
  into this branch after they land.
- README on this branch is a stub pointing at the 20.0 README until phase 2; write the full one then.
