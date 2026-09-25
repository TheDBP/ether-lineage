# Consolidating the device patch series

A plan, not a record. Delete this file once it has been carried out.

The device series is 38 patches and `check-patch-series.sh` reports 12 pairs where a later patch undoes
an earlier one. That is not 12 bugs; it is the shape of work done in the order it was understood,
preserved in a series that is replayed from scratch and therefore reads as the *description of a tree*
rather than as history. A reader should not have to hold four patches in their head to know what one
boolean ends up as.

## What must not change

The consolidation is about legibility, not content. Nothing below removes or weakens:

- the ImsBridge and the legacy AIDL surface (0019-0022)
- the IMS blob staging that refuses to build a ROM silently lacking VoLTE (0023)
- nanopb 0.2.8 for the QTI RIL blob (0024)
- the VT natives shim (the code half of 0026)
- the IWLAN data path (0029) — inert on this device, correct and portable for another
- CNE and the property labelling (0031, 0032, 0033)

Wi-Fi calling stays wired and stays switched off. Another device inherits the structure by flipping
one boolean.

## Method

The same one that worked for the 37 -> 35 collapse, and the only one worth trusting:

1. `git -C build_output/src/device/nextbit/ether rev-parse HEAD^{tree}` — record the hash.
2. Reset the project to the vendored base commit.
3. `git am` the series with the folds applied.
4. Compare the tree hash. **It must be byte-identical.** If it is not, the fold changed behaviour and
   is wrong, however plausible it looked.
5. `refresh-patches.sh`, then `check-patch-series.sh` to confirm the pair count fell.
6. `kernel-rebuild.sh selinux_policy` for anything touching policy — 6 minutes, versus finding out two
   hours into a build. A first attempt at 0038 failed exactly that way.

Do it in the order below. Each step is independently verifiable, so a bad one can be abandoned without
unpicking the rest.

## Step 1 — the capability-advertisement family (6 of the 12 pairs)

`0004`, `0025`, `0026`(config half), `0035`, `0037` all argue about three booleans and which resource
directory holds them. Traced in full:

    config_device_wfc_ims_available
      0004  created true  in values-mcc310-mnc260/
      0025  created true  in values-mcc310-mnc240/   (Android picks the qualifier from the SIM)
      0035  deleted from both, created true in values/
      0037  flipped to false in values/

`config_device_vt_available` took the same path with an extra flip at 0026; `config_device_volte_available`
the same minus the flip. Fold into **one** patch stating the end state: the three booleans, unqualified,
in `values/config.xml`, plus the carrier legs in `vendor.xml`. Keep 0004's WPA supplicant half separate —
it is unrelated and only shares a patch by accident of timing.

While there, align `carrier_vt_available_bool`, which is still `true` in `vendor.xml` while
`config_device_vt_available` is `false`. Harmless today because `ImsManager` ANDs them, but the carrier
config claims a capability the device denies.

Removes pairs: 0025/0004, 0026/0004, 0035/0004, 0035/0025, 0035/0026, 0037/0004.

## Step 2 — split the two patches that do two things

Neither is a fold; both are the reason folds look harder than they are.

- **0026** ships the VT natives shim *and* turns video calling off. The shim belongs with the IMS
  infrastructure; the boolean belongs in step 1.
- **0032** moves the volume panel *and* finishes the CNE property work. Unrelated subsystems.

## Step 3 — the staged-development pairs

Each is a patch that created a placeholder and a later patch that filled it in. The end state is what
the series should say.

- **0021 and 0022 undo 0019** — 0019 ships stubs marked `DELIBERATELY EMPTY` and
  `UnsupportedOperationException("not bridged yet")`; 0021 generates the real AIDL surface and 0022
  implements the six sub-interfaces. Do **not** fold all three into one patch: the result is enormous
  and unreviewable. Instead restructure so 0019 ships only the parts that are final and 0021/0022 add
  new files rather than rewriting stubs. This is the largest and least urgent item.
- **0023 undoes 0018** — 0018 adds the IMS blob include, 0023 changes it to the guarded form. Fold: 0018
  should ship the final form.
- **0013 undoes 0012** — 0012 registers `libshims_ppd_poll`, 0013 changes that registration. Different
  subsystems otherwise (mm-pp-daemon vs the camera daemon), so do not squash the patches; move the
  final shim registration into 0012.
- **0036 undoes 0022** — one line: 0022 wrote `setProvisionedValue` as pure delegation, 0036 captures
  the return code to log refusals. Acceptable as-is. A later patch refining a method an earlier one
  created is the mildest form of this and folding a diagnostic into the bridging patch would muddy
  both. Leave it, and leave the note saying why.

## Step 4 — ordering, so related patches run together

Renumber into contiguous families. The current order is chronological, which scatters related work:
`0016` sets 320 dpi and `0027` sets the font scale for that panel, eleven patches apart.

    port foundation and device tuning      0001 port, turbo tuning, build tag, dpi + font scale, wallpaper
    display and camera fixes              JPEG rotation, mm-pp-daemon, camera mutex, HAL properties
    wifi and USB                          wcnss wakelock, adb enumeration, WPA supplicant overlay
    audio                                 ACDB calibration paths
    IMS and VoLTE infrastructure          modem bring-up, bridge, AIDL surface, blobs, nanopb, VT
                                          shim, IWLAN path, incoming-call delivery, config probe
    IMS capability advertisement          the single patch from step 1
    device features                       RobinLed + QS tiles, flashlight, volume panel, prebuilt apps
    sepolicy and properties               the three property/denial batches

Renumbering is textually large and semantically nil, so do it last and in one go, after the folds have
settled.

## Out of scope

`system/core` 0003 undoes 0001 over one line (`"Mode": "0755"`). One line in another project; fold it if
that project is being touched anyway, not as its own exercise.

## Target

12 pairs down to 1 (0036/0022, deliberately kept). 38 patches down to roughly 33, none of which
contradicts another, and related work adjacent.
