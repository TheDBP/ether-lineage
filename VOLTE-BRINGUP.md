# VoLTE bringup on the Nextbit Robin

How a 2016 phone whose IMS stack shipped for Android 7.1.1 ended up placing VoLTE calls on
Android 13, what each piece does, and — at least as usefully — every wrong turn on the way.

Status as of 2026-09-24: **VoLTE works, outgoing and incoming, with two-way audio on both and the
HD indicator.** Calls end with `CODE_USER_TERMINATED` and a `REMOTE`/`LOCAL` disconnect cause, i.e.
somebody hung up, rather than an error. Wi-Fi calling is available at the platform level but its
registration is untested. Video calling is deliberately off and cannot be revived.

`VOLTE.md` is the chronological working log this is distilled from; it has the raw measurements.
The generic, device-independent lessons live in `forge/docs/debugging-volte.md`.

---

## 1. Why any of this is necessary

The Robin's IMS stack is proprietary QTI userspace built for Android 7.1.1. Two things about it
matter:

**The framework API it targets no longer exists.** In 7.1 an IMS implementation was an app exposing
`com.android.ims.internal.IImsService` over Binder, and `com.android.ims.*` was part of the *boot
classpath*. Android 9 deleted that API and replaced it with `android.telephony.ims.ImsService`.
There is no version of Android 13 that can talk to a 7.1 IMS app directly.

**The blobs are compiled against a 2016 platform ABI.** They import symbols that changed meaning,
changed signature, or were deleted outright. Nothing warns you: the library loads, or it loads and
misbehaves, or it fails on a symbol you have never heard of.

So there are two independent problems — an API gap and an ABI gap — and they fail in completely
different ways. Most of the time lost on this port was spent mistaking one for the other.

---

## 2. Architecture

```
  Android 13 telephony  (ImsPhone, ImsPhoneCallTracker, ImsResolver)
            |
            |  android.telephony.ims.*  (modern ImsService API)
            v
  ImsServiceControllerCompat + MmTelFeatureCompatAdapter      <- AOSP's own pre-P compat layer
            |
            |  android.telephony.ims.compat.*                    (still in AOSP, unused elsewhere)
            v
  ImsBridge            (device/nextbit/ether/ims-bridge)       <- ours
            |
            |  org.codeaurora.ims.legacy.internal.IImsService    (the 7.1 Binder interface,
            v                                                     regenerated from the binary)
  ims.apk              (stock, deodexed and package-renamed)
            |
            |  protobuf over a local socket
            v
  rild / libril-qc-qmi-1.so  -> modem
```

AOSP still ships a compatibility layer for pre-P IMS implementations
(`android.telephony.ims.compat`). It is unused by any current device, but it is complete, and it is
what makes this possible at all: we only had to bridge from *its* interface down to the 7.1 app,
not reimplement the modern ImsService API.

---

## 3. The pieces

### 3.1 `ims.apk` — deodexed and renamed

Stock ships a 27 KB manifest plus an arm64 `.odex` compiled against the 7.1 boot image. It has to be
deodexed before it can run, and then renamed, because it references `com.android.ims.*` — classes
Android 9 deleted from the boot classpath.

`deodex-app.sh` extracts the apk and odex, pulls the arm64 boot classpath out of the stock image,
deodexes, and hard-fails on leftover quick opcodes or unresolved references. It also recovers 22
legacy types that live only in the boot image, not in the apk:
`boot-ims-common.oat` and `boot-framework.oat//system/framework/framework.jar:classes2.dex`.

> **Trap:** `baksmali x` disassembles only the *first* dex of a multi-dex oat. Address later ones
> explicitly as `<oat>//system/framework/framework.jar:classes2.dex` or you will silently get a
> fraction of the classes.

`rebuild-app.sh` then rewrites `com.android.ims` to `org.codeaurora.ims.legacy` — 1589 references in
the app, 6969 in the recovered framework classes, 373 descriptor strings. Broadcast action strings
such as `com.android.ims.IMS_SERVICE_UP` are deliberately **not** renamed: they are wire contracts
with other components, not class names.

Every rewrite in that script asserts its own expected count and fails the build if reality disagrees.
That is not defensive styling; several of them were wrong on the first attempt and the assertion is
what caught it.

### 3.2 The legacy AIDL surface

The bridge has to speak the exact Binder protocol `ims.apk` expects: right transaction codes, right
interface descriptors, right parameter order. Guessing is not viable.

`gen-legacy-aidl.py` generates all 14 interfaces from the stock binary's own `TRANSACTION_*`
constants and method descriptors. `verify-legacy-aidl.sh` then checks the **built** apk's transaction
codes and descriptors against the stock binary — 14 interfaces, 148 transactions, all matching. It
was negative-tested by corrupting one code and confirming it exits non-zero.

### 3.3 `ImsBridge`

`device/nextbit/ether/ims-bridge` implements the pre-P `MMTelFeature` and forwards to the legacy
service. Notable details:

- `sharedUserId="android.uid.phone"`, platform-signed, privileged.
- It declares **no** privileged permissions. Adding them without a `privapp-permissions` allowlist
  entry crash-loops `system_server` at `systemReady`; `android.uid.phone` already grants what is
  needed.
- `LegacyMMTelFeature` reports `STATE_READY` only after `ServiceManager.waitForService("ims")`
  returns, because the framework will not call `startSession` on a feature that is not ready.
- `getVideoCallProvider` returns null — video is not bridged.

### 3.4 nanopb 0.2.8

`ims.apk` talks to `rild` in protobuf. `libril-qc-qmi-1.so` does not carry its own nanopb; it
*imports* `pb_encode`/`pb_decode` from `libril`. Android 13's libril has nanopb 0.3.x, and 0.3.x
inserted `PB_LTYPE_BOOL = 0x00`, shifting every other `PB_LTYPE_*` up by one. A 0.3.x runtime reads a
0.2.8 descriptor as the *next type along*: `VARINT` becomes `STRING`, `STRING` becomes `SUBMESSAGE`,
and the decoder chases a pointer that is really an integer.

Two changes fix it:

- `hardware/ril` patch 0001 gives libril a version script (`local: pb_*;`) so it stops exporting
  nanopb, while keeping 0.3.x for libril's own SAP descriptors.
- `device/nextbit/ether/nanopb-0.2.8/` builds `libnanopb_legacy` from `external/nanopb-c` at tag
  `android-7.1.1_r1`, bound to the blob via `TARGET_LD_SHIM_LIBS`.

> **This was misdiagnosed twice.** It is *not* a `PB_FIELD_8/16/32BIT` width problem — all three
> widths fail identically, and 32-bit additionally segfaults, which made it look like one. The
> symbol names are unchanged across the version bump, so a symbol-level check reports nothing wrong.

### 3.5 CNE

The Qualcomm Connectivity Engine (`cnd` plus `CNEService.apk`) was disabled during the initial port.
IMS needs it. Patches 0001 and 0002 were edited to restore the `cnd` service and the
`com.quicinc.cne.api` / `.server` HAL manifest entries. `com.qualcomm.qti.dpm.api` stays removed.

### 3.6 The Surface shim

`ImsVideoGlobals.init()` dlopens the VT natives, and `libimsmedia_jni.so` imports
`android::Surface::Surface(sp<IGraphicBufferProducer> const&, bool)` — a constructor Android 13
replaced with a three-argument form. The symbol resolves nowhere, `ImsMedia.<clinit>` throws
`UnsatisfiedLinkError`, and the whole IMS service dies at `ImsService.onCreate`.

`libshims/vtsurface_shim.cpp` supplies the old mangled name and placement-constructs the modern one.

That alone would be a heap-corruption bug. The blob does `new Surface(...)` with `sizeof(Surface)`
baked into the instruction stream at compile time — **3560 bytes in 2016, 8168 today**, measured at
six independent `new Surface` call sites in the platform's own `libandroid_runtime.so`. So
`extract-ims-blobs.sh` also rewrites the blob's allocation: one `MOVZ x0, #3560` becomes
`MOVZ x0, #8168`. It searches for the instruction encoding rather than a fixed offset, asserts
exactly one occurrence, and is idempotent.

Why bother, when video does not work anyway? Because `init()` creates singletons the *voice* path
uses. Without it, `CameraController` and `LowBatteryHandler` are null, and six separate call sites
throw `RuntimeException: ... Not initialized` — one of which kills `com.android.phone` on every
call. Four of those were patched out individually before it became obvious that fixing `init()`
fixes the class.

---

## 4. The failure that defined the port

For several days the symptom was: IMS capabilities negotiated, `MmTel Capabilities - [Voice: true]`,
`UNSOL_VOPS_CHANGED`, `STATUS_ENABLED` — and yet every call fell back to circuit-switched and failed
with `DIAL error 46 / INVALID_MODEM_STATE`. No `onImsConnected`. The obvious reading was that our
bridge's registration listener was broken.

It was not. Decoding the raw frames the IMS app exchanges with the modem settled it in minutes:

```
UNSOL_RESPONSE_IMS_NETWORK_STATE_CHANGED (id 204), payload:
  08 02        field1 state     = 2  -> NOT_REGISTERED
  15 00000000  field2 errorCode = 0  (fixed32, correct wire type)
  20 0E        field4 radioTech = 14 (LTE)
```

Well-formed protobuf, correct wire types, no error. The listener was faithfully relaying
"not registered". **The modem had never been asked to register.**

Walking back: the framework only asks the vendor stack to enable a capability it believes the
platform supports. `ImsManager.isVolteEnabledByPlatform()` is

```java
config_device_volte_available   AND   carrier_volte_available_bool
```

The carrier leg was fine (`mConfigFromDefaultApp` had it true). The device leg was **false**,
because the resource was in `overlay/.../values-mcc310-mnc260/` and:

```
gsm.sim.operator.numeric   310240   <- Mint, and this is what picks the resource qualifier
gsm.operator.numeric       310260   <- T-Mobile, and this picks nothing
```

**Android takes resource mcc/mnc qualifiers from the SIM, not the serving network.** An MVNO on a
host network reports its own MCC/MNC on the SIM. The overlay never applied, the resource fell back to
AOSP's `false`, and one boolean suppressed VoLTE, VT and Wi-Fi calling together.

It was also a regression of our own making: patch 0004 had replaced a working global
`persist.dbg.volte_avail_ovr=1` with that MNC-scoped overlay. The log line
`qcril_qmi_imsa_is_ims_registered_for_voip_vt_service` read `1` before the swap and `0` after.

Fixed in patch 0026 by adding `values-mcc310-mnc240`.

---

## 5. Everything else that failed, and what it taught

**`readParcelable(null)` after the rename.** `createCallSession` died with
`ClassNotFoundException: org.codeaurora.ims.legacy.ImsStreamMediaProfile`. A null loader makes
`Parcel` fall back to the *boot* classloader. On 7.1 these were `com.android.ims.*` framework
classes and that worked. Renaming moved them into the app, invisible to the boot loader.
→ **A class that moves off the boot classpath breaks every `readParcelable(null)`, `readBundle()`
and `readSerializable()` that used to resolve it.** Grep for those before blaming the transport.

**Four singletons, one cause.** `openForSub`'s `getInstance()`, `maybeCreateVideoProvider`'s
`CameraController`, `maybeUpdateLowBatteryStatus`'s and `canDial`'s `LowBatteryHandler` — all
because `ImsVideoGlobals.init()` had been deleted. Each was patched individually, each cost a build
cycle. The fifth occurrence is what finally justified the shim.
→ **When the same root cause surfaces three times, stop patching call sites.**

**Exceptions vanish across Binder.** `JavaBinder: *** Uncaught remote exception! (Exceptions are not
yet supported across processes.)` means a callee threw and the caller saw success — or, here, a null
session and no explanation. Several of the above presented as "the bridge returned null".

**Reading the wrong registration signal.** `RILJ: IMS_REGISTRATION_STATE {1,1}` said registered while
the MMTel side logged `registrationDisconnected` four times in the same session. The legacy RIL query
and the `ImsQmiIF.Registration` unsol are different signals and they disagree. The one the call path
follows is the unsol.

**The incoming-call path deadlocks the main thread, and it is the compat layer's fault.**
`ImsPhoneCallTracker.onIncomingCall` defaults to `executeAndWait()`, which is
`CompletableFuture.runAsync(task, mExecutor).join()`, and the production constructor injects
`phone.getContext().getMainExecutor()`. A modern ImsService calls `onIncomingCall` on a **binder**
thread, where blocking costs nothing -- hence the property name
`ro.telephony.block_binder_thread_on_incoming_calls`. The pre-P compat layer instead delivers it
from `MmTelFeatureCompatAdapter`'s `ACTION_IMS_INCOMING_CALL` broadcast receiver, which runs on the
**main** thread, so `join()` waits for a task only the waiting thread can run.

Everything else is downstream, and none of it looks like the cause. `PhoneInterfaceManager.sendRequest`
posts to the main thread and waits with no timeout, so *every* unrelated telephony call hangs: that
is why Settings ANRed on `isVoNrEnabled`, and why binder threads pile up on `MainThreadRequest`
monitors. Eventually `TelephonyConnectionService` cannot execute, the phone process is killed for
ANR, and the next call fails with `Phone is null, OUT_OF_SERVICE` -- with IMS never re-registering.
Set the property false (device patch 0029). AOSP's else-branch comment names the case exactly: "for
legacy IMS we want to avoid blocking the binder thread".
**`sys.ims.*` is typed `qcom_ims_prop`** and unreadable from a shell without root. Empty is not the
same as unset.

**`apply-overlay.sh` regenerates `vendor/extra/product.mk` from the enabled option set.** Run without
the option environment it writes that file empty and silently drops every option, producing a ROM
with stock sounds and no re-skin. Always go through `bootstrap.sh`.

**Editing a patch file does not change the build tree.** The tree is rebuilt from `BASE_REF` plus
patches at bootstrap; verifying a change in a scratch replay proves nothing about the build that just
ran.

---

## 6. Verifying it

In rough order of usefulness:

```sh
# 1. Did the framework ask for voice at all? cap 0 == FEATURE_TYPE_VOICE_OVER_LTE.
adb logcat -d | grep 'changeEnabledCapabilities'
#    cap: 0 radioTech: 13 enabled        <- what you want
#    cap: 4 radioTech: 13 enabled        <- UT only: the platform gate is shut, see section 4

# 2. What does the modem actually say? Decode the frame, do not trust the summary.
adb logcat -d | grep -A1 'UNSOL_RESPONSE_IMS_NETWORK_STATE_CHANGED'
#    payload 08 01 = REGISTERED, 08 02 = NOT_REGISTERED, 08 03 = REGISTERING

# 3. Framework's view.
adb logcat -d | grep -E 'setImsRegistrationState|isVolteEnabled='

# 4. Both legs of the availability gate.
adb shell dumpsys carrier_config | awk '/mConfigFromDefaultApp/{f=1} f' | grep volte_available
adb shell getprop gsm.sim.operator.numeric    # the SIM picks the resource qualifier
adb shell getprop gsm.operator.numeric        # the network does not
```

Frame format, for hand-decoding: one length byte, then a `MsgTag` (field 1 fixed32 token, 2 varint
type, 3 varint message id, 4 varint error), then the payload. **The length byte covers the tag only.**
For `Registration` (id 204): field 1 `state` varint, field 2 `errorCode` **fixed32**, field 3
`errorMessage`, field 4 `radioTech`.

`forge/tools/abi-gap.sh <blob>` lists symbols a blob imports that the platform no longer exports.
Note what it cannot tell you: a symbol that still resolves can have changed meaning (nanopb), and a
type that still exists can have grown (`Surface`).

---

## 7. Reproducing the build

Everything is staged from the stock ROM at product-config time; there is no remembered command.

```sh
EXTRA_OPTIONS="bringup oem" PRESET=clean ./forge/bootstrap.sh
```

`device.mk` stages `vendor/ims-blobs` on first build if it is absent, running `extract-ims-blobs.sh`,
which in turn runs `deodex-app.sh` and `rebuild-app.sh` and applies the Surface allocation rewrite.
The include of `ims-blobs.mk` is deliberately hard, not `-include`: a ROM whose VoLTE is quietly
absent is exactly the failure the staging exists to prevent. To force re-staging, delete
`vendor/ims-blobs`.

Relevant patches:

| patch | what |
|---|---|
| device 0018 | IMS daemons, JNI symlinks, sepolicy |
| device 0019–0022 | ImsBridge, legacy AIDL, the sub-interfaces |
| device 0023 | stage the IMS blobs from the build |
| device 0025 | nanopb 0.2.8 |
| device 0026 | **`config_device_volte_available` under the SIM's MNC** |
| device 0027 | Surface shim; video calling off |
| device 0029 | **`block_binder_thread_on_incoming_calls=false`** -- without it, incoming calls deadlock `com.android.phone` |
| `hardware/ril` 0001 | stop libril exporting nanopb |
| `vendor/apn` 0001 | the missing IMS APN for 310240 |

---

## 8. What is still open

**Wi-Fi calling.** Not working. The platform gate is open — the toggle appears, and both
`carrier_wfc_ims_available_bool` and `config_device_wfc_ims_available` are true — and the call path
goes through the same bridge, so it should work once registration does. Three things were wrong
underneath, found in this order:

*The modem is not the blocker.* `strings` over `/firmware/image/modem.b*` gives `IWLAN S2B IFACE
1..16`, an IMS RAT-change handler that knows about IWLAN, and S2b NV item paths. The carrier config
in the same image carries `epdg_fqdn:ss.epdg.epc.mnc260.mcc310…` with `IWLAN` in its
`Supported_RAT_Priority_List`. The capability was compiled in and left switched off; Wi-Fi calling
was never a shipped feature on this device.

*CNE could not read its own configuration.* Every `persist.cne.*` name fell through to
`default_prop`, which `cnd` is refused, so `persist.cne.feature=1` was set and never seen. The
visible consequence was one layer up, in the RIL: `pref data tech UNKNOWN` with a candidate list of
CDMA/EVDO/GSM/LTE and no IWLAN. Device patch 0031 gives those prefixes their own type; the measured
result was `pref data tech` becoming `LTE`. IWLAN still did not appear.

*The modem was declining, not failing.* Toggling Wi-Fi calling does reach it and the QMI transaction
succeeds, and it answers:

    client_provisioning_config_ind_hdlr: .. client_prov_enabled: 0
                                         .. wifi_call_preference: 0    (1 was sent)

Of the seven client-provisioning items the RIL exposes, we sent `WIFI_CALL` and
`WIFI_CALL_PREFERENCE` and never `ENABLE_VOWIFI` — the user's *preference* for a feature the modem
does not consider *provisioned*. `ImsManager.isWfcProvisionedOnDevice()` only reaches the branch that
pushes the provisioning value when `isMmTelProvisioningRequired(VOICE, IWLAN)` is true; ours was
false, so it short-circuited to "provisioned" locally and sent nothing. This is also why VoLTE was
never affected by the same setting: VoLTE works because the modem's own carrier config enables it,
so it never needed this path.

Device patch 0035 sets `ims.mmtel_requires_provisioning_bundle` for VOICE over IWLAN alone. The
deprecated global `carrier_volte_provisioning_required_bool` stays false deliberately — switching it
on would gate working VoLTE on provisioning too. **Untested at time of writing.**

`persist.vendor.cnd.wqe` is deliberately left off. WQE is Wireless Quality Estimation: it actively
probes an ICD server to measure RTT and bitrate and reports a verdict to the modem. It is not a gate
for Wi-Fi calling, and with no probe server configured it may report the link as bad and suppress the
handover we are trying to get.

**Video calling will not work.** `lib-imsvt.so` imports `IOMXObserver` and `IGraphicBufferAlloc` —
platform interfaces deleted outright when OMX moved to HIDL/Codec2 — among 61 unresolved symbols.
Those are removed subsystems, not grown types, and are not shimmable. It is switched off at the
framework (`config_device_vt_available=false`) so nothing advertises a capability it cannot deliver.
The shim exists only so `init()` can create its singletons.

**`ims_rtp_daemon` never runs, and that is fine.** `sys.ims.DATA_DAEMON_STATUS` is never set, so the
daemon never starts — and audio works in both directions regardless. Voice media goes modem-to-DSP
without the AP-side daemon on this device. `imsdatadaemon` sits idle in `poll` with no client on
`/dev/socket/ims_datad`; that is not a fault. **Do not "fix" it.**
