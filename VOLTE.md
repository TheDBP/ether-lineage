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
| blob list, 58 entries | `proprietary-files-ims.txt` |
| staging | `extract-ims-blobs.sh` → `vendor/extra/ims-blobs/` + a generated `ims-blobs.mk` |
| init, sepolicy, JNI symlinks | device patch `0018` |

Staging goes to `vendor/extra` rather than `vendor/nextbit/ether` on purpose: that repo is synced
from TheMuppets, which omits the IMS set deliberately, and blobs must never be committed anyway.
`apply-overlay` clears `vendor/extra` per build, so nothing leaks between presets.

Two things the script got wrong first, both worth keeping in mind for the next list:

- the destination decides the partition, not the source. `framework/`, `priv-app/` and `etc/` are
  system-side; forcing them to vendor produces an image where the IMS jars sit somewhere the boot
  classpath never looks, and nothing complains.
- the apks are odexed against the 7.1 boot image, so they are copied verbatim — never re-signed or
  re-compiled by the build.

Still missing before this can boot: `ims-blobs.mk` is not yet included by `device.mk`, and the four
daemons the stock zip ships are more than the two bullhead starts (`ims_rtp_daemon` and
`imscmservice` have no init entry — find out whether the APK starts them before adding any).

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
