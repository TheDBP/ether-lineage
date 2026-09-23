# VoLTE on ether — work branch `lineage-20.0-volte`

Goal: IMS registration (`dumpsys telephony.registry` → `mImsRegState=REGISTERED`) and a VoLTE call on
T-Mobile / Mint (310/260). Nothing here ships until a call completes both ways with audio.

## What exists

- Modem: the RIL carries the IMS transport — `libril-qc-qmi-1.so` exports
  `qcril_qmi_ims_socket_agent::{init_socket_listenfd,process_incoming_message,send_message}` over
  `ims_MsgType`/`ims_MsgId`/`ims_Error` (1204 IMS strings), and the baseband is `M8992FAAAANAAM`.
  **Unverified:** the specific `mcfg_sw/generic/na/tmo/commerci/mcfg_sw.mbn` carrier config. No modem
  image is in the stock zip (only `venus.mbn`), and `/firmware` is not readable without root, so that
  claim has no evidence behind it yet. It does not block step 4.
- Stock ether 7.1.1 (`Ether_Stock_ROM_N108.zip`) ships the complete QTI IMS userspace, which the
  TheMuppets ether list omits: `vendor/app/ims/ims.apk` (`org.codeaurora.ims`, dex stripped into
  `oat/arm64/ims.odex`), `vendor/app/imssettings/`, `bin/{imsqmidaemon,imsdatadaemon,ims_rtp_daemon,imscmservice}`,
  `vendor/lib/lib-ims*.so`, `libimscamera_jni`, `libimsmedia_jni`, `libqmi*`, `framework/ims-common.jar`
  (dex in `boot-ims-common.oat`), `framework/{qcrilhook,rcsimssettings}.jar`, `priv-app/qcrilmsgtunnel`,
  `etc/diag_ims.cfg`, `etc/permissions/qcrilhook.xml`.
- Framework: `values-mcc310-mnc260` + CarrierConfig overlay already flip every IMS switch
  (device patch 0004).

## What blocks

The QTI `ims.apk` (7.1 on ether, 8.1 on bullhead, same design) is the pre-P IMS style:
`android:process="com.android.phone"`, no intent-filter, registers itself with
`ServiceManager.addService("ims")` implementing `com.android.ims.internal.IImsService`. Android 9
deleted that binding path. `ImsServiceControllerCompat` on 13 binds only the 8.0 dynamic
`IImsMMTelFeature` API, which this APK does not implement. That class and `MmTelFeatureCompatAdapter`
live in **`frameworks/opt/telephony`** (`src/java/com/android/internal/telephony/ims/`), not in
`frameworks/opt/net/ims`; `ImsResolver` there still scans for compat ImsServices on 13, so the
binding path the bridge targets is alive. LineageOS bullhead commit `5cef16f`
("Disable pre-P IMS stack", body: "Does not work at all and kills our dialer", lineage-16.0) is the
same wall — and note it changed only `lineage-proprietary-blobs-vendor.txt`, one line: upstream did
not attempt a bridge, they stopped shipping the APK.

The APK's framework surface is small: `com.android.ims.{ImsCallProfile,ImsReasonInfo,ImsSsInfo,
ImsCallForwardInfo,ImsConferenceState,ImsStreamMediaProfile,ImsSuppServiceNotification,ImsConfigListener}`
and `com.android.ims.internal.{IImsService,IImsCallSession,IImsCallSessionListener,IImsUt,IImsUtListener,
IImsEcbm,IImsEcbmListener,IImsConfig,IImsMultiEndpoint,IImsRegistrationListener,IImsVideoCallProvider,
ImsVideoCallProvider}`. On 13 the parcelables live in `android.telephony.ims.*` and the `internal`
AIDLs carry 13 signatures, so the APK cannot load against the boot classpath as-is.

Modem transport is a unix socket to QCRIL (`ImsQmiIF` protobuf), served by `libril-qc-qmi-1.so`
with `imsqmidaemon` — all ether's own blobs.

## Inventory (2026-09-23)

Extracted from the stock zip and compared against what `vendor/nextbit/ether` already carries.
`proprietary-files-ims.txt` in this repo is the resulting list: **58 files, 35 MB**.

| | count | note |
|---|---|---|
| already present | 21 | the whole QMI/RIL transport: `libqmi*`, `libril-qc-qmi-1.so`, `libril-qcril-hook-oem`, `librilqmiservices` |
| missing — daemons | 4 | `imsqmidaemon`, `imsdatadaemon`, `ims_rtp_daemon`, `imscmservice` |
| missing — libs | 37 | 16 × 64-bit, 21 × 32-bit (`lib-ims*`, `libims*_jni`, `lib-rcsims*`, `libcneqmiutils`) |
| missing — apps | 6 | `ims.apk`+odex, `imssettings`+odex, `qcrilmsgtunnel`+odex |
| missing — framework | 9 | `ims-common.jar`, `qcrilhook.jar`, `rcsimssettings.jar`, `boot-ims-common.{oat,art}` ×2 arches, `qcrilhook.odex` ×2 arches |
| missing — etc | 2 | `diag_ims.cfg`, `permissions/qcrilhook.xml` |

The useful half of that: **the modem transport is already in the build**. `libril-qc-qmi-1.so` — the
RIL that serves the `ImsQmiIF` protobuf socket the daemons talk to — ships today. What is absent is
only the IMS userspace above it, which is what upstream deliberately dropped.

Nothing here is pinned: every file comes from the same stock image named in the header of
`proprietary-files.txt`.

## Carrier-side risk

Separate from anything in this repo: T-Mobile provisions VoLTE against a device allowlist keyed on
IMEI/TAC, and Mint is an MVNO on that network. A device that is not on the list can be refused IMS
registration no matter how correct the software is, so the whole scoreboard can pass and still end
at "the network says no".

What is known, 2026-09-23: **VoLTE and VoWiFi both work on bonito (Pixel 3a XL) on Mint, running our
own unofficial lineage-24.0 build.** That rules out one component of the risk -- the carrier is not
gating on stock firmware, a certified build, or an untampered bootloader. A custom ROM registers
fine.

It does not rule out the component that matters here: bonito is a Pixel and is on the allowlist by
IMEI. The Robin (Nextbit, 2016, never VoLTE-certified on T-Mobile) almost certainly is not, and
there is no cheap way to test that before IMS registration works -- which is the last milestone on
the scoreboard, not the first. Treat it as the reason the three-session budget exists.

## What bullhead supplies (re-fetched 2026-09-23)

Bullhead is a Nexus 5X: **same msm8992**, same QTI IMS generation, and LineageOS carried a working
IMS wiring for it at 16.0. `upstream-reference/device_lge_bullhead` (lineage-16.0, 12 MB clone) has
every piece step 4 needs.

**init** (`init.bullhead.rc:426`) — note it defines only TWO daemons, not the four in the stock zip:

```
service imsqmidaemon /system/bin/imsqmidaemon
    class main
    user system
    socket ims_qmid stream 0660 system radio
    group radio net_raw log diag

service imsdatadaemon /system/bin/imsdatadaemon
    class main
    user system
    socket ims_datad stream 0660 system radio
    group system wifi radio inet net_raw log diag net_admin
    disabled

on property:sys.ims.QMI_DAEMON_STATUS=1
    start imsdatadaemon
```

**sepolicy** — `sepolicy/ims.te` is a complete domain (`init_daemon_domain`, `net_raw`/`net_admin`,
`create_socket_perms`, `allowxperm ... msm_sock_ipc_ioctls`, `set_prop(ims, qcom_ims_prop)`,
`unix_socket_connect` to cnd and netd, `qmux_socket(ims)`), supported by:

| file | what it adds |
|---|---|
| `file.te` | `type ims_socket, file_type;` |
| `property.te` | `type qcom_ims_prop, property_type;` |
| `radio.te` | `allow radio ims_socket:sock_file write;` (and a commented-out `#HACK` connectto) |
| `property_contexts` | `sys.ims.` → `qcom_ims_prop` |
| `file_contexts` | both sockets → `ims_socket`, both daemons → `ims_exec` |

**Android.mk:49** — the bit that is easy to miss: the APK's JNI libraries are **symlinked** into
`vendor/app/ims/lib/arm64/`, because the app looks for them there rather than in the normal lib path.

```
IMS_LIBS := libimscamera_jni.so libimsmedia_jni.so
IMS_SYMLINKS := $(addprefix $(TARGET_OUT_VENDOR)/app/ims/lib/arm64/,$(notdir $(IMS_LIBS)))
```

### Porting caveats, 16.0 → 20.0

- `device_domain_deprecated` does not exist on 13. Drop it and add what the denials actually ask for.
- Bullhead runs the daemons from `/system/bin`; ours land in `vendor/bin`, so every `file_contexts`
  path and the service paths change.
- The `#HACK` comment on `radio → ims:unix_stream_socket connectto` is a hint that they hit
  something there; expect to need it and to have to justify it.
- 13's neverallows are stricter than 9's. Treat the policy as a starting point to be re-derived from
  denials, not as something to paste.

## Where these blobs can be got

Checked 2026-09-23 against the public repos, not assumed.

- **TheMuppets `proprietary_vendor_nextbit`** — the set our build already syncs — carries **zero**
  IMS files for ether. The 21 files we already have are the QMI/RIL transport, nothing above it.
- **TheMuppets `proprietary_vendor_lge` (bullhead, lineage-16.0)** publishes most of the stack for
  the same msm8992: 15 libraries (`lib-ims*`, `libims*_jni`, `lib-rcs*`) and three daemons
  (`imsqmidaemon`, `imsdatadaemon`, `ims_rtp_daemon`). `lineage-17.1` has none of it.
- **`vendor/app/ims` is absent from the bullhead set too.** They publish the libraries and the
  daemons and not the APK — the same file `5cef16f` removed, and the one thing the whole approach
  turns on.
- **Google's bullhead factory image** is a public download and does contain an `ims.apk`
  (`platformBuildVersionCode` 27, 8.1). That is a different device's build of the same QTI stack.

So: the stock ether zip is the only public source of **ether's own** `ims.apk`, `imscmservice`,
`imssettings`, `qcrilmsgtunnel` and the framework jars. Everything else in the list exists publicly
for a sibling device.

Mixing is not free. Bullhead's 16.0 blobs came off an 8.1 image and ether's off 7.1, and the pieces
that matter talk to `libril-qc-qmi-1.so`, which is ether's. Prefer ether's own files; reach for
bullhead's only for a specific file that will not work, and say so when you do.

## Does this carry forward?

Checked upstream 2026-09-23. The 8.0 compat binding path — the thing the bridge targets — is still
present on **lineage-21.0 (Android 14)** and **lineage-22.2 (Android 15)**:

| | 21.0 | 22.2 |
|---|---|---|
| `ImsServiceControllerCompat` | present | present |
| `MmTelFeatureCompatAdapter` | present | present |
| `android.telephony.ims.compat.ImsService` | present | present |

So a bridge written against 13 is not a one-release dead end; the surface it binds to survives at
least two releases past it. That does not promise the bridge itself ports cleanly — the `internal`
AIDL signatures move between releases and that is exactly what the bridge has to translate — but the
approach is not being deprecated out from under us.

Decision (2026-09-23): use **ether's own** stack from the stock zip throughout. The bullhead 8.1
`ims.apk` stays a fallback to fetch on demand — Google publishes the factory image — and is not kept
locally.

## Approach

1. Deodex `ims.odex` (baksmali `x`), rename `com.android.ims.*` → `org.codeaurora.ims.legacy.*` in
   smali, rebuild, sign with the platform key (`sharedUserId` phone process needs it).
2. `ims-legacy` Java library: the 7.1 parcelables + AIDLs under the renamed package, built from
   AOSP 7.1 `frameworks/base/telephony/java/com/android/ims/` (Apache 2). Boot classpath or
   `uses-library` injected into the rebuilt manifest.
3. Bridge (a new service; the compat adapters it hands off to are in `frameworks/opt/telephony`): `IImsService` → `IImsMMTelFeature` (near 1:1 method map,
   serviceId held by the bridge). Wrap each crossing interface (call session, listeners, UT, ECBM,
   config, registration, multi-endpoint, video provider) and copy parcelables field-wise.
   `MmTelFeatureCompatAdapter` + `ImsServiceControllerCompat` take it from there; the bridge
   declares `android.telephony.ims.compat.ImsService`.
4. Daemons + libs from the stock zip via a new `proprietary-files-ims.txt`; init from
   `device_lge_bullhead/init.bullhead.rc` (`imsqmidaemon`; `imsdatadaemon` on
   `sys.ims.QMI_DAEMON_STATUS=1`; sockets `ims_qmid`, `ims_datad` 0660 system radio);
   sepolicy from `device_lge_bullhead/sepolicy/{ims,qmux,rild,radio,file,property}.te`;
   `allow radio <ims service>:service_manager add`.
5. Expect bionic mismatches (same class as `libperipheral_client`): `-z global` shims per daemon.

## Step 4 status (2026-09-23)

Written, not yet built or booted.

| piece | where |
|---|---|
| blob list | `proprietary-files-ims.txt` — 43 active (step 4), 15 deferred to steps 1-3 |
| staging | `extract-ims-blobs.sh` → `vendor/extra/ims-blobs/` + a generated `ims-blobs.mk` |
| init (4 daemons), JNI symlinks, device.mk include | device patch `0018` |

Staging goes to `vendor/extra` rather than `vendor/nextbit/ether` on purpose: that repo is synced
from TheMuppets, which omits the IMS set deliberately, and blobs must never be committed anyway.
`apply-overlay` clears `vendor/extra` per build, so nothing leaks between presets.

Two things the script got wrong first, both worth keeping in mind for the next list:

- the destination decides the partition, not the source. `framework/`, `priv-app/` and `etc/` are
  system-side; forcing them to vendor produces an image where the IMS jars sit somewhere the boot
  classpath never looks, and nothing complains.
- the apks are odexed against the 7.1 boot image, so they are copied verbatim — never re-signed or
  re-compiled by the build.

Both open questions are answered. `device.mk` now `-include`s the staged fragment.

The daemon set came from **ether's own stock ramdisk**, unpacked from the boot.img in the stock zip,
not from bullhead. Bullhead starts two; ether's stock `init.target.rc` runs three stages plus a
fourth service:

```
imsqmidaemon -> sys.ims.QMI_DAEMON_STATUS=1 -> imsdatadaemon
             -> sys.ims.DATA_DAEMON_STATUS=1 -> ims_rtp_daemon   (socket ims_rtpd)
imscmservice: class main, no socket, always running
```

`imsqmidaemon` and `imsdatadaemon` are byte-identical between the two devices, which is why porting
the rest from bullhead was safe — but the second property handshake and the two extra services
would have been missed entirely by following bullhead alone. **Read the target's own stock init
before trusting a sibling's.**

### sepolicy is already done

Patch 0018 ships **no sepolicy at all**, and must not. `device/qcom/sepolicy-legacy`, which
`BoardConfig.mk` includes, already carries the whole IMS policy:

| | |
|---|---|
| `common/ims.te` | `type ims, domain`, `init_daemon_domain`, `net_domain`, `qmux_socket`, `set_prop(ims, qcom_ims_prop)` |
| `common/file.te:127` | `type ims_socket, file_type;` |
| `common/property.te:27` | `type qcom_ims_prop, property_type;` |
| `common/property_contexts:31` | `sys.ims.` → `qcom_ims_prop` |
| `common/file_contexts:197-199` | `imsqmidaemon`, `imsdatadaemon` → `ims_exec`; `ims_rtp_daemon` → **`hal_imsrtp_exec`** |
| `legacy-common/file_contexts:13` | `imscmservice` → `ims_exec` |
| `common/hal_imsrtp.te` | a separate domain for the RTP daemon |

Writing our own duplicated it and failed the build outright:

```
device/nextbit/ether/sepolicy/file.te:17: ERROR 'Duplicate declaration of type'
```

The hand-written version was also *wrong*: it labelled `ims_rtp_daemon` as `ims_exec`, where the
legacy policy gives it its own `hal_imsrtp` domain.

Two lessons. Search the **whole tree** whitespace-tolerantly before declaring a sepolicy type —
`device/nextbit/ether/sepolicy/file.te` already carries a comment warning that `type  proc_dirty_ratio`
with two spaces defeats a naive grep, and the same trap caught this. And a vendored qcom policy on a
QTI device has probably already solved anything QTI-generic; check there before writing it.

### What step 4 actually ships

**43 files, not 58.** The apps and framework jars are deferred to steps 1-3 and commented out at
the bottom of `proprietary-files-ims.txt`, for two independent reasons:

- `ims.apk` is **27 KB** against a **2.3 MB** `ims.odex` — its dex is stripped *out* into the odex.
  Importing the apk alone installs a shell with no code, and a 7.1 odex means nothing to 13's ART.
  Deodexing and rebuilding it is step 1; until then it must not be in the image.
- An APK cannot go in `PRODUCT_COPY_FILES` at all:
  `build/make/core/Makefile:72: error: Prebuilt apk found in PRODUCT_COPY_FILES`.
  Prebuilt apps need `android_app_import` modules, which is the right shape *after* step 1 produces
  an apk with dex in it.

So step 4 is daemons, libraries and configs — which is exactly what its milestone tests. The apps
contribute nothing to "do the daemons stay up and does QMI_DAEMON_STATUS flip".

## Step 4 results on hardware (2026-09-23)

Flashed and measured. **The hard parts work.**

| | |
|---|---|
| `imsqmidaemon` | **running**, stays up, no crash loop |
| `sys.ims.QMI_DAEMON_STATUS` | **1** — it reached the modem |
| `/dev/socket/ims_qmid` | created, `u:object_r:ims_socket:s0` |
| `imscmservice` | **running** |
| `imsdatadaemon` | starts and runs when started by hand |
| `ims_rtp_daemon` | was restart-looping — missing library, now fixed |

So 7.1-era blobs load and execute under Android 13's linker namespaces, and the modem handshake
completes. That was the risk rated highest going in.

### Three denial-derived rules (sepolicy/ims_ether.te)

```
allow ims self:capability net_raw;          imsdatadaemon
get_prop(ims, default_prop)                 both daemons
get_prop(vendor_init, qcom_ims_prop)        THE blocker
```

The last one is why the chain stalled: the handshake triggers live in a vendor init file, so
`vendor_init` evaluates them, and it was denied reading the very property they test. **Init registers
`on property:` actions at parse time**, so one denial at early boot drops the action for the lifetime
of init — `setenforce 0` afterwards does not bring it back, which is why this cannot be validated at
runtime and needs a rebuild.

Also note the qcom legacy policy is **not** a superset of bullhead's: it owns the types, labels and
contexts, but not `net_raw`, which bullhead granted and I removed as "already covered".

### Resolve dependencies, do not grep names

`ims_rtp_daemon` restart-looped with:

```
CANNOT LINK EXECUTABLE "/vendor/bin/ims_rtp_daemon": library "lib-rtpsl.so" not found
```

Five libraries were missing — `lib-rtpsl`, `lib-rtpcore`, `lib-rtpdaemoninterface`, `lib-rtpcommon`,
`lib-dplmedia` — because the inventory was built by matching names like `lib-ims*`, and none of
these look like IMS. `lib-dplmedia` is second-order and no pattern would have caught it. The list is
now 53 entries, derived from the daemons' actual `NEEDED` closure, and `verify-volte-plan.sh` checks
that closure so this class cannot recur.

## Build 7 on hardware (2026-09-23)

Cold boot, `/data` factory reset, SELinux **Enforcing**, no manual `start` commands.

| daemon | result |
|---|---|
| `imsqmidaemon` | running, pid stable |
| `imscmservice` | running, pid stable |
| `imsdatadaemon` | **running** — the `get_prop(vendor_init, qcom_ims_prop)` rule cleared the stall |
| `ims_rtp_daemon` | never started |

- `sys.ims.QMI_DAEMON_STATUS=1` fires: `init: processing action (sys.ims.QMI_DAEMON_STATUS=1) from
  (/vendor/etc/init/hw/init.target.rc:150)` -> starts `imsdatadaemon`. Stage one of the handshake works.
- **Zero** avc denials naming `u:r:ims:s0` or `hal_imsrtp`. The three denial-derived rules hold.
- The restart loop is gone: same pids across samples, elapsed climbing, all five previously-missing
  NEEDED libs (`lib-rtpsl`, `lib-rtpcore`, `lib-rtpdaemoninterface`, `lib-rtpcommon`, `lib-dplmedia`)
  present in `/vendor/lib64`.

Stage two does not fire: `imsdatadaemon` never sets `sys.ims.DATA_DAEMON_STATUS`, so `ims_rtp_daemon`
stays down. It is not crashing and not spinning -- `state=S`, `wchan=poll_schedule_timeout`, utime/stime
frozen at 0/2 across samples. It is idle, waiting.

It is waiting for a SIM. Confirmed with root, not inferred:

- The modem subsystem is **up**. `/dev/smdcntl0` exists -- per patch 0011 that node only appears once
  the subsystem boots -- `ether_modem_hold` (the 0011 service) holds `/dev/subsys_modem` open as
  designed, and there are **zero** `smdcntl0 ... timed out` / `unable to connect to server` errors,
  which is 0011's failure signature. rild runs and services requests.
- There is no card. `UiccProfile: setExternalState ... CARD_IO_ERROR`, `icc_operator_numeric=` empty,
  `subId not valid for Phone 0`, `eUICC not enabled`, and every RIL request returns
  `INVALID_MODEM_STATE`. `ModemActivityInfo` reports `mRat=UNKNOWN` with `mTxTimeMs=[0,0,0,0,0]` and
  sleep/idle counters frozen across minutes -- the modem has never transmitted.

**Superseded the same day, once a SIM went in.** The SIM was needed to test, but it was not the
cause of the stall.

With a Mint (T-Mobile MVNO, 310240) card in, a cold boot of this exact build registers in under ten
seconds -- `operator=Mint`, `LTE`, `registrationState=HOME`, `mDataRegState=0(IN_SERVICE)` -- and
LTE data passes, 0% loss at ~37 ms. LTE data is **not** broken by the IMS work.

SMS and visual voicemail were confirmed working on this build by hand, so the 53 IMS blobs and the
four new init services regress nothing the released branch already did.

**Voice calls do not work**, as expected. There is no IMS registration -- `ims_rtp_daemon` never
starts -- and Mint rides T-Mobile, which retired 3G in 2022 and 2G in 2024, so there is no CSFB
fallback either. The README's "voice needs 2G/3G" framing holds, and on this carrier that means
voice needs VoLTE. This is the thing the remaining work buys.

Service later came up fully -- `mVoiceRegState=0(IN_SERVICE)` as well as data -- whether because
the scan ended or because the network took its time authorising the device. Either way it is stable.

And `sys.ims.DATA_DAEMON_STATUS` is *still* unset, with **voice and data both IN_SERVICE**. `imsdatadaemon` sits in `poll_schedule_timeout`
with utime/stime frozen at 0/2 while a working data connection is up. So stage two is not waiting on
a data call, and not waiting on a SIM. It is blocked above the data layer -- the IMS framework
service (`ims.apk`, still dex-stripped, steps 1-3) or CNE. Chase those, not the radio.

One transient to recognise rather than re-debug: registration can read `NOT_REG_SEARCHING` with
`cellIdentity=null` and every RIL request returning `INVALID_MODEM_STATE` purely because a **manual
network scan is running** -- the modem deregisters while it scans. Count `is_nw_scan 1` in the radio
log before concluding anything: 29 during the stuck period, 0 on the clean boot. Stopping the IMS
daemons appeared to fix it and did not; they re-register fine with all three running.

Do not read `sys.ims.*` with `getprop` from a shell and believe the answer: those properties are
typed `qcom_ims_prop` and shell has no read access, so they come back **empty whether set or not**
(`avc: denied { read } scontext=u:r:shell:s0 tcontext=u:object_r:qcom_ims_prop:s0`, and `libc:
Access denied finding property`). Read the init action from logcat instead -- that is ground truth.

## Step 1 done: the odex is back to editable smali (2026-09-23)

`deodex-app.sh <stock.zip> <workdir> ims` reproduces all of it. baksmali/smali come from the Android
tree itself -- `prebuilts/extract-tools/common/smali/` -- so nothing has to be fetched.

The odex is an ART OAT, so its instructions are resolved against the boot image it was compiled
against; baksmali needs that same `system/framework/arm64` boot classpath to turn them back into
portable smali. Result: **226 smali files, 188 of them `org.codeaurora.ims`**, including
`org.codeaurora.ims.ImsService`.

Two checks that matter more than the file count, both in the script as hard failures:

- **leftover odex opcodes: 0.** baksmali leaves `invoke-*-quick` / `iget-quick` in place when it
  cannot resolve them. A partial deodex still assembles and still installs; it fails at runtime.
  Count the quick opcodes, do not assume.
- **round-trip reassembles**: smali -> dex succeeds on the untouched output, 188 classes. Prove the
  toolchain before editing anything, or a later failure has two possible causes instead of one.

### What step 2 has to build

The APK references **22 distinct `com.android.ims.*` outer types**. Checked against this tree:

| still present on 13 | `ImsException` (frameworks/base/telephony), `ImsManager` (frameworks/opt/net/ims) |
|---|---|
| **gone -- must be rebuilt** | the other **20**: `ImsCallProfile`, `ImsReasonInfo`, `ImsSsInfo`, `ImsCallForwardInfo`, `ImsConferenceState`, `ImsStreamMediaProfile`, `ImsSuppServiceNotification`, `ImsConfigListener`, and the twelve `internal/` AIDL interfaces (`IImsService`, `IImsCallSession`, `IImsCallSessionListener`, `IImsUt`, `IImsUtListener`, `IImsConfig`, `IImsEcbm`, `IImsEcbmListener`, `IImsMultiEndpoint`, `IImsRegistrationListener`, `IImsVideoCallProvider`, `ImsVideoCallProvider`) |

**That table was wrong and is corrected below** -- it searched only for `.java`, and most of these
types are `.aidl`. The real count on 13 is 14 present, 8 absent (the parcelables, which moved to
`android.telephony.ims.*`). It does not matter either way, because the 13 copies carry 13
signatures and the APK expects 7.1, so all 22 get rebuilt under `org.codeaurora.ims.legacy.*`
regardless.

### Step 2's inputs come from the device, not from AOSP

The plan said to build these from an AOSP 7.1 checkout. Better source: **the stock boot image we
already extract**. Those are the exact classes this APK was compiled against, so signatures match by
construction instead of by guessing a release tag, and nothing has to be fetched. `deodex-ims.sh`
now recovers them and hard-fails if any of the 22 is not found. All 22 are found.

They are split across two jars, and the second one has a trap in it:

- `ims-common.jar` (`boot-ims-common.oat`) -- 47 classes, the high-level helpers: `ImsManager`,
  `ImsCall`, `ImsUt`, `ImsConfig`, `ImsEcbm`.
- `framework.jar` (`boot-framework.oat`) -- the parcelables and the internal AIDL interfaces, in its
  **second dex**. `baksmali x <oat>` disassembles only the *first* dex of a multi-dex oat and says
  nothing about the rest, so asking `boot-framework.oat` for `com/android/ims` returns zero and reads
  exactly like proof the classes are not there. Run `baksmali list dex` first, then address the entry
  by appending the name it prints to the oat path as if the oat were a directory:
  `boot-framework.oat//system/framework/framework.jar:classes2.dex`. That yields 3077 classes, 119 of
  them `com/android/ims`.

The 7.1 definitions now in hand, for sizing step 3's bridge: `IImsService` 16 methods,
`IImsCallSession` 28, `IImsUt` 18, `IImsConfig` 9.

Those field counts are **not** a measure of work, and reading them as one overstates the bridge
badly. Almost all of them are constants. Instance fields, which is what conversion copies:

| | total members | instance fields |
|---|---|---|
| `ImsReasonInfo` | 91 | **3** |
| `ImsCallProfile` | 52 | **5** |
| `ImsStreamMediaProfile` | 38 | **4** |
| `ImsSsInfo` / `ImsCallForwardInfo` / `ImsSuppServiceNotification` / `ImsConferenceState` | 38 | **15** |

27 field copies across all seven.

The APK subclasses seven Stubs -- `IImsService`, `IImsCallSession`, `IImsCallSessionListener`,
`IImsConfig`, `IImsEcbm`, `IImsUt`, `IImsUtListener` -- so it *implements* these interfaces rather
than calling them. `IImsCallSession` has 295 bare type references and **zero** member references.
That is why the bridge wraps implementations rather than forwarding calls.

Weight is concentrated: `ImsReasonInfo` (345 refs), `ImsCallProfile` (297), `IImsCallSession` (295)
and `IImsUt` (159) are over half of all references. Get those four right first.

## Step 2 done: both apps rebuilt (2026-09-23)

`rebuild-app.sh <workdir> <ims|cne>`, taking the workdir `deodex-app.sh` produced. Both outputs are
**unsigned with META-INF stripped** -- ship via `android_app_import` with `certificate: "platform"`
and let the build sign. Do not presign: both declare a system `sharedUserId`.

| | classes | dex | sharedUserId |
|---|---|---|---|
| `ims-rebuilt.apk` | **325** (226 app + 99 legacy) | 787,464 B | `android.uid.phone` |
| `CNEService-rebuilt.apk` | **101** | 327,896 B | `android.uid.system` |

### The rename, and the one rule that makes it safe

`com.android.ims.*` -> `org.codeaurora.ims.legacy.*` across 1589 type references in the app and 6969
in the recovered framework classes, which are merged into the app's own dex -- so the apk carries
its legacy framework with it and needs no `uses-library`. The closure is 99 classes out of the 166
available; all 68 types it reaches outside `com/android/ims` resolve on 13.

Strings split two ways and the split is not cosmetic:

- **Rename the AIDL descriptors** (373 of them). Android 13 still ships
  `com/android/ims/internal/IImsService.aidl` with *different methods*. Leaving our 7.1 interfaces
  advertising the identical descriptor invites a binder call across incompatible signatures.
- **Leave the broadcast actions.** `com.android.ims.IMS_SERVICE_UP`, `IMS_SERVICE_DOWN`,
  `com.android.ims.volte.incoming_call`, `com.android.imscontection.DISCONNECTED` (sic) are a
  contract with whoever listens, not class names.

The rule separating them: rewrite a string only when it exactly names a class being renamed.

### CNE packaging, from its manifest

`com.quicinc.cne.CNEService`, `sharedUserId=android.uid.system`, `persistent=true`,
`process=".dataservices"`, and `<uses-library android:name="com.quicinc.cne"/>`. So it also needs
both jars and both permission XMLs, which declare the libraries:

    /system/etc/permissions/com.quicinc.cne.xml  -> com.quicinc.cne      -> /system/framework/com.quicinc.cne.jar
    /system/etc/permissions/cneapiclient.xml     -> com.quicinc.cneapiclient -> /system/framework/cneapiclient.jar

**99 of the rebuilt apk's 101 classes also exist in `com.quicinc.cne.jar`** -- it genuinely owns only
`CNEServiceApp` and its handler; the rest are the cne library and protobuf-micro. That duplication is
what stock shipped, since the odex we rebuilt from is stock's own. Do not "fix" it by trimming the
apk to two classes: matching stock is the conservative choice and stock demonstrably worked.

## Step 3: the bridge exists and compiles (2026-09-23)

Patch 0019 adds `device/nextbit/ether/ims-bridge`, an `android_app` that presents ims.apk's 7.1
`IImsService` to the modern stack through `android.telephony.ims.compat.ImsService`. It builds:
`ImsBridge.apk` installs to `system/priv-app`.

### The thing that makes it work at all

The legacy interfaces are hand-written AIDL under `org.codeaurora.ims.legacy`, matching the rename
already applied to the rebuilt apk. **Method order is load-bearing**: AIDL assigns transaction codes
by declaration order, and the far end is stock's compiled 2016 binary, which cannot be recompiled to
agree with us. The order is transcribed from that binary's `TRANSACTION_*` constants.

Verified after building, by disassembling our own apk: the generated stub numbers `open`=1 through
`getMultiEndpointInterface`=16, matching 7.1, and advertises the same renamed descriptor the apk
does. Do not take this on faith after editing the .aidl -- re-check it.

### What works and what does not

Bridged: `startSession`/`endSession`, `isConnected`, `isOpened`, `addRegistrationListener`,
`createCallProfile`, `turnOnIms`, `turnOffIms`, `setUiTTYMode`, plus the registration-listener
adapter -- ten of eleven callbacks map directly; `registrationFeatureCapabilityChanged` has no 13
equivalent and is dropped explicitly rather than approximated.

**All six sub-interface methods are now bridged too** (patch 0022), so nothing in the feature throws:

| wrapper | shape |
|---|---|
| `CallSessionWrapper` | 28 delegations onto `ImsCallSessionImplBase` |
| `CallSessionListenerAdapter` | 30 callbacks back; all thirty exist on 13 with matching shape |
| `UtWrapper` | 16 delegations onto `ImsUtImplBase` |
| `ConfigWrapper` | pure delegation -- 13's `IImsConfig` is method-for-method 7.1's |
| `EcbmWrapper` / `MultiEndpointWrapper` | 2 each |

Two design points worth keeping. The session argument in every call-session callback is resolved
back to the wrapper already built rather than a fresh one, so **object identity stays stable** --
the telephony stack matches callbacks to calls by it; only the genuinely new sessions from merge and
conference extension get their own wrapper. And `setListener` on `ImsEcbmImplBase` /
`ImsMultiEndpointImplBase` is **not** an overridable: it lives on an inner Stub because the base owns
the listener and exposes `enteredEcbm()` / `onImsExternalCallStateUpdate()` for the implementation to
call. Each of those wrappers therefore registers its own adapter with the legacy service and
forwards inward.

Three things deliberately do not forward, each logged rather than dropped silently:

- `getVideoCallProvider` returns null -- 7.1's provider is a different interface, and video is
  unreachable before VoLTE works at all.
- `registrationFeatureCapabilityChanged` has no 13 equivalent.
- `removeRegistrationListener` cannot be expressed: 7.1 offers only `setRegistrationListener`, which
  *replaces* the single listener rather than detaching one of several, so calling it would silently
  unhook whoever else registered.

### Two prerequisites that are not code -- landed in 0020

Neither is optional:

1. **`android.hardware.telephony.ims` is not declared on this device.** `PhoneGlobals` only builds
   an `ImsResolver` when `PackageManager.FEATURE_TELEPHONY_IMS` is present, so without it nothing
   binds the bridge no matter how correct it is -- and there is no log line saying so. The feature
   file exists as soong module `android.hardware.telephony.ims.prebuilt.xml`.
2. **`config_ims_mmtel_package`** (a `packages/services/Telephony` resource, empty by default) must
   name the bridge's package, or `ImsResolver` has no device default to bind.

Also note `MMTelFeature` declares **no** `RemoteException` on any method while every legacy call
throws it, so the conversion happens in the bridge; and its interface getters return
`ImsUtImplBase`/`ImsEcbmImplBase`/`ImsMultiEndpointImplBase`, not the AIDL interfaces -- reading the
signatures off a grep rather than the file gets this wrong.

## Shipping it (patch 0020, 2026-09-23)

Built and installed, all three signed or staged correctly:

    system/vendor/app/ims/ims.apk                          324,682 B, 325 classes
    system/priv-app/ImsBridge/ImsBridge.apk                  41,374 B
    system/vendor/etc/permissions/android.hardware.telephony.ims.prebuilt.xml

`ims.apk` is **generated, never committed** -- it is a proprietary blob derived from the user's own
stock zip. `extract-ims-blobs.sh` now runs `deodex-app.sh` and `rebuild-app.sh` after staging the 53
blobs, drops the result at `vendor/ims-blobs/ims/ims.apk`, and writes an `android_app_import`
alongside it. It cannot go in `PRODUCT_COPY_FILES`: AOSP rejects APKs there outright.

Both apks must carry the platform certificate, because both declare `android.uid.phone` and Android
refuses a shared uid across mismatched signatures. Verified: identical cert
`93:76:E9:...:75:27`, matching `platform.x509.pem`.

Do not compare signing keys by hashing `META-INF/CERT.RSA`. It is a PKCS#7 blob holding a *per-file
signature*, so it differs between two apks signed with the same key, and reads exactly like proof
they were signed with different ones. Extract the certificate:
`openssl pkcs7 -inform DER -print_certs | openssl x509 -noout -fingerprint -sha256`.

### A bug that invalidated an earlier result

`rebuild-app.sh` had `open(p,'w').write(rewrite(open(p).read()))`. Python evaluates `open(p,'w')`
first, truncating the file, so `rewrite()` received `''` and every rewritten smali was blanked. It
surfaced only when the script ran from a different working directory and smali reported
`required (...)+ loop did not match anything at input ''` across 226 files.

**So the "step 2 done" result reported before this fix cannot be trusted** -- the verified numbers
are the ones from after it. Read the file fully, then open for write; never both in one expression.

## Wi-Fi calling (VoWiFi)

Same IMS stack, different transport: signalling goes through the same `org.codeaurora.ims` service,
but the data path runs over an ePDG tunnel instead of LTE, and the QTI component that chooses
between them is **CNE** (`cnd`, the Connectivity Engine). So VoWiFi is not a second project — it is
VoLTE plus CNE.

What already points that way: `device/qcom/sepolicy-legacy/common/ims.te` carries
`unix_socket_connect(ims, cnd, cnd)` and `binder_call(ims, cnd)`, `imsdatadaemon` links
`libcneapiclient.so` and `libdsi_netctrl.so`, and device patch 0004 already sets
`carrier_wfc_ims_available_bool` for 310/260.

**`cnd` is deliberately disabled on ether** — our own device patch 0002 commented it out:

> The 19KB /vendor/bin/cnd shim needs a proprietary Qualcomm app we do not ship:
> Package not found: com.qualcomm.qti.cne / com.quicinc.cne.CNEService
> so it exits immediately and init respawns it forever — 60 times in one boot

That was correct then and stays correct until the app is shipped. The stock zip has the whole set:

| | |
|---|---|
| `priv-app/CNEService/CNEService.apk` | **4,627 bytes** + an `oat/` dir |
| `framework/com.quicinc.cne.jar`, `cneapiclient.jar` | |
| `etc/permissions/{cneapiclient,com.quicinc.cne}.xml`, `etc/cne/*.xml` | |
| `vendor/lib64/{libcne,libcneapiclient,libcneqmiutils}.so` | libs — bullhead publishes the first two |

**CNEService.apk is dex-stripped exactly like ims.apk** — 4.6 KB with the code in an odex. So VoWiFi
is gated behind the *same* deodex-and-rebuild work as VoLTE, not behind anything new. Solving steps
1-3 for `ims.apk` teaches the technique for `CNEService` too.

Order of work, therefore: VoLTE first. Re-enabling `cnd` before its app exists just restores the
60-respawns-per-boot that patch 0002 removed.

### CNE deodexed too (2026-09-23) -- and it needs no bridge

`deodex-app.sh <stock.zip> <workdir> cne` does for `CNEService.apk` what the `ims` target does for
`ims.apk`: **101 smali files, 94 under `com/quicinc/cne`**, zero leftover quick opcodes, zero
unresolved, round-trip reassembles at 101 classes.

The two jars need nothing at all -- `com.quicinc.cne.jar` (325 KB `classes.dex`) and
`cneapiclient.jar` (11.6 KB) still carry their own dex. Only the apk was stripped. Neither jar is on
the boot classpath, so they ship as ordinary `/system/framework` jars with their permission XMLs.

**CNEService references nothing Android removed.** Outside `android.*`/`java.*`/its own package it
touches exactly three internal types, all still present on 13:

| | used | status on 13 |
|---|---|---|
| `ITelephony` | `$Stub.asInterface` only | `.aidl` present; `asInterface` is AIDL-generated |
| `PhoneConstants` | `DataState.{CONNECTED,CONNECTING,DISCONNECTED,SUSPENDED}`, `values()`, `ordinal()`, `State.IDLE` | all present (13 adds `DISCONNECTING`, additive) |
| `AsyncChannel` | `<init>`, `connect`, `sendMessage` | all present |

So CNE is **deodex, rebuild, sign** -- no legacy library and no bridge, which is steps 2 and 3 gone.

### ...and even the rebuild was already done for us

`proprietary-files.txt` carries `-priv-app/CNEService/CNEService.apk`. The leading `-` is
extract-utils' **deodex** marker, which is what `prebuilts/extract-tools/common/smali/` exists to
serve. The build has therefore been shipping a fully deodexed CNEService with a 355 KB `classes.dex`
all along, installed and running as the `.dataservices` process. `rebuild-app.sh cne` reproduces it
but is not needed to ship it; the `cne` target earns its keep as the analysis that proved no bridge
is required. Check the blob list for a `-` prefix before deodexing anything by hand.

### CNE landed and verified on hardware (2026-09-23)

The only things actually missing were the two edits that had disabled it, so they were removed from
the patches that made them rather than reverted in a new one:

- **0002** no longer comments out the `cnd` service in `init.qcom.rc`.
- **0001** no longer strips `com.quicinc.cne.api` and `com.quicinc.cne.server` from `manifest.xml`.
  It still strips `com.qualcomm.qti.dpm.api`, which was its other, still-correct intent.

Verified by replaying all 18 patches onto the pristine base: clean apply, `cnd` live with no
commented leftovers, both CNE HALs present, no `dpm.api`, manifest still parses.

Then verified on the device by pushing the two files and rebooting, rather than spending a build:

    init.svc.cnd = running          pid stable, started ONCE (not 60 times)
    hwservicemanager rejections: 0  (was: "Cannot find entry com.quicinc.cne.server@2.0")
    avc denials naming cnd:      0
    QCNEJ/CndHalConnector: -> SND notifyMobileDataEnabledChanged(true)
                              -> SND notifyWwanSubtypeChanged(13)   # 13 = LTE
                              -> SND notifyScreenStateChanged(...)

CNEService and cnd are in live two-way conversation. **Patch 0002's premise -- that cnd exits
immediately and respawns 60 times a boot because its app is missing -- does not hold with the app
present.** It starts once and stays up.

That is CNE done. It does not by itself deliver Wi-Fi calling: CNE selects the transport, but the
IMS registration still has to exist, so VoWiFi remains behind the `ims.apk` bridge like VoLTE.
That inverts the earlier assumption that VoWiFi costs the same as VoLTE: the expensive half is
`ims.apk` alone. Once CNEService is rebuilt and shipped, patch 0002's reason for disabling `cnd`
("Package not found: com.qualcomm.qti.cne / com.quicinc.cne.CNEService") no longer holds and the
service and its HAL entries can come back.

## Scoreboard

daemons stay up → `sys.ims.QMI_DAEMON_STATUS=1` → `service list` shows `ims` → bridge bound
(`dumpsys telephony.registry` `mImsRegState`) → Enhanced 4G toggle appears → outgoing call
connects → audio both ways → incoming call → SMS over IMS → Wi-Fi calling.

Budget: three sessions. No registration by the end of the third → park it, document the state.

## Reference material

Outside every repo, never pushed. `upstream-reference/` sits beside the device repos; the stock zip is gitignored in the repo root:

**`upstream-reference/` was deleted in the 2026-09-23 disk prune, and `device_lge_bullhead` has been re-fetched since.** Everything in it is public and
re-fetchable (LineageOS `device_lge_bullhead`, TheMuppets `vendor_lge_bullhead`, Google factory
images); the stock ether zip, which is the primary source, is unaffected and still in the repo root.

| path | what |
|---|---|
| `Ether_Stock_ROM_N108.zip` | primary source: every IMS blob for this exact modem/RIL |
| `device_lge_bullhead/` | LineageOS lineage-16.0: `init.bullhead.rc`, `sepolicy/`, `Android.mk` IMS lib symlinks |
| `bullhead-factory/bullhead-opm7.181205.001/ext/{system,vendor}` | stock 8.1 for a second `ims.apk` (platformBuildVersionCode 27) if the 7.1 one deodexes badly |
| `vendor_lge_bullhead-16.0/bullhead/proprietary/` | TheMuppets 16.0 blob set; `ims.apk` deliberately excluded upstream |
| `vendor_lge_bullhead-17.1/` | TheMuppets 17.1 (trimmed set) |

## Verification

`./verify-volte-plan.sh` checks every factual claim above against the tree, the stock blobs and the
bullhead reference — 21 checks, PASS/FAIL each, non-zero exit on any failure.

Re-verified 2026-09-23 until clean twice in a row. The first pass found three defects, all now
fixed above:

- the modem `mcfg_sw` claim had no evidence behind it (no modem image in the stock zip,
  `/firmware` unreadable without root) and is now marked unverified;
- `ImsServiceControllerCompat` and `MmTelFeatureCompatAdapter` were placed in
  `frameworks/opt/net/ims`; they are in `frameworks/opt/telephony`;
- bullhead `5cef16f` changed only the blobs list — upstream never attempted a bridge, so "it does
  not work" is evidence about the APK, not about the approach.

One defect was in the checker rather than the plan, found by pointing it at missing inputs: C4d
("the service has no intent-filter") passed vacuously on an empty manifest dump. It now requires
the service element to exist first. **Negative-test this script before trusting a clean run.**

## Rules

- One change per flash. Keep `lineage-20.0` shippable; nothing merges until the scoreboard completes.
- Test with the SIM in; `logcat -b radio` and `dumpsys telephony.registry` after every flash.
- A root build is not needed; `adb root` on userdebug is enough.
- Stock blobs stay in `vendor/nextbit/ether`; never in a public repo.
