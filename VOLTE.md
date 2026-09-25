> **SUPERSEDED — historical.** This was the plan and inventory written before the work was done, and
> its "Unverified" notes have since been answered, several of them differently than guessed here. The
> account of what is actually true is `VOLTE-BRINGUP.md`: VoLTE works, Wi-Fi calling does not and is
> not achievable on this hardware, and the reasons are measured rather than predicted. Kept only
> because the inventory of what the stock zip ships is still useful.

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

## First flash of the bridge (build 8, 2026-09-23) -- two bugs, both mine

The image built clean and flashed, and `org.codeaurora.ims` **installed** -- the deodexed, renamed
apk is accepted by the platform, which is the first proof the whole rename approach works. Then:

### system_server crash loop

    java.lang.IllegalStateException: Signature|privileged permissions not in
    privapp-permissions allowlist: {org.lineageos.ims.bridge
      (android.permission.READ_PRIVILEGED_PHONE_STATE, MODIFY_PHONE_STATE)}
      at PermissionManagerServiceImpl.onSystemReady

A **priv-app** that requests a `signature|privileged` permission without a matching
privapp-permissions allowlist entry makes PackageManagerService throw at `systemReady`. That kills
`system_server` before boot completes, on every boot. The device looks like it is booting slowly; it
is not. `sys.boot_completed` reaching 1 and then going back to empty, with zygote and system_server
on high pids, is the tell.

Both permissions were unnecessary: the bridge shares `android.uid.phone`, so it already runs with
the phone process's granted permissions. Removed rather than allowlisted. If a future wrapper needs
one, add it to the manifest **and** an allowlist together.

Recovery without reflashing: `adb root && adb remount && rm -rf /system/priv-app/ImsBridge`, reboot.

### The build tree and the patches had silently diverged

The CNE re-enable (edits to patches 0001 and 0002) was verified by replaying the series onto a
pristine base in a scratch directory -- and that check passed. But `_build_rom.sh` does **not** run
`apply-overlay`; it builds whatever is in `device/nextbit/ether`, which still held the *old* commits.
So build 8 shipped with no CNE HALs in `manifest.xml` and `cnd` still commented out, while the
patches on disk were correct.

**Editing a patch file does not change the build.** After editing any patch, reset the project to
`BASE_REF` and re-run `apply-overlay`, then check the tree itself:

    git -C device/nextbit/ether reset --hard <base>
    ./forge/docker/aosp.sh bash -lc 'bash /repo/forge/tools/apply-overlay.sh /aosp'
    grep -c quicinc.cne device/nextbit/ether/manifest.xml     # expect 2
    grep -c '^service cnd' device/nextbit/ether/rootdir/init.qcom.rc

A plain re-run of apply-overlay is not enough on its own: it skips patches whose subjects already
appear in `BASE_REF..HEAD`, so an edited patch with an unchanged subject is skipped. The reset is
the part that matters.

## Build 10 on hardware: the IMS stack RUNS, and rild segfaults (2026-09-23)

Everything up to the IMS stack itself now works. Boots in 41 s, Enforcing, `system_server` stable:

    android.hardware.telephony.ims           declared
    org.codeaurora.ims                       installed AND RUNNING
    org.lineageos.ims.bridge                 installed and running
    com.quicinc.cne.CNEService               installed
    init.svc.cnd                             running
    ImsResolver: device MMTEL package: org.lineageos.ims.bridge
    ImsResolver: service name: ComponentInfo{org.lineageos.ims.bridge/...ImsBridgeService}

So the platform discovers and selects the bridge, and the 2016 IMS service executes. Two fixes were
needed to get the apk that far, both now in `rebuild-app.sh` as asserted transformations:

1. **Hidden-API `System.arraycopy`.** libcore's type-specific overloads (`arraycopy([BI[BII)V`) are
   `@hide`/`@UnsupportedAppUsage`, so the 2016 call raised
   `IllegalAccessError: Method 'void java.lang.System.arraycopy(byte[], ...)' is inaccessible`
   inside `ImsService.onCreate`, crash-looping `com.android.phone`. Four calls in `ImsSenderRxr`.
   Redirected to the public generic `arraycopy(Object,int,Object,int,int)`, which accepts arrays --
   semantically identical, hidden-API enforcement left on.
2. **Video telephony cannot dlopen.** `ImsService.onCreate` calls `ImsVideoGlobals.init()`, whose
   static init loads the VT natives, linked against a vanished libgui symbol
   `android::Surface::Surface(sp<IGraphicBufferProducer> const&, bool)`. The call returns void and
   its result is unused, so it is removed. The bridge already reports no video support.

### The remaining blocker: nanopb ABI split across two libraries

`rild` now SIGSEGVs every ~5 s -- 27 restarts in 145 s. Not the modem (no SSR, `smdcntl0` present,
`modem_hold` holding) and not sepolicy (the 108 `rild`/`default_prop` denials are pre-existing, just
amplified). The stack:

    #00 libril.so (encode_field+364)
    #01 libril.so (pb_encode+76)
    #02 libril-qc-qmi-1.so (qcril_qmi_encode_npb+64)
    #03 libril-qc-qmi-1.so (qcril_qmi_ims_pack_msg+1936)
    #04 qcril_qmi_ims_socket_agent::send_message
    #06 qcril_qmi_imsa_service_status_ind_hdlr

The modem raises an IMSA service-status indication, rild packs an IMS protobuf for the socket client,
and the encoder walks off the end. `libril.so` is **built from source** and exports 11 nanopb symbols;
`libril-qc-qmi-1.so` is the **2016 blob** that hands it the message descriptors. nanopb's
`pb_field_t` layout is not stable across versions, so the blob's descriptors do not match the
encoder's expectations. Same bug class as the bonito camera: a prebuilt handing a platform type to
freshly built code.

**This only appears now because it needs an IMS socket client.** With no client, rild never calls
`send_message`, so every earlier build looked fine. The SIM appearing absent in the UI is a
consequence, not a separate fault: rild dying repeatedly leaves the subscription with
`simSlotIndex=-1` while `gsm.sim.state` still reads READY and the radio still shows Mint/LTE.

Two ways out, neither free:

- **Ship the stock 2016 `libril.so`** (`system/lib64/libril.so`, 120,224 B, present in the stock
  zip) so its nanopb matches the blob. Risk: our `rild` links it, and a 2016 libril may not satisfy
  what the current rild expects.
- **Pin nanopb in our `libril.so`** to the 2016 version as a vendor variant, leaving the platform
  copy alone. More work, no partition-wide blast radius.

## IMS REGISTERS (2026-09-23)

The nanopb pin was the last blocker. With it, on hardware:

    ImsResolver: Binding ImsService: ...ImsBridgeService with features: [{...}]
    ImsServiceController: onServiceConnected
    ImsBridge: onCreateMMTelImsFeature slot=0
    ImsResolver: ImsServiceController added on slot: 0 with feature: MMTEL
    ImsFeatureBinderRepo: [0] addConnection, subId=1, type=MMTEL
    FeatureConnector: [ImsPhoneCallTracker] imsFeatureCreated
    RILJ: [0200]< IMS_REGISTRATION_STATE {1, 1}
    RILQ: IMS registered for VOIP or VT service 1
    sys.ims.QMI_DAEMON_STATUS = 1

So the modem holds an IMS registration, rild reports it, the framework receives
`IMS_REGISTRATION_STATE {1,1}` (registered, LTE), the bridge is bound, and every framework consumer
-- `ImsPhoneCallTracker`, `ImsSmsDispatcher`, `ImsProvisioningController`, `ImsStateCallbackController`
-- has attached to the MMTEL feature. rild is stable at one start.

### The fix: nanopb field width, not nanopb version

`libril` is where nanopb lands for the whole RIL, because `libril-qc-qmi-1.so` **imports**
`pb_encode`/`pb_decode` from it rather than carrying its own. nanopb fixes `sizeof(pb_field_t)` at
compile time via `PB_FIELD_8/16/32BIT`; AOSP builds libril 32-bit, the msm8992 blob expects 16-bit, so
the descriptors it passes are strided wrong and the encoder runs off the array.

Patch: `overlay/patches/hardware/ril/0001-libril-stop-exporting-nanopb-so-the-QTI-blob-can-bind.patch`.
(The earlier field-width patch this section described was wrong and no longer exists; the real
cause was the 0.2.8 vs 0.3.x LTYPE shift, see below.)

It only reproduces once something connects to the IMS socket. Every build before ims.apk ran looked
healthy, and the visible symptom was telephony cycling Mint -> No Service -> no SIM, because rild
restarting every ~5 s leaves the subscription unable to hold its slot. **Telephony cycling like that
is worth checking rild's pid before believing anything about the SIM.**

### The media path: a missing IMS APN

`sys.ims.DATA_DAEMON_STATUS` is never set, so init never starts `ims_rtp_daemon` -- registration is
up but a call would have no RTP. `imsdatadaemon` runs and is *idle*, not crashing: `state=S`,
`wchan=poll_schedule_timeout`, utime 0. Its logs go to `/dev/diag`, not logcat, which is why it looks
silent.

Root cause is in the APN database, not the daemon. `strings` on the binary shows it calls
`dsi_get_data_srvc_hndl` for the IMS ApnType, and:

    310240 (Mint, this SIM)   6 APN rows, ZERO with type=ims
    310260 (T-Mobile proper)  33 rows, 8 with type=ims

Android matches APNs on the SIM's own operator numeric, so the 310260 IMS rows are unreachable even
though the SIM registers on 310260 as an EHPLMN. With no IMS PDN defined there is nothing for the
data daemon to attach to.

Fixed in `overlay/patches/vendor/apn/0001-US-add-the-missing-IMS-APN-for-310240-Mint.patch`, mirroring
the ungated `T-Mobile US IMS` row and gated to Mint's gid (`756D`) exactly as Mint's existing data row
is, so the other MVNOs sharing 310240 are untouched. The APN database is generated at build time from
`vendor/apn/<CC>.xml`, so this needs a build -- it is not pushable.

### Carrier config was NOT the problem

An earlier note here claimed `carrier_volte_available_bool` read false from carrier config and that
Mint/T-Mobile was refusing the device. **That was a misreading.** `dumpsys carrier_config` prints two
blocks and the first is `Default Values from CarrierConfigManager`, where every IMS key is false by
definition. The block that applies is `mConfigFromDefaultApp`, and for this SIM
(`carrierId=1`, `carrier_config_carrierid_1_T-Mobile-US.xml`) it reads:

    carrier_volte_available_bool     true
    carrier_wfc_ims_available_bool   true
    carrier_vt_available_bool        true
    carrier_ims_gba_required_bool    true

So VoLTE is enabled carrier-side. Read `mConfigFromDefaultApp`, never the defaults block.

That note stands, and it was only ever half the answer. `isVolteEnabledByPlatform()` ANDs the
carrier key with the **device** resource `config_device_volte_available`, and that was the false
leg. See "The root cause: the SIM's MNC, not the network's" below.

Worth remembering for later: `carrier_ims_gba_required_bool=true` means T-Mobile expects GBA for IMS
authentication. Registration already succeeds, so it is not blocking now.

### A build trap that cost a cycle

`apply-overlay.sh` regenerates `vendor/extra/product.mk` from the **enabled option set**. Run it
without the option environment and it writes that file empty -- every option's makefile fragment
silently vanishes, while `_build_rom.sh` still sets `WITH_*` and runs each option's `require.sh`, so
nothing complains. Build 10 shipped with stock Lineage sounds and boot animation for exactly this
reason. Always run it as `PRESET=<p> EXTRA_OPTIONS="..." apply-overlay.sh`, and check
`vendor/extra/product.mk` has content plus `vendor/extra/overlay/` has more than `oem-assets` in it.

## Overnight session (2026-09-24): three blockers cleared, one left

### Cleared

**The bridge never reported READY.** `LegacyMMTelFeature` set `STATE_INITIALIZING` in its constructor
and `STATE_READY` only inside `startSession` -- but the framework will not call `startSession` until
the feature reports READY. ImsResolver bound the service, `onCreateMMTelImsFeature` ran, and the log
went quiet with no error. READY is now published once ims.apk registers, waited for on a background
thread because ims.apk calls `addService("ims")` from `com.android.phone` while the bridge is a
separate process.

**registrationFeatureCapabilityChanged was being dropped.** The class comment claimed 13 had no
equivalent. It does, with an identical signature -- the earlier comparison missed it because the
declaration spans two lines and the extraction was line-based. It is the callback that matters most:
`MmTelFeatureCompatAdapter` turns exactly it into `MmTelCapabilities` via
`notifyCapabilitiesStatusChanged`. Dropped, the framework sees `Voice: false`, decides IMS cannot
carry a call, and routes to `GsmCdmaCallTracker` -- which on a carrier with no 2G/3G is RIL error 46
and an instant DISCONNECTED.

**Removing ImsVideoGlobals.init() broke open().** Dropping the VT init was right (its natives need an
`android::Surface` symbol that no longer exists) but incomplete: `openForSub` also calls
`ImsVideoGlobals.getInstance().setActiveSub(sub)`, and `getInstance()` throws when the singleton is
null -- with the message "ImsVideoGlobals: Multiple initializaiton.", which reads like the opposite of
the real problem. **The exception did not cross the binder**, so the bridge logged
`legacy session open, serviceId=0` and looked healthy while every session was dead. Removing the
getInstance/setActiveSub pair cleared both that exception and the 60-second
`REQUEST_QUERY_SERVICE_STATUS` / `REQUEST_IMS_REGISTRATION_STATE` timeouts.

### The remaining blocker: nanopb layout between rild and the QTI blob

    app -> rild:  qcril_qmi_decode_npb: Decoding failed: missing required field
    rild -> app:  qcril_qmi_encode_npb: Encoding failed: invalid data_size

**10 messages received, 10 decode failures, 0 successes, 0 outgoing packed.** Not message-specific:
nothing decodes at all, so rild answers nothing and the IMS service never learns its features, which
is why capabilities stay false even with the callback now forwarded.

`libril-qc-qmi-1.so` (2016 blob) **imports** all 17 `pb_*` symbols from `libril.so`, which we build
from source against nanopb **0.3.9.8 (2021)**. The blob's descriptor arrays were generated by QTI's
nanopb circa 2016 (`vendor/qcom/proprietary/qcril/qcril_qmi/nanopb_utils/`).

All three field widths were built and tested on hardware -- the intermediates for each exist, so these
were real tests:

| `PB_FIELD_*` | result |
|---|---|
| 32-bit (AOSP default for libril) | rild SIGSEGV in `encode_field` -- stride runs off the array |
| 16-bit | no crash, 21 decode failures, 0 successes |
| 8-bit (nanopb default) | no crash, 10 decode failures, 0 successes |

So the mismatch is **structural, not field width**. Currently left on 8-bit: fewest failures and no
crash, and rild is stable at one start.

### Options, ranked

1. **Build libril against a 2016-era nanopb.** Most likely correct; needs the right version
   identified and vendored as a variant. Neither binary carries a version string.
2. **Extract nanopb from the stock libril.so** and shim it onto the blob. Feasible in principle --
   stock exports all 17 `pb_*` -- but `llvm-objcopy --keep-global-symbols` only rewrites `.symtab`,
   not `.dynsym`, so its 72 `RIL_*` globals stay exported and would interpose on ours. Would need a
   real dynamic-symbol rewrite (no patchelf on this host).
3. **Ship stock libril.so wholesale.** Ruled out: our `rild` needs `ril_service_name`,
   `ril_service_name_base` and `rilc_thread_pool`, which the 2016 library does not define.

### Where the device stands

rild stable (1 start, no crashes), Mint on LTE, modem holds an IMS registration, ImsResolver binds
the bridge, the session opens without exceptions, and the daemons run. `DATA_DAEMON_STATUS` is still
unset and `ims_rtp_daemon` still does not start -- both plausibly downstream of the decode failure,
since the service never completes its status queries.

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

## The root cause: the SIM's MNC, not the network's (2026-09-24)

`config_device_volte_available` was shipped only in
`overlay/frameworks/base/core/res/res/values-mcc310-mnc260/`, on the assumption that Mint is
T-Mobile. Android picks resource mcc/mnc qualifiers from the **SIM**, not the serving network:

    gsm.sim.operator.numeric  310240   <- Mint, chooses the resource qualifier
    gsm.operator.numeric      310260   <- T-Mobile, does not

So the overlay never applied and the resource fell back to AOSP's `false`. The whole failure chain
hung off that one boolean:

    config_device_volte_available = false
      -> isVolteEnabledByPlatform() = false          (ANDed with carrier_volte_available_bool=true)
        -> CAPABILITY_TYPE_VOICE never in the CapabilityChangeRequest
          -> MmTelFeatureCompatAdapter enables FEATURE_TYPE_UT_OVER_LTE (cap 4) and nothing else
            -> modem never attempts registration
              -> Registration.state = 2 NOT_REGISTERED, errorCode 0, for the entire session
                -> only registrationDisconnected ever reaches the framework
                  -> ImsPhone not selected -> CS fallback -> DIAL error 46 INVALID_MODEM_STATE

Fixed by patch 0026: `values-mcc310-mnc240/config.xml`. Keep it in step with the `-mnc260` sibling.

**This was a regression, not a gap that was always there.** Patch 0004 replaced a global
`persist.dbg.volte_avail_ovr=1` with the `-mnc260` overlay; its own comment records the swap. The
override worked because it is carrier-agnostic, the overlay did not because it is scoped to an MNC
this SIM does not report. The 2026-09-23 "IMS REGISTERS" note above was taken before that swap.

Corroborated in the logs: `qcril_qmi_imsa_is_ims_registered_for_voip_vt_service` printed
`IMS registered for VOIP or VT service 1` on 2026-09-23 and `... 0` on 2026-09-24 before the fix.

### What this clears up

- **The registration-listener gap was never a bug in our code.** The bridge, the ten forwarded
  `IImsRegistrationListener` methods, the generated AIDL and nanopb 0.2.8 were all working. They
  were faithfully relaying "not registered".
- **`DATA_DAEMON_STATUS` / `imsdatadaemon` was a symptom, not a second bug.** `imsdatadaemon`
  starts on its own once registration proceeds.
- **The CNEService crash is unrelated.** It does not even start on a boot where IMS registers.
- **Do not read registration off `RILJ: IMS_REGISTRATION_STATE {1,1}` alone.** That is the legacy
  RIL query. The signal the call path follows is the `ImsQmiIF.Registration` unsol (id 204) reaching
  `ImsRegistrationCompatAdapter`. They disagreed for a whole session: RILQ said registered while the
  MMTel side logged `registrationDisconnected` four times.

### Measured after the fix

    changeEnabledCapabilities - cap: 0 radioTech: 13 enabled   (FEATURE_TYPE_VOICE_OVER_LTE)
    setFeatureValueReceived with value 1
    Registration payload  08 03 -> 08 03 -> 08 01   (REGISTERING -> REGISTERED), radioTech 14
    SST: setImsRegistrationState {registered=true mImsRegistrationOnOff=true}
    ImsPhoneCallTracker: isVolteEnabled=true
    MmTel Capabilities - [Voice: true ...]   and it STAYS true
    init.svc.imsdatadaemon: running

### Reading the IMS wire protocol

`ImsSenderRxr` logs every frame: `Response data: [...]` is raw bytes, the next line is the decoded
envelope. Frame = one length byte, then a `MsgTag` (field 1 fixed32 token, 2 varint type, 3 varint
message id, 4 varint error), then the payload message. The length byte covers the tag only. For
`Registration` (id 204): field 1 `state` varint (1 REGISTERED, 2 NOT_REGISTERED, 3 REGISTERING),
field 2 `errorCode` **fixed32**, field 3 `errorMessage`, field 4 `radioTech`. Decoding a frame by
hand is the fastest way to tell a transport bug from an honest answer from the modem.

### Still to do

- `persist.dbg.volte_avail_ovr=1` is set on the test Robin, left there so a call can be tried
  before the next build. **Clear it before validating patch 0026** or the overlay is untested.
  It is deliberately not shipped: it forces VoLTE on for every carrier.
- `overlay/packages/apps/CarrierConfig/res/xml/vendor.xml` carries the same `mnc="260"`
  assumption. Inert here, because the carrier's own bundle already supplies those keys. Left alone
  so patch 0026 stays one attributable change.

## The call path opens, and hits the rename's sharpest edge (2026-09-24)

With registration up, dialling now goes down `ImsPhoneCallTracker.dialInternal` instead of
`GsmCdmaCallTracker` -- the IMS path. It fails immediately at `createCallSession()`:

    Class not found when unmarshalling: org.codeaurora.ims.legacy.ImsStreamMediaProfile
      at org.codeaurora.ims.legacy.ImsCallProfile.readFromParcel(ImsCallProfile.java:328)
      at org.codeaurora.ims.legacy.internal.IImsService$Stub.onTransact

`readParcelable(null)` is the culprit, and it is ours. A null loader makes `Parcel` fall back to
its own -- the BOOT classloader. On 7.1 that worked because these were `com.android.ims.*`,
framework classes on the boot classpath. The rename moved them into the app, where the boot loader
cannot see them, so the first inbound `ImsCallProfile` throws and every call fails.

Fixed in `rebuild-app.sh`: each `readParcelable` site is repointed at the class's own loader
(`const-class` + `getClassLoader`), asserted at exactly 4 call sites across `ImsCallProfile` (x2),
`ImsConferenceState` and `ImsExternalCallState`. Verified by assembling each rewritten class.

**Rule for the rename: a class that moves off the boot classpath breaks every `readParcelable(null)`,
`readBundle()` and `readSerializable()` that used to resolve it.** Grep for those before blaming the
transport.

## Advance research: the media path has no ABI blockers (2026-09-24)

Swept every IMS/RTP vendor library with `rom-forge/tools/abi-gap.sh`, which lists the symbols a
prebuilt imports that the platform no longer exports:

    lib-rtpcore.so             181 symbols, 0 unresolved
    lib-rtpcommon.so            42 symbols, 0 unresolved
    lib-rtpsl.so                64 symbols, 0 unresolved
    lib-rtpdaemoninterface.so   22 symbols, 0 unresolved
    lib-imsdpl.so              172 symbols, 0 unresolved
    lib-dplmedia.so             61 symbols, 0 unresolved
    lib-imsSDP.so / -imsqimf / -imss / -imsxml / -imsrcs*      all 0 unresolved
    ims_rtp_daemon              94 symbols, 0 unresolved
    imsdatadaemon              107 symbols, 0 unresolved

**The entire voice media path is ABI-clean.** Nothing to shim, nothing to patch. If VoLTE audio
fails it will not be because a 2016 binary cannot load.

### Why ims_rtp_daemon has never started

The init chain is intact and matches the stock ramdisk's own `init.target.rc` exactly:

    on property:sys.ims.QMI_DAEMON_STATUS=1   -> start imsdatadaemon      (=1, running)
    on property:sys.ims.DATA_DAEMON_STATUS=1  -> start ims_rtp_daemon     (never set)

`imsdatadaemon` is alive and **idle**, not crashed: `state=S`, `wchan=poll_schedule_timeout`, and
utime/stime frozen at 2/1 across a five-second sample. No SELinux denials. It owns
`sys.ims.datadaemon.ims.netid` (nothing else on the device references that property) and listens on
`/dev/socket/ims_datad` with **zero connections**, while `/dev/socket/qmux_radio/rild_ims0` shows a
live connected pair -- so the QMI path to the modem is up and only the data daemon is unstimulated.
Its client library is `lib-imsdpl.so`, which is ABI-clean.

Nothing is broken here. The daemon is waiting to be asked, and nothing has asked it because no call
has ever set up. Do not "fix" this before a call completes.

## VT ABI: scoped, and smaller than lib-imsvt.so makes it look (2026-09-24)

    libimscamera_jni.so    14 symbols,  0 unresolved
    libimsmedia_jni.so     18 symbols,  1 unresolved   <- android::Surface::Surface(sp<IGBP>&, bool)
    lib-imsvt.so          266 symbols, 61 unresolved   <- NOT in the init path

`lib-imsvt.so` looks fatal and is not relevant: nothing links it, `libimsmedia_jni.so` does not
depend on it, and the Java side loads only `imsmedia_jni`/`imscamera_jni`. It is dlopened later, if
a video call actually starts. Its 61 gaps are two different problems:

- ~45 `Rcc*` rate-control symbols live in **`librcc.so`, which exists in the stock ROM and we never
  extracted** -- a plain omission in `proprietary-files-ims.txt`.
- The rest are genuinely dead platform API: `IGraphicBufferAlloc` (deleted),
  `IOMXObserver` (the pre-Treble OMX binder interface, replaced wholesale by HIDL/Codec2),
  `MediaBuffer(sp<GraphicBuffer> const&)`. Those are removed subsystems, not grown types, and are
  not shimmable. **Video calls are not coming back.**

That is fine, because the goal was never video. `ImsVideoGlobals.init()` needs only the two JNI
libs. Making it load lets us delete three fragile smali rewrites -- the init removal, the
`openForSub` surgery and the `maybeCreateVideoProvider` no-op -- each of which has already cost a
build cycle.

## VOLTE WORKS (2026-09-24)

Outgoing call connects over IMS with the HD indicator and **two-way audio**, verified on hardware.

What made the difference, in the order it mattered:

1. `config_device_volte_available` under `values-mcc310-mnc240`. It had been under `-mnc260`, and
   the SIM reports 310240 while the network reports 310260. One boolean, resolved from the wrong
   directory, and the framework never asked for voice, so the modem never registered, so the only
   thing the listener could report was "disconnected". That looked like a broken registration
   listener in our bridge for days.
2. `readParcelable(null)` repointed at the app class loader. The rename moved these classes off the
   boot classpath, where a null loader could no longer find them, so every `createCallSession`
   threw.
3. `libshim_vtsurface` plus the 3560 -> 8168 allocation rewrite, which let `ImsVideoGlobals.init()`
   run for the first time on 13. That initialised `CameraController` and `LowBatteryHandler`
   and closed all six "Not initialized" crash sites at once, instead of the sixth and seventh
   rounds of patching individual call sites.

Final boot, before the call: 0 UnsatisfiedLinkError, 0 "Not initialized", `registered=true`,
`isVolteEnabled=true`, `cap: 0 radioTech: 13 enabled`.

### The media path never needed ims_rtp_daemon

`ims_rtp_daemon` is **still not running** and `sys.ims.DATA_DAEMON_STATUS` is **still unset**, and
audio works in both directions anyway. So the assumption that the RTP daemon gates VoLTE audio on
this device was wrong: voice media goes modem-to-DSP without the AP-side daemon, which only matters
for paths we do not have (VT, and some carrier configurations). The earlier sweep showing the whole
RTP stack ABI-clean was correct but beside the point.

**Do not "fix" `imsdatadaemon` sitting idle.** It is idle because nothing needs it.

### Still open

- Wi-Fi calling: the platform gate is open (the toggle appears, `carrier_wfc_ims_available_bool`
  and `config_device_wfc_ims_available` are both true) but IWLAN registration is untested.
- Video calling is deliberately off and cannot be revived: `lib-imsvt.so` needs `IOMXObserver` and
  `IGraphicBufferAlloc`, platform interfaces deleted outright.
