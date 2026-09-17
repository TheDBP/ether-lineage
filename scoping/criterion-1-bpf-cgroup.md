# lineage-21.0 criterion-1 scoping — netd / Connectivity / bpf / cgroup (read 2026-09-14)

Line refs are into the `lineage-21.0` branch heads as of 2026-09-14 (LineageOS/android_system_netd, android_packages_modules_Connectivity, android_system_bpf, android_system_core, android_frameworks_base). Prefixes: `netd-`/`conn-`/`sbpf-`/`lpg-`/`fb-`/`sc-` = those repos in that order (`lpg` = system/core/libprocessgroup, `sc` = system/core rootdir).

## 1. system/netd

- `server/TrafficController.cpp` does not exist on 21 (nor on 20). Per-UID firewall/bandwidth/stats is entirely in Connectivity (`BpfNetMaps.java`); netd keeps only interface-level firewall (`netd-FirewallController.cpp:71-169`) and interface quota/alert (`netd-BandwidthController.cpp:313-720`).
- `netd-BandwidthController.cpp:205-256` `getBasicAccountingCommands()` byte-identical to 20.0 upstream: same four `-m bpf --object-pinned` rules at :218, :222, :241, :254; called from `enableBandwidthControl()` :288. Patch 0001 applies as-is.
- `netd-Controllers.cpp:314-317` `initIptablesRules(); Stopwatch s; enableBandwidthControl()` — same anchor. Patch 0001 Controllers hunk applies.
- `netd-main.cpp:140-149`: `CgroupGetControllerPath(CGROUPV2_HIERARCHY_NAME, &cg2_path)` → `exit(1)`, then `libnetd_updatable_init(cg2_path)` → `exit(1)`. Only delta vs 20.0: `CGROUPV2_CONTROLLER_NAME` → `CGROUPV2_HIERARCHY_NAME`. Patch 0002 needs one-token context fix.
- New on 21: `conn-NetdUpdatable.cpp:34-37` `libnetd_updatable_init` now `abort()`s when `BpfHandler::init` fails. Moot once BpfHandler::init returns ok.
- New on 21: `conn-BpfHandler.cpp:104-105` U+ requires `cg2_path == "/sys/fs/cgroup"`; with "" from patched netd it fails before touching BPF — that is the degrade path.

Verdict: shape unchanged. 0001 carries; 0002 re-derives with one identifier change.

## 2. packages/modules/Connectivity

### BpfNetMaps.java — pure Java now; `service/jni/com_android_server_BpfNetMaps.cpp` and `service/native/TrafficController.cpp` are deleted. Maps are static `IBpfMap` fields (:123-130) opened via `BpfMap` → `nativeBpfFdGet` → `bpfFdGet` (`conn-com_android_net_module_util_BpfMap.cpp:34-43`, throws `ErrnoException`).

- Constructor :367-372 → `ensureInitialized()` :306-310 → `initBpfMaps()` :247-299. Every open (`getConfigurationMap` :188-195 etc.) wraps `ErrnoException` in **`IllegalStateException`** — the constructor throws. 20.0 `native_init` only `ALOGE`d. Three constructors run in system_server boot — `ConnectivityService:2117`, `NetworkStatsFactory:158`, `NetworkStatsService:650` — any throw kills system_server.
- No no-BPF gate. Only gate is `SdkLevel.isAtLeastT()` (:98, :368, `throwIfPreT` :381-385); the pre-T netd path (:723-726, :761-764, :840-843) is dead on U.
- `maybeThrow` :375-379 has one caller (`swapActiveStatsMap` :826) — 20.0 patch 0002 covers nothing now.
- Per public method with null maps (once ctor is non-throwing):
  - `addNaughtyApp/removeNaughtyApp/addNiceApp/removeNiceApp/setUidRule/updateUidLockdownRule` → `addRule/removeRule` :388-445 → `synchronized (sUidOwnerMap)` NPE.
  - `setChildChain` :514-527, `swapActiveStatsMap` :802-827, `setDataSaverEnabled` :876-885 → NPE.
  - `replaceUidChain` :566-601, `addUidInterfaceRules` :722-747, `removeUidInterfaceRules` :760-773, `setNetPermForUids` :839-865, `setIngressDiscardRule` :895-909, `removeIngressDiscardRule` :918-925, `pullBpfMapInfoAtom` :949-960 → NPE (only Errno/SSE caught).
  - `isChainEnabled` :544, `getUidRule` :642 → static `BpfNetMapsReader.*(map,…)` → NPE.
  - `getUidsWithAllowRuleOnAllowListChain` :674, `…DenyList…` :695 → NPE.
- ConnectivityService wraps SSE → ISE (`conn-ConnectivityService.java:13877-13906`, :13940, :14005); NPMS catches ISE (`fb-NetworkPolicyManagerService.java:6502, 6541, 6565, 6593`). Exception-based degrade is tolerated; NPE is not. ConnectivityService ctor :2155 already catches SSE from the first `setChildChain`.
- `BpfNetMapsReader` (`conn-BpfNetMapsReader.java`, framework/) is a separate app-side singleton (:89-115), ctor throws ISE (:122-148). Reached only via `ConnectivityManager.isUidNetworkingBlocked` :6285-6295 (U+). `NetworkPolicyManager` still routes to NPMS (`fb-NetworkPolicyManager.java:692-694`) — not on boot path; grep frameworks/base for in-platform callers after sync.

### NetworkStatsService
- Five map opens return null + `Log.wtf` (:806-856), as 20.0. **`getIfaceStatsMap` :859-865 throws ISE** → ctor :637 fatal. 1-line patch.
- `setKernelCounterSet` :1839-1843 null-guarded; `deleteKernelTagData` :2586-2620 not (NPE on uid removal) — identical latent hazard on 20.0 (:2425-2454).
- `SkDestroyListener` :650-652 only dereferences `mCookieTagMap` on a SOCK_DESTROY netlink event (`conn-SkDestroyListener.java:72`) which 3.10 never emits.

### BpfNetworkStats.cpp — rewritten
- Maps are function-local `static BpfMap/BpfMapRO` (:43-50, :84, :195-197) whose ctors call `abortOnMismatch` → `abort()` on bad fd (`conn-BpfMap.h:62-63`; ctors :75-78, :236-239). No `isValid()` checks in file. 20.0 patch 0003 has no anchor; 20.0 libs/net 0001 (BpfMap.h no-abort) retargets to `staticlibs/native/bpf_headers/include/bpf/BpfMap.h` and must be followed by explicit `isValid()` early-outs.
- Consumers: `conn-nss-jni.cpp:79-104` non-zero → UNKNOWN; `conn-NetworkStatsFactory.java:87-104` non-zero → `IOException` — the 20.0 chain that broke WiFi provisioning, so parse entry points must return 0 with empty output.

### BpfHandler
- `init()` :157-166 `RETURN_IF_NOT_OK(initPrograms); RETURN_IF_NOT_OK(initMaps)` — same as 20.0.
- Upstream now guards `tagSocket` :193 and `untagSocket` :302 with `if (!mCookieTagMap.isValid()) return -EPERM;`. 20.0 `mMutex`/`mBpfEnabled` hunks unnecessary; only `init()` changes.
- `initPrograms` :73-105 adds `IsAtLeastV` 4.19 gate (not hit) and cg2 path check :104.

### RtNetlinkAddressMessage (:136-139)
- Same `if (nlAttr == null) return null;`; 20.0 libs/net 0002 retargets to `staticlibs/device/com/android/net/module/util/netlink/`, no content change.

Verdict: non-BPF path reachable, but no longer "12 lines in maybeThrow". Stub = static `sBpfUnavailable` flag + early return in every public method. Nothing in ConnectivityService/NPMS hard-requires the maps once BpfNetMaps stops throwing/NPE-ing.

## 3. netbpfload / bpfloader

- Only `netbpfload.rc` is installed (`conn-Android.bp:53`; `sbpf-Android.bp` has no `init_rc`). `conn-netbpfload.rc:20` `service bpfloader /system/bin/netbpfload`, :18 `exec_start bpfloader` from `on load_bpf_programs` (`sc-init.rc:555`), `oneshot`, **:84 `reboot_on_failure reboot,bpfloader-failed`**. 20.0 system/bpf 0001 retargets here.
- Flow on 3.10 (`packages/modules/Connectivity/netbpfload/NetBpfLoad.cpp`):
  1. :262-267 platform binary execs `/apex/com.android.tethering/bin/netbpfload` (apex built in-tree on Lineage, so patches reach it).
  2. :291-297 T/U kernel-version checks: `ALOGW` only. :299-301 V check not taken.
  3. :340-362 U sysctl writes: fatal only on ≥5.13 / ≥4.14 — non-fatal on 3.10.
  4. **:368-370 `createSysFsBpfSubDir()` now fatal** (`return 1`; 20.0 was `void`+ALOGW). `/sys/fs/bpf` never mounts on 3.10 → `mkdir` ENOENT → **exit 1** before any ELF load. :377 `loader` too.
  5. :380-389 load loop `sleep(20); return 2`.
  6. :392-399 map self-test `return 1` (moved here from system/bpf).
  7. :401-406 `execve(/system/bin/bpfloader)` — only platform loader sets `bpf.progs_loaded`.
  Unpatched exit on ether: 1 at step 4 → init `reboot,bpfloader-failed`. No ENOSYS-specific handling anywhere.
- Platform `bpfloader` (`sbpf-BpfLoader.cpp:190-220`): mkdir fatal :198-200, load loop `sleep(20); return 2` :203-212, **no self-test**, `SetProperty("bpf.progs_loaded")` :215-218. 20.0 patch 0002 self-test hunk has no anchor; `break` hunk applies.
- `waitForProgsLoaded` (`conn-WaitForProgsLoaded.h:32-34`) spins forever on the property; someone must publish it.

## 4. system/core libprocessgroup

- `lpg-cgroups.json:32-44`, `lpg-cgroups.recovery.json:1-8`: identical to 20.0 upstream. Patches 0001/0003 apply unchanged.
- Parser optional on both sections: `lpg-cgroup_map_write.cpp:204 isMember("Cgroups")`, :212 `isMember("Cgroups2")`. Version-aware branches `lpg-cgroup_map.cpp:94, :123`, `lpg-task_profiles.cpp:118, :130, :871`; no hard v2 assert. New: `lpg-cgroup_map.cpp:237-242` activation failure is a warning for `Optional` controllers.
- `lpg-task_profiles.json:76-79` `FreezerState` = `freezer`/`cgroup.freeze`; Frozen/Unfrozen :97-121 unchanged. Diff vs 20.0: :650 rename, :684-687 `Dex2OatBackground`.
- `lpg-processgroup.cpp:711-713` `createProcessGroup` → `CgroupGetControllerPath(CGROUPV2_HIERARCHY_NAME)` (return ignored, `cgroup` empty) → `createProcessGroupInternal` :644-646 → `ConvertUidToPath("")` → `MkdirAndChown` fails :662-664 → `sc-service.cpp:704-714` fatal to service start. Patch 0002 `if (cgroup.empty()) return 0;` lands at :646.
- New on 21: `CgroupsAvailable()` :62-65 = `access("/proc/cgroups")` (true on v1). `sendSignalToProcessGroup` :375-380 builds v2 path from empty root; fopen fails :410-417 → `kill(-pid)`, return false; `killProcessGroup` :539 returns -1, skips `cgroup.events` poll :542-551. Non-fatal but noisy on every kill. Optional hunk: empty v2 root → `kill(-pid)`, return success.

Verdict: v1-only JSON layout still permitted; all three patches carry (0002 anchor moves).

## 5. CachedAppOptimizer

- Gates as 20.0: `CACHED_APPS_FREEZER_ENABLED` :1137-1141 ("disabled" wins), DeviceConfig `use_freezer` :1143-1144, then **`isFreezerSupported()`** :1090-1130 reads `getFreezerCheckPath()` = `getAttributePathForTask("FreezerState")` (`fb-com_android_server_am_CachedAppOptimizer.cpp:562-571`) → `<freezer>/cgroup.freeze`; v1 freezer at `/dev/freezer` has `freezer.state`, not `cgroup.freeze` → `FileNotFoundException` :1112 → `mUseFreezer=false`. All freeze paths check `mUseFreezer` (:996, :1399, :1628, :2605). AMS :20745 only proxies.

Verdict: freezer self-disables. No patch.

## Criterion 1 verdict

**Go** — needs-build-to-know only for the completeness of the Java stub.

- netd: same shape — carry.
- Connectivity: non-BPF path reachable; per-UID stats / data saver / firewall chains become no-ops (same degradation as 20.0). Larger patch but still stub-not-reimplement.
- bpf loaders: both now hard-fail before the load loop; still a stub (early-out + publish property). rc patch moves to Connectivity.
- libprocessgroup + freezer: carry; freezer self-gates.

Needs-build-to-know: in-platform callers of `ConnectivityManager.isUidNetworkingBlocked`/`BpfNetMapsReader` (grep after sync); sepolicy for `netbpfload` setting `bpf.progs_loaded` if the early-out lives there.

## Expected shape of each re-derived patch

- **netd 0001**: carry verbatim (fuzz at most).
- **netd 0002** (main.cpp:141-144): same hunk, `CGROUPV2_CONTROLLER_NAME` → `CGROUPV2_HIERARCHY_NAME`.
- **Connectivity A — BpfHandler.cpp:162-163**: replace two `RETURN_IF_NOT_OK` with log + `return ok`. ~10 lines, no header change.
- **Connectivity B — BpfNetMaps.java**: `initBpfMaps()` catches ISE (or `get*Map()` return null on ENOSYS), sets `static boolean sBpfUnavailable`; `if (sBpfUnavailable) { Log.w; return <void|false|FIREWALL_RULE_ALLOW|empty set|PULL_SKIP>; }` at top of every public method in section 2 plus `isChainEnabled`/`getUidRule`/`dump`. ~60-80 lines. Optionally same in `BpfNetMapsReader` (~15 lines).
- **Connectivity C — NetworkStatsService.java:859-865**: `getIfaceStatsMap` → `Log.wtf; return null`; dump at :3003/:3065 already null-tolerant. 3 lines.
- **Connectivity D — staticlibs BpfMap.h:62-63**: `abortOnMismatch`: `if (!mMapFd.ok()) { ALOGW; return; }` (retarget of libs/net 0001).
- **Connectivity E — BpfNetworkStats.cpp**: `if (!map.isValid()) return 0;` in `bpfGetUidStats` :83-86, `bpfGetIfaceStats` :115-117, `bpfGetIfIndexStats` :130-132, `parseBpfNetworkStatsDetail` :194-198, `parseBpfNetworkStatsDev` :270-272, and skip map write in `ifindex2name` :53-60. ~25 lines.
- **Connectivity F — RtNetlinkAddressMessage.java:136-139**: libs/net 0002 verbatim, path change only.
- **Connectivity G — netbpfload.rc:84**: comment out `reboot_on_failure` (system/bpf 0001, path change).
- **Connectivity H — NetBpfLoad.cpp**: after :297 probe once (`!isAtLeastKernelVersion(4,9,0)` or `createMap()` ENOSYS) and either (i) `SetProperty("bpf.progs_loaded","1"); return 0;` without exec'ing bpfloader (~8 lines; verify sepolicy), or (ii) mkdir non-fatal :369/:377, `break` load loop :381-389, skip self-test :392-399, still exec (~20 lines).
- **system/bpf 0002 (BpfLoader.cpp)**: only with option (ii): mkdir non-fatal :199, `break` :210-211, property still set :215. Drop the 20.0 self-test hunk.
- **system/core 0001/0003**: carry verbatim.
- **system/core 0002** (processgroup.cpp:646): same guard, new anchor; optional extra hunk in `sendSignalToProcessGroup` :377-380.
- **frameworks/base CachedAppOptimizer**: nothing.
