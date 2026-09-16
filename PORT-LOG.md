# ether → lineage-20.0 port log

Forward-port of the LineageOS 18.1 ether tree (last upstream commit 2021-08-30) onto a lineage-20.0
(Android 13) base. No upstream ether tree exists above 18.1, so every fix here is ours.

**State:** boots and works. WiFi, Bluetooth, camera, audio, adb, LTE data, SMS, visual voicemail.
No VoLTE. See *Still open*.

**Shape of the port:** platform at 20.0, everything Qualcomm-specific frozen at 18.1. The CAF HALs
are pinned at `lineage-18.1-caf-msm8994` — msm8992 has no CAF tree of its own and shares msm8994's,
and `lineage-18.1-caf-msm8994` is the newest branch those repos have.

**Ceiling:** 20.0 ships, 21 follows on branch `lineage-21.0`, and 21 is the end of the line: 22 needs
a 4.19+ kernel (`NetBpfLoad`).
msm8992 is the weakest forward-port target here — no CAF tree, 3.10 kernel with no eBPF, Android 11
blobs. Android 16 work goes to the V20 (msm8996) instead.

---

## The one root cause

Almost everything was a 2016 kernel meeting a 2022 userspace.

| assumption the code made | arrived in | what broke | fix |
|---|---|---|---|
| cgroup v2 | Linux 4.5 | nothing booted; `libprocessgroup` could not mount | v1-only `cgroups.json`, freezer moved to /dev/freezer |
| `bpf()` syscall | Linux 3.18 | `BpfMap` ctor `abort()`s → system_server and gpuservice crash-loop | ctor returns an invalid map, as its callers already assume |
| `bpf()` syscall | Linux 3.18 | netd crash-loop; bpfloader reboots the device | restore netd's A11 no-eBPF fallback; publish `bpf.progs_loaded` anyway |
| `IFA_FLAGS` netlink attr | Linux 3.14 | **WiFi** — every `RTM_NEWADDR` discarded | fall back to the 8 flag bits in `ifaddrmsg` |
| FunctionFS AIO | Linux 3.15 | USB adb impossible | restore a blocking path in adbd |
| RT bandwidth per cgroup | — | `SCHED_FIFO` unavailable system-wide | `RT_GROUP_SCHED=n` |
| driver-side PMF/802.11w | — | WPA 4-way handshake timed out | `pmf=0` in the supplicant overlay |

The second-order lesson: **when something legacy breaks on a newer branch, check whether the older
branch special-cased this platform.** `git diff` the same file across both trees. Two separate
failures below (`qcom_boards.mk`, the sepolicy m4 renames) were 20.0 dropping legacy platforms from a
filter, and neither failure pointed at the filter.

---

## Build-config fixes

| symptom | cause | fix |
|---|---|---|
| `sepolicy.mk: No such file` at board-config parse | 20.0's manifest carries neither `device/qcom/sepolicy-legacy` nor `hardware/sony/timekeep` | `timekeep` goes in `local_manifests`; `sepolicy-legacy` is vendored (upstream has no branch with the pre-rename layout). Branch naming is inconsistent: `timekeep` uses `lineage-20`, sepolicy uses `lineage-20.0-legacy-um`. Check with `git ls-remote --heads`. |
| same, after syncing | makefile renamed `sepolicy.mk` → `SEPolicy.mk` | patch the BoardConfig include |
| `source path "system/core/base/include" does not exist` | libbase split out after 18.1 → `system/libbase` | patch `include_dirs` in the ether init blueprint |
| `android.hidl.base@1.0 already defined by hardware/lineage/compat` | device-local stubs for dropped HIDL libs; 20.0 ships real compat shims | delete the device copies. Diff all modules `hardware/lineage/compat` defines against the device tree first — these two were the only overlaps |
| `camera.msm8992 missing libstagefrighthw`, `wcnss_service missing libqmi_cci` | 20.0's `hardware/qcom-caf/` starts at msm8953; apq8084/msm8960/msm8974/**msm8994** dropped | pin the three CAF repos at `lineage-18.1-caf-msm8994`. Hand-create the `Android.{mk,bp}` symlinks to `../common/os_pickup.*` — upstream makes those via manifest `<linkfile>` |
| still missing `libstagefrighthw`/`libqdMetaData`, 32-bit only | `BoardConfigQcom.mk` deleted `B_FAMILY`/`B64_FAMILY`/`BR_FAMILY`, so `QCOM_SOONG_NAMESPACE` became the non-existent `hardware/qcom-caf/msm8992` | restore the `B64_FAMILY → msm8994` mapping (patch to `vendor/lineage`) |
| ten non-existent `PRODUCT_PACKAGES` entries | 20.0 sets `PRODUCT_ENFORCE_PACKAGES_EXIST`; 19.1 did not | nine shared one cause (next row). `Snap`, `libcnefeatureconfig`, `libhidltransport.vendor`, `libhwbinder.vendor` were never built on 19.1 either — dead, removed. `Terminal` is a genuine loss: 20.0's manifest has no `packages/apps/Terminal` |
| components silently vanish (`libbt-vendor`, power HAL) | `qcom_boards.mk` lost every pre-UM family, so `is-vendor-board-platform,QCOM` is false | restore msm8992/msm8994 to `QCOM_BOARD_PLATFORMS`. **Nothing errors where the gating happens** — it surfaces as a package list at the end of the parse |
| `hardware/lineage/interfaces/cryptfshw` missing | HIDL interface dropped after 19.1 | remove it and its `<hal>` from manifest.xml. Safe: fstab mounts /data `encryptable=footer`, so FDE is opt-in |
| `audio.a2dp.default` rejected by `platform_availability_check.mk` | A13 moved Bluetooth to a mainline module; the HAL is APEX-only | drop it. A2DP is unaffected — the APEX provides it |
| `ERROR 'unknown type vendor_hal_perf_default_exec'` | 19.1 excluded pre-UM platforms from the sepolicy m4 renames and gave them a `legacy-vendor` dir; 20.0 deleted both. Result is a *half*-rename | restore 19.1's exclusion list. Do **not** restore `legacy-vendor` — its one rule references a `pps` type undeclared on 20.0 |
| 270 failed edges, ELF prebuilts in `PRODUCT_COPY_FILES` | became fatal | `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true`. Proper fix is `cc_prebuilt_library_shared` |

## Toolchain

| symptom | cause | fix |
|---|---|---|
| every `.bc` target dies | 20.0 builds `libclcore.bc` with a 2016 prebuilt clang linked against `libncurses.so.5` | add `libncurses5`/`libtinfo5` to the 22.04 image only — noble dropped both |
| Kbuild `Makefile:121` check dies | `RuleBuilder` rm -rf's the module's genDir before sbox and never recreates it | `mkdir -p` it; keep the path **absolute** (`KERNEL_BUILD_OUT_PREFIX`), since `make -C` chdirs |
| `Executable "ld" doesn't exist` building `fixdep` | `/usr/bin/ld` is not on the sbox PATH. 20.0 sets `-fuse-ld=lld` only via `HOSTLDFLAGS`, which Kbuild applies only to multi-object host targets; `host-csingle` uses `$(hostc_flags)` alone | set it in `HOSTCFLAGS` too |
| `ld.lld: duplicate symbol: yylloc` in `scripts/dtc` | clang 11+ defaults to `-fno-common`; `BoardConfigKernel.mk` passes `HOSTCFLAGS` on the make **command line**, overriding the kernel Makefile | `TARGET_KERNEL_ADDITIONAL_FLAGS := HOSTCFLAGS="-fuse-ld=lld -fcommon"` |
| `devicetable-offsets.c` fails on every `DEVID()` | 3.10 predates clang; its integrated assembler rejects the `\n->` marker in `kbuild.h` | `TARGET_KERNEL_CLANG_COMPILE := false`. Check the GCC 4.9 prebuilts still exist on the target branch |

## Device code

| symptom | cause | fix |
|---|---|---|
| `redefinition of '__kernel_sockaddr_storage'` | the 3.10 uapi header aliases `sockaddr_storage` because bionic had none; A13's bionic declares it | drop the alias, as upstream Linux later did |
| HAL1 camera sources fail on `CAMERA_CMD_LONGSHOT_ON`, missing `camera_face` members | AOSP 12 stripped the legacy vendor surface from `system/camera.h` | **`TARGET_SUPPORT_HAL1 := false`** and wrap the HAL1 source set in it. Android 12+ uses HAL3 regardless. Do *not* shadow `system/camera.h` — that was the earlier workaround and is unnecessary |
| still photos transposed and banded | `needJpegRotation()` returned true unconditionally; the hardware JPEG encoder cannot rotate, so it was disqualified and the software fallback mishandled it. Preview was always correct | gate on the capability bit. `CAM_QCOM_FEATURE_PP_SUPERSET_HAL3` already includes rotation and the CPP acts on it |
| Bluetooth aborts in `HciLayer` | WCNSS echoes vendor opcodes without the OGF; `HciLayer` matches strictly | gate LE vendor capabilities |
| F-Droid missing at runtime | — | `LOCAL_OPTIONAL_USES_LIBRARIES := androidx.window.extensions androidx.window.sidecar` |

## Boot

| symptom | cause | fix |
|---|---|---|
| no /data, /cache or /misc; init cannot write its own reboot reason | A13 removed FDE and libfs_mgr **rejects** `encryptable` rather than ignoring it — one bad flag fails the whole fstab | drop the flag. /data is unencrypted; the FBE replacement needs ext4 crypto this kernel lacks |
| blkio and memory cgroups cannot mount | `CONFIG_MEMCG` and `CONFIG_BLK_CGROUP` were never enabled | enable them. Both predate 3.10 by years |
| `Failed to mount cgroup v2` | cgroup v2 is Linux 4.5; this kernel has only the `CGRP_ROOT_SANE_BEHAVIOR` precursor | v1-only platform `cgroups.json`. **Not doable from `/vendor/etc/cgroups.json`** — that file is merged into the platform descriptors, so it can add entries but cannot remove the v2 root |
| `MkdirAndChown /uid_0: Read-only file system`, service start fails | with no v2 root the hierarchy path is empty, `ConvertUidToPath("")` yields `/uid_0`, and `createProcessGroup` returning an error is itself fatal | return success from `createProcessGroupInternal` when no hierarchy is configured. "Nothing aborts" is not "nothing fails" |
| device reboots forever at ~37 s, looks like a splash hang | `bpfloader.rc` has `reboot_on_failure reboot,bpfloader-failed`, and this kernel has no eBPF at all | bpfloader must publish `bpf.progs_loaded` even with no eBPF, or netd waits on it forever and INetd never registers |
| system_server aborts 15×/boot, gpuservice 32× | `BpfMap`'s pinned-path ctor calls `abort()` when `mapRetrieve()` fails | return an invalid map. Both callers already test `isValid()`; the `abort()` made their error handling unreachable. Only the pinned-path ctor changed — `createMap()` still aborts |

## Runtime

| symptom | cause | fix |
|---|---|---|
| WiFi never reaches CONNECTED; `unparsable netlink msg` constant | `RtNetlinkAddressMessage.parse()` returns null when `IFA_FLAGS` is absent. IpClient never learns the interface has an address, so provisioning never completes, `createNativeNetwork()` never fires, netd logs `no such netId` | fall back to the 8 flag bits already read from `ifaddrmsg` |
| 4-way handshake times out; "pre-shared key may be incorrect" | that is wpa_supplicant's generic **timeout** message, not a key mismatch. The supplicant escalated to *require* MFP, which the driver cannot do | `pmf=0` in `wpa_supplicant_overlay.conf`. Verify via `/system/vendor/etc/wifi/...` — the overlay is passed as `confanother`, so the `/data` copy still reads `pmf=1` |
| `cnd` restarts 60× | `/vendor/bin/cnd` is a shim needing a proprietary app this ROM does not ship | disable it, with five HALs declared with no implementation |
| LiveDisplay restarts | sepolicy: the HAL cannot reach the post-processing daemon | grant it |
| modem never loads | nothing called `subsystem_get("modem")` once the peripheral-manager path was gone — `ether_modem_hold` holds `/dev/subsys_modem` open |
| UI freezes for exactly 4 s, then every queued touch lands at once (launcher, SystemUI) | HWUI holds `mFrameMetricsReporterMutex` across all of `draw()` (A13). This Adreno has no `EGL_EXT_buffer_age`, so the buffer is dequeued *inside* draw, under the lock, waiting for SurfaceFlinger to release one. SF's oneway `onTransactionCompleted` then blocks its binder thread on that lock in `onSurfaceStatsAvailable`; the thread never sends `BC_FREE_BUFFER`, so the binder driver parks every later oneway to the process — including the release RenderThread is waiting for. Only the 4000 ms dequeue timeout breaks it. Not a scheduler, cpuidle, thermal or memory problem; 19.1 predates the lock | `onSurfaceStatsAvailable` posts its work to the RenderThread instead of waiting (`overlay/patches/frameworks/base/0001-hwui-*`). Diagnosed from atrace with `binder_driver` + `raw_syscalls` filtered to the launcher tids |
| rear LEDs never light; `com.nextbit.robinled` NPE ×3 at boot in `onListenerConnected` | `getSystemService(PowerManager.class)` is null: the fetcher needs `thermalservice` too, and `robinled_app` could not `find` it (avc denied) | `allow robinled_app app_api_service:service_manager find` (the 0006 patch) |
| `WCNSS_FILTER: wcnss_acquire_wakelock write to wakelock file failed -1 - Operation not permitted`, once a second | `/sys/power/wake_lock` needs `CAP_BLOCK_SUSPEND`; sepolicy grants it (`wakelock_use`) but the rc never did | `capabilities BLOCK_SUSPEND` on `start_hci_filter` (0015) |
| `mm-qcamera-daemon` aborts on every front/back switch: `FORTIFY: pthread_mutex_destroy called on a destroyed mutex` (8 tombstones a boot) | the ISP blob destroys a mutex twice; pre-P bionic returned an error, A13 aborts | shim scoped to the daemon (`TARGET_LD_SHIM_LIBS`, `-z global`) makes `pthread_mutex_destroy` a no-op; safe, the struct is caller-owned (0013). Switch is immediate |
| boot animation never ends, no crash, no reboot; composer HAL spinning property reads | gatekeeper denied a `system_prop` read, never registers `IGatekeeper/default`, `system_server` waits forever | sepolicy: let gatekeeper and the composer HAL read what they poll (0017) |
| `adb root` → "disabled by system setting" on a wiped /data | the `/data/adbroot/enabled` seed lived in a vendor rc → `vendor_init`, denied on `adbroot_data_file` | dropped with the rest of the bench-debug scaffolding once USB adb worked; the Developer-options toggle is enough |

---

## Do not repeat

- **Do not import `sepolicy-legacy-um/legacy/vendor/{common,ssg,test}` wholesale.** It compiles
  further, then dies on AOSP neverallows: it grants `hal_bootctl` the bare `gpt_block_device` /
  `xbl_block_device` / `root_block_device` types. Supported SoCs escape via `BOARD_SEPOLICY_M4DEFS`
  renaming them to `vendor_*`, and that renaming is explicitly skipped for msm8992/msm8994.
- **Do not discover missing sepolicy types from build output.** `checkpolicy` reports one unknown
  type per run. Use `forge/tools/find-orphaned-sepolicy-types.sh`.
- **Do not diagnose by amputation.** Disabling WiFi to isolate a crash moved it and lowered the boot
  phase; the crash was `BpfMap` landing on whichever thread asked for interface stats first.
- **Do not treat a stack trace in logcat as a crash.** `No service published for: wifi` appears with
  a full trace through `getServiceOrThrow` but is caught and logged by
  `CachedServiceFetcher.onServiceNotFound`.
- **Do not chase `zygote received signal 9`.** `SigChldHandler` has zygote SIGKILL itself when
  system_server dies.
- **Do not shadow `system/camera.h`.** Set `TARGET_SUPPORT_HAL1 := false` instead.

## Method

- **Read `/data/tombstones` before any pstore archaeology.** It survives reboots, does not wrap, and
  names the faulting library and function. The pmsg ring is 512 K and wraps within a few loop cycles.
- **An exception census only finds failures that throw.** When the symptom is "nothing happened",
  grep for the state transition that never occurs, and never filter a line containing `unparsable`,
  `invalid`, `unknown` or `ignoring` because it lacks a stack trace.
- **Pull pstore before booting to recovery** — booting TWRP to investigate overwrites it.
  `fastboot boot <twrp.img>` reaches recovery without flashing and preserves it.
- Build with `KEEP_GOING=true` (`mka -k`) and collapse the log with `forge/tools/triage-build-log.sh`.
  Env that `_build_rom.sh` reads must be plumbed in **two** places; `bootstrap.sh` hands the container
  an explicit env list.
- Run the assessment tools before writing anything: `check-platform-support.sh`,
  `check-hal-readiness.sh`, `check-image-labels.sh`, `find-orphaned-sepolicy-types.sh`,
  `find-removed-platform-symbols.sh`.

---

## sepolicy: what this device needs

Restored from the 18.1 `device/qcom/sepolicy-legacy` tree into `device/nextbit/ether/sepolicy/`,
**each with its `file_contexts` / `genfs_contexts` / `property_contexts` / `vndservice_contexts`
label** — a type without its label parses fine, labels nothing, and leaves the rules inert.

| group | types |
|---|---|
| needed by `qcom/dynamic` | `adsprpcd_file`, `bt_firmware_file`, `firmware_file`, `sysfs_graphics`, `qdisplay_service` |
| `BOARD_SEPOLICY_M4DEFS` gap | `persist_block_device`, `display_vendor_data_file`, `sysfs_battery_supply`, `sysfs_usb` |
| ether's own | `debugfs_rmt`, `time_data_file`, `pps_socket`, `mpctl_data_file`, `mpctl_socket`, `thermal_socket` |
| domains (need `_exec` too) | `perfd`, `rfs_access`, `sensors`, `mm-pp-daemon`, `mm-qcamerad`, `thermal-engine`, `hal_perf_default` |
| properties | `freq_prop`, `vendor_mpctl_prop`, `vendor_display_prop` |

Rules that cost a build each when missed:

- **A restored domain needs `init_daemon_domain()`**, not just `type x, domain;`. Without it the
  daemon keeps running as `init`, is denied everything, and takes the boot down if it is early-boot
  critical. Port the whole 18.1 policy file and append the device's rules — do not add just the
  missing `type` line.
- **Every property type needs vendor ownership.** A13 enables `enforce_sysprop_owner`, so a bare
  `type x, property_type;` parses but fails the combined sepolicy build. Use the qcom macros:
  `vendor_internal_prop()`, `vendor_restricted_prop()`.
- **Full policy files pull in more types** — 34 further referenced ones here. Declare them from their
  18.1 definitions and deliberately leave them **unlabelled**: an unlabelled type matches nothing, so
  the rules are inert while the policy stays diffable against 18.1.
- **Full files also use qcom `te_macros` that no longer exist.** `hal_server_domain_bypass()`,
  `qmux_socket()`, `diag_use()` report as a bare `syntax error` naming the macro. Expand inline,
  dropping parts whose attributes are unavailable.
- **Image labelling fails at ~99%.** `e2fsdroid` will not build `system.img` unless every path in the
  image has a label, and reports one path per run during `add_img_to_target_files`. ether needs
  `firmware_file` (`/firmware`, `/vendor/firmware`) and `persist_file` (`/persist`); both mount points
  are empty, so only the top-level catch-all is required. A label must match the type's attributes —
  `/system/etc/firmware` cannot use `firmware_file`, which carries `vendor_file_type` while
  `sepolicy_tests` requires `system_file_type` on `/system/`. And do not re-label what the shared
  policy already labels; diff against **all** compiled `file_contexts`.

---

## Still open

| item | detail |
|---|---|
| **Flashlight** | torch toggle has no effect; not diagnosed. |
| **`CNEService` crashes on every WiFi/mobile transition** | A7 blob calling `INetworkPolicyManager.getNetworkQuotaInfo`, removed in 12. Self-restarts, nothing depends on it. Fix: drop the APK from `proprietary-files.txt`, keep `cnd`. |
| **LiveDisplay monochrome** | toggle has no visible effect; colour calibration works. |
| **No VoLTE / Wi-Fi calling** | LTE data and SMS work; voice falls back to 2G/3G, so on T-Mobile/Mint (no legacy network) calls fail. The stock N108 zip ships the QTI IMS stack (`org.codeaurora.ims`, `imsqmidaemon`, `lib-ims*`), but it is a pre-P `ServiceManager("ims")` service that Android 9+ cannot bind. Plan and inventory in `VOLTE.md` on branch `lineage-20.0-volte`. |
| **QMI blobs are not modules** | `libqmi_cci`, `libqmi_common_so`, `libmdmdetect` exist in `vendor/nextbit/ether/proprietary/` but are declared `PRODUCT_COPY_FILES`, so `LOCAL_SHARED_LIBRARIES` cannot resolve them. Worked around with `TARGET_PROVIDES_WCNSS_QMI := true`, which selects the OSS dlopen path 19.1 actually compiled. |

---

## Reference

- **Flashing.** ether is A-only with a dedicated 40 MiB recovery partition
  (`BOARD_RECOVERYIMAGE_PARTITION_SIZE := 41943040`). Recovery does **not** ride inside the ROM zip
  and must be flashed separately. `BOARD_USES_RECOVERY_AS_BOOT` is not set, so a stale recovery does
  not break normal boot — that instinct comes from A/B devices, where the recovery ramdisk *is* the
  boot ramdisk.
- **A third-party 19.1 build** (`lineage-19.1-20240707-UNOFFICIAL-ether.zip`) is ground truth for
  *device* content — blobs, labels, prop set. It is **not** ground truth for *platform* enforcement:
  it predates `enforce_sysprop_owner` and declares property types as bare `property_type`.
- **The TipzTeam 19.1 device tree and vendor** were recovered from Software Heritage; their kernel is
  gone for good (the GitLab group is deleted; two crawl attempts returned `not_found`). Their tree is
  generally ahead of ours — `Android.bp`, `util/QCameraFlash.cpp`, a reworked `libshims/powermanager`.
  Diff it before writing anything new.
  Unresolved contradiction: their `bpfloader.rc` keeps `reboot_on_failure`, their `init.rc` triggers
  `load_bpf_programs` unconditionally, and their kernel config has no BPF options — on that evidence
  their build should bootloop as ours did, and reportedly does not.
- **CAF source needed essentially no changes to reach A13.** The msm8996 18.1→20.0 diff is the recipe
  (media: 1 commit, zero functional; display: 5 commits, all in `gpu_tonemapper`/`gralloc`/`hwc`;
  audio: 2 commits). The ether builds none of the changed components — its HWC comes from prebuilt
  blobs.
