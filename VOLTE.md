# VoLTE on ether — work branch `lineage-20.0-volte`

Goal: IMS registration (`dumpsys telephony.registry` → `mImsRegState=REGISTERED`) and a VoLTE call on
T-Mobile / Mint (310/260). Nothing here ships until a call completes both ways with audio.

## What exists

- Modem: the 8992 modem image has the IMS stack and `mcfg_sw/generic/na/tmo/commerci/mcfg_sw.mbn`.
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
`IImsMMTelFeature` API, which this APK does not implement. LineageOS bullhead commit `5cef16f`
("Disable pre-P IMS stack — does not work at all and kills our dialer", lineage-16.0) is the
same wall.

The APK's framework surface is small: `com.android.ims.{ImsCallProfile,ImsReasonInfo,ImsSsInfo,
ImsCallForwardInfo,ImsConferenceState,ImsStreamMediaProfile,ImsSuppServiceNotification,ImsConfigListener}`
and `com.android.ims.internal.{IImsService,IImsCallSession,IImsCallSessionListener,IImsUt,IImsUtListener,
IImsEcbm,IImsEcbmListener,IImsConfig,IImsMultiEndpoint,IImsRegistrationListener,IImsVideoCallProvider,
ImsVideoCallProvider}`. On 13 the parcelables live in `android.telephony.ims.*` and the `internal`
AIDLs carry 13 signatures, so the APK cannot load against the boot classpath as-is.

Modem transport is a unix socket to QCRIL (`ImsQmiIF` protobuf), served by `libril-qc-qmi-1.so`
with `imsqmidaemon` — all ether's own blobs.

## Approach

1. Deodex `ims.odex` (baksmali `x`), rename `com.android.ims.*` → `org.codeaurora.ims.legacy.*` in
   smali, rebuild, sign with the platform key (`sharedUserId` phone process needs it).
2. `ims-legacy` Java library: the 7.1 parcelables + AIDLs under the renamed package, built from
   AOSP 7.1 `frameworks/base/telephony/java/com/android/ims/` (Apache 2). Boot classpath or
   `uses-library` injected into the rebuilt manifest.
3. Bridge in `frameworks/opt/net/ims`: `IImsService` → `IImsMMTelFeature` (near 1:1 method map,
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

## Scoreboard

daemons stay up → `sys.ims.QMI_DAEMON_STATUS=1` → `service list` shows `ims` → bridge bound
(`dumpsys telephony.registry` `mImsRegState`) → Enhanced 4G toggle appears → outgoing call
connects → audio both ways → incoming call → SMS over IMS → Wi-Fi calling.

Budget: three sessions. No registration by the end of the third → park it, document the state.

## Reference material

Outside every repo, never pushed. `upstream-reference/` sits beside the device repos; the stock zip is gitignored in the repo root:

| path | what |
|---|---|
| `Ether_Stock_ROM_N108.zip` | primary source: every IMS blob for this exact modem/RIL |
| `device_lge_bullhead/` | LineageOS lineage-16.0: `init.bullhead.rc`, `sepolicy/`, `Android.mk` IMS lib symlinks |
| `bullhead-factory/bullhead-opm7.181205.001/ext/{system,vendor}` | stock 8.1 for a second `ims.apk` (platformBuildVersionCode 27) if the 7.1 one deodexes badly |
| `vendor_lge_bullhead-16.0/bullhead/proprietary/` | TheMuppets 16.0 blob set; `ims.apk` deliberately excluded upstream |
| `vendor_lge_bullhead-17.1/` | TheMuppets 17.1 (trimmed set) |

## Rules

- One change per flash. Keep `lineage-20.0` shippable; nothing merges until the scoreboard completes.
- Test with the SIM in; `logcat -b radio` and `dumpsys telephony.registry` after every flash.
- A root build is not needed; `adb root` on userdebug is enough.
- Stock blobs stay in `vendor/nextbit/ether`; never in a public repo.
