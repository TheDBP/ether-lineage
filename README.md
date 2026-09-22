# Nextbit Robin — LineageOS 20.0 (Android 13)

Android 13 on the **Nextbit Robin** (`ether`, Snapdragon 808 / msm8992, 2016). LineageOS never
carried ether past 18.1, and the one 19.1 tree that existed was deleted from its host; this port
replays onto a copy of that tree recovered from Software Heritage (`vendored/`, also kept flat on
the `main` branch of [ether-trees](https://github.com/TheDBP/ether-trees)), and everything above it
is new.

**It boots and works.** WiFi, Bluetooth, camera, audio, adb, LTE data, SMS and visual voicemail all
function. No VoLTE — see *Known issues* for what is still open.

## What this build actually changes

The Robin spends most of its life pretending to be much slower than it is — and the LineageOS
device tree, not Nextbit, is mostly to blame. Nextbit's own ROM never throttled the A57 big cores on
die temperature and kept both online; the lineage-18.1 tree that every later port inherits starts
throttling them at **51 °C** and takes them offline at **52 °C**, temperatures the cluster reaches
almost immediately under load. Most of what the `turbo` tag means is going back to Nextbit's policy
with higher ceilings.

Sources: stock = Nextbit `Robin_Nougat_108` (`init.qcom.post_boot.sh`, `thermal-engine-8992.conf`,
boot ramdisk); 18.1 = the `lineage-18.1` device tree's values, carried unchanged by the recovered 19.1 tree this
port replays onto (`vendored/`);
turbo = this build (device patch 0002, kernel patches 0002/0004/0005). Same 3.10 kernel lineage
throughout.

| | stock Nougat | LineageOS 18.1 tree | turbo 20.0 |
|---|---|---|---|
| **Thermal** (`thermal-engine-8992.conf`) | | | |
| A57 frequency throttle (`SS-BIG-CLUSTER`, on `quiet_therm`, the board thermistor) | disabled; only a `pop_mem` 55 °C step-down, no cap | 51 °C → 864 MHz | 88 °C → 864 MHz (unreachable on a board sensor — effectively off) |
| A53 frequency throttle (`SS-LITTLE-CLUSTER`, on `quiet_therm`) | disabled; `pop_mem` 55 °C → 787 MHz | 54 °C → 787 MHz | 88 °C → 787 MHz (as big) |
| A57 core offlined (`HOTPLUG-CPU4` / `CPU5`) | 95 / 95 °C | 52 / 50 °C | never — `core_control` off |
| GPU throttle | step-down from 70 °C on the GPU sensor | 600→180 MHz ladder at 48–53 °C | same ladder at 72–87 °C |
| Battery charge-current throttle | 53 / 55 / 58 / 60 / 65 °C | 49 / 54 / 57 °C | 49 / 54 / 57 °C |
| **CPU** (`init.qcom.post_boot.sh` / `init.nbq.power.sh`) | | | |
| governor, both clusters | `interactive` | `interactive` | `interactive` |
| A53 `hispeed_freq` / `go_hispeed_load` | 960 MHz / 95 | 960 MHz / 90 | 960 MHz / 90 |
| A53 `target_loads` | `65 787200:75 960000:80` | `65 460800:75 960000:80` | `65 787200:75 960000:80` (stock) |
| A57 `hispeed_freq` / `go_hispeed_load` | 1248 MHz / 95 | 1248 MHz / 90 | 1824 MHz / 80 |
| A57 `target_loads` | `20 633600:70 960000:80 1248000:85` | `70 960000:80 1248000:85` | `20 633600:70 960000:80 1248000:85` (stock) |
| touch boost (`cpu_boost`) | 960 little + 960 big, 200 ms | 960 little only, 40 ms | 1248 little + 1824 big, 150 ms |
| A57 cores held online (`core_ctl min_cpus`) | 2 — both pinned | 0 — idle-parked | 2 — both pinned |
| `core_ctl offline_delay_ms` | 100 | 100 | 1 000 000 |
| `msm_thermal core_control` | on | on | off |
| HMP `sched_upmigrate` / `sched_downmigrate` | 95 / 80 (+ shadow 60 / 30) | 95 / 85 | 65 / 45 |
| **GPU** (`kgsl-3d0`) | | | |
| `default_pwrlevel` | 5 (180 MHz) | 5 (180 MHz) | 5 (180 MHz) |
| `msm-adreno-tz` jump-to-max gates (`BUSY_BIN` / `LONG_FRAME` / `CEILING`) | kernel default | 95 / 25 ms / 50 ms | 80 / 16.7 ms / 25 ms |
| **Memory** | | | |
| zram swap | 512 MB lz4, mounted | none | 768 MB, mounted |
| `vm.swappiness` / `vm.page-cluster` | 60 / 3 (kernel default) | 60 / 3 (kernel default) | 100 / 0 |
| lowmemorykiller | adaptive off, `minfree 18432…80640` | adaptive on, `vmpressure_file_min 81250` | as 18.1 |
| `dalvik.vm.heapgrowthlimit` / `heapsize` | 192m / 512m | 288m / 768m | 288m / 768m |
| **Kernel config** | | | |
| `RT_GROUP_SCHED` | (stock kernel) | on | off — `SCHED_FIFO` works inside cgroups |
| `MEMCG` / `BLK_CGROUP` | (stock kernel) | off | on |

Die protection is the same in all three and not in the table: per-core tsens rules (`SS-CPU0-1` …
`SS-CPU5`) at 85 °C, `pop_mem` at 80 °C in the two LineageOS columns (55 °C on stock), and behind
them the kernel's own `msm_thermal` backstops, which no config can switch off: 100 °C forces the
A57s to 768 MHz, 115 °C resets the SoC. The `quiet_therm` rows above are a board thermistor, i.e.
skin temperature; the A57 `target_loads` row is the one where 18.1 hurt most — with both big cores
pinned online and tasks migrated to them early, a 384–633 MHz A57 (slower than an A53 at 960) had to
reach 70 % load before it would move.

Unchanged in all three and not worth a row: A53/A57 `scaling_min_freq 384 MHz`, no max cap,
`timer_rate 20000`, `min_sample_time 40000`, `above_hispeed_delay 19000`, `io_is_busy 1`, cpubw
`bw_hwmon` / mincpubw `cpufreq`, `read_ahead_kb 128`, kernel default I/O scheduler (`noop` — the
`sys.io.scheduler=bfq` prop has no consumer).

`msm_thermal` `core_control` is off entirely, not just raised to 90 °C: this kernel deletes a
CPU's `cpufreq/` directory when the core goes offline, so an in-flight `time_in_state` read blocks in
uninterruptible sleep while BatteryStats holds its global lock, and the watchdog kills system_server.
thermal-engine mitigates by capping frequency instead.

The zram row is not a preference. Nextbit shipped 512 MB of swap; the LineageOS tree dropped it,
and AOSP stopped calling `swapon_all` from `init.rc` anyway, so nothing this tree declared would have
mounted. On a 3 GB phone, the alternative to swap is killing processes.

Beyond the tuning, this build restores or adds:

- **The rear LED cluster.** `RobinLed` pulses the rear "cloud" LEDs at a rate scaled to how many
  notifications are waiting, and doubles as a charge gauge. The lights HAL gives the rear cluster up
  so there is exactly one writer to it. The stock boot chase runs again too: Android 13 refuses a
  vendor rc that triggers on `init.svc.bootanim`, so that action now lives in a system rc.
- **Correct still photos.** The stock HAL asks the JPEG encoder to rotate, which that encoder cannot
  do, so captures fell back to software and came out with the sensor's dimensions transposed and the
  frame repeated in bands. Preview was always correct, which is what made it look like a working
  camera.
- **adb over USB**, on a kernel with no FunctionFS AIO — which is otherwise impossible.
- **Fulguris, F-Droid and K-9 Mail**, each on its own switch; and **the Nextcloud bundle** — Files,
  Talk, push, Deck, Passwords, Notes, CalDAV/CardDAV and Tasks — for the phone that was sold on
  living in the cloud.
- **The Robin's look** — the Nextbit teal (#009D94) as the system accent, seeded as a Monet preset
  so it survives wallpaper changes; nav-bar glyphs redrawn as scalable tintable vectors (recreations,
  not extracted artwork, so they ship on every build); a hotseat-only home screen; no Google feed
  page; themed icons; dark theme by default; NFC and LiveDisplay tiles in Quick Settings.
- **Optionally the phone's own assets** — the original Nextbit sounds, wallpapers and boot animation,
  reclaimed at build time from your own copy of the stock ROM. Off unless you ask for it.

## Status

| | |
|---|---|
| WiFi | connects, DHCP, internet |
| Bluetooth | enables and stays on |
| Camera | captures correctly; front/back switch is immediate |
| Audio | working |
| LEDs | rear cluster: notification pulse, charge gauge, boot chase |
| LiveDisplay | colour calibration works; monochrome mode has no visible effect |
| adb | USB (wireless via Developer options, as stock) |
| Cellular | LTE data, SMS, visual voicemail (T-Mobile US); no VoLTE or Wi-Fi calling — see *Known issues* |

Branches: `lineage-20.0` (this, released), `lineage-20.0-volte` (VoLTE plan and inventory, `VOLTE.md`),
`lineage-21.0` (in progress), `main` (landing page). This repo's own `lineage-18.1` and
`lineage-19.1` attempts were never finished and are gone; nothing in them is coming forward.

**20.0 ships first; 21 follows straight after, and 21 is the end of the line.** LineageOS 22 needs a
kernel of at least 4.19 (`NetBpfLoad` exits on anything older) and the Robin's is 3.10. The scoping
for 21 is `PLAN.md` on the `lineage-21.0` branch.

## The one thing to understand

Nearly every bug on this port had the same root cause: **a 2016 kernel meeting a 2022 userspace**.
Android 13 assumes a kernel far newer than 3.10, and each assumption failed differently:

| assumed | arrived in | what broke |
|---|---|---|
| cgroup v2 | Linux 4.5 | `libprocessgroup` — nothing booted |
| `bpf()` syscall | Linux 3.18 | netd crash-loop, then `system_server` aborting repeatedly per boot |
| `IFA_FLAGS` netlink attribute | Linux 3.14 | **WiFi** — every address notification silently discarded |
| FunctionFS AIO | Linux 3.15 | USB adb impossible |
| RT bandwidth per cgroup | — | `SCHED_FIFO` unavailable system-wide; Bluetooth aborted |

Full account in **[PORT-LOG.md](PORT-LOG.md)**.

## Known issues

- **No VoLTE, no Wi-Fi calling.** LTE data, SMS and visual voicemail work; voice needs 2G/3G
  fallback, which T-Mobile and AT&T no longer provide. The modem has an IMS stack and a T-Mobile
  config, and the stock 7.1.1 zip ships the QTI IMS userspace (`org.codeaurora.ims`, `ims*daemon`,
  `lib-ims*`), but that ImsService is the pre-Android-9 `ServiceManager("ims")` kind, which 13
  has no binding path for. Plan in `VOLTE.md` on branch `lineage-20.0-volte`.
- **Flashlight does not work.** The torch toggle has no effect. Not yet diagnosed.
- **`CNEService` crashes on every Wi-Fi/mobile transition.** Android 7 blob calling
  `INetworkPolicyManager.getNetworkQuotaInfo`, removed in 12. Restarts itself; nothing depends on it.
  Fix: drop the APK from `proprietary-files.txt`, keep `cnd`.
- **LiveDisplay monochrome does nothing.** Colour calibration works; the monochrome toggle has no
  visible effect.
- **`use_sched_load` reads back 0** after the tuning writes 1, on both clusters, also when written
  by hand as root. Harmless.
- **`vendor.qcom.PeripheralManager` never registers.** Nothing depends on it.

## Installing

Prebuilt images are on the [Releases](https://github.com/TheDBP/ether-lineage/releases) page, as
the `libre` preset and, from the same build, `clean`:

- `libre` — LineageOS plus F-Droid, Fulguris, K-9 Mail, KDE Connect, TermOne Plus, ConnectBot,
  Linphone and the Nextcloud
  bundle (Files, Talk, NextPush, Deck, NC Passwords, Notes, DAVx5, Tasks). The Robin was sold as
  the cloud-first phone; this is that, pointed at a server you own.
- `clean` — LineageOS with only the shared defaults, nothing bundled.

Neither has Google apps, root, or any of Nextbit's own artwork.

You need: a Robin on stock Nougat (`Robin_Nougat_108` or later) or on LineageOS 18.1 — both
tested; other starting points untested — and `adb` and `fastboot` from Android platform-tools. Each
preset is two files: the ROM zip and a `<name>-recovery.img` (Lineage recovery from the same build)
— no TWRP. Everything on the phone is erased.

1. **Unlock the bootloader** (skip if already unlocked). Settings → About → tap *Build number* five
   times; Developer options → enable *OEM unlocking* and *USB debugging*. Then
   `adb reboot bootloader` and `fastboot oem unlock`, confirm on the phone. The phone wipes itself
   and reboots.
2. **Flash and boot the recovery.** Back in the bootloader (`adb reboot bootloader`, or hold
   Volume Down while powering on):
   `fastboot flash recovery lineage-20.0-<date>-UNOFFICIAL-turbo-libre-ether-recovery.img`, then
   `fastboot boot lineage-20.0-<date>-UNOFFICIAL-turbo-libre-ether-recovery.img` (the
   `turbo-clean` one for that preset). (This bootloader ignores `fastboot reboot recovery` and boots the system; boot the image directly.)
3. **Factory reset.** *Factory reset → Format data / factory reset*. Required coming from stock or
   another ROM, and again on any update that changes signing keys.
4. **Sideload the ROM.** *Apply update → Apply from ADB*, then on the computer
   `adb sideload lineage-20.0-<date>-UNOFFICIAL-turbo-libre-ether.zip`. Signature verification
   takes about a minute before the install starts.
5. **Reboot** to system. First boot takes about a minute; the rear LEDs chase while the animation
   plays. A lingering animation with no chase means something is wrong, not slow.

Updating from one of these builds to a newer one: `adb reboot recovery`, step 4, reboot; no wipe.
The zip does not write the recovery partition — repeat step 2 with the new image if you want the
recovery from the same build.

Want Google apps or root? Build the `full` preset yourself (below); those images are not
published.

## Building

One command, one image. Start with `clean` — it needs no inputs beyond the source.

```sh
PRESET=clean ./forge/bootstrap.sh    # plain LineageOS + the tuning, nothing proprietary
PRESET=libre ./forge/bootstrap.sh    # + F-Droid, Fulguris, K-9, the Nextcloud bundle, still no Google
PRESET=full  ./forge/bootstrap.sh    # + GApps, root, Fulguris, F-Droid, K-9, the Nextcloud bundle
PRESET=robin ./forge/bootstrap.sh    # the Nextbit look and root, no Google
```

Output lands in `build_output/src/out/target/product/ether/`.

`PRESET` names a saved set of options; `OPTIONS="root nav-icons"` picks them directly. `OPTIONS`
**replaces** the list rather than adding to it — `COMMON_OPTIONS` is not merged in, so an ad-hoc set
is the whole set.

Options live in the forge (`forge/options/`) and work the same on every device. What lives in this
repo's `overlay/patches/` is only what is true of this phone.

To publish a build use `./forge/tools/release.sh` rather than uploading a zip by hand — it refuses
anything carrying GApps or reclaimed manufacturer assets, and checks the image rather than the label.
See [rom-forge docs/RELEASING.md](https://github.com/TheDBP/rom-forge/blob/main/docs/RELEASING.md).

## Presets

One build command produces one image. A preset is a saved selection of options — it has no
behaviour of its own.

| preset | tag | adds over `clean` |
|---|---|---|
| `clean` | `turbo-clean` | nothing — this is the baseline |
| `libre` | `turbo-libre` | `fdroid`, `fulguris`, `k9`, `termoneplus`, `kdeconnect`, `nextcloud`, `connectbot`, `linphone` |
| `robin` | `turbo-robin` | `oem`, `root` |
| `full` | `turbo` | `fdroid`, `fulguris`, `gapps`, `k9`, `termoneplus`, `kdeconnect`, `nextcloud`, `connectbot`, `linphone` |

Every preset also carries the shared set, which is what makes this build look and behave the way
it does regardless of which preset you pick:

`advanced-restart` `dark-default` `google-feed-off` `home-defaults` `linux` `livedisplay-off` `minimal-home` `nav-icons` `nfc-off` `setupwizard-lineage` `setupwizard-nag-skip` `teal-skin` `teal-wallpaper` `themed-icons`

`oem` is in no preset. `EXTRA_OPTIONS` adds an option to whichever preset you build, and every
option added that way appends its name to the tag:

```sh
EXTRA_OPTIONS=oem PRESET=full ./forge/bootstrap.sh      # tag turbo-oem
```

Set `EXTRA_OPTIONS="oem"` in `device.conf.local` (gitignored) to get it on every build from this
checkout. Those images carry reclaimed manufacturer assets and are for your own phone.

## Options

Every option this device uses, and what each one does. They live in `forge/options/`, so they
work on any device rather than being wired into this tree.

| option | what it does |
|---|---|
| `advanced-restart` | Advanced restart in the power menu |
| `dark-default` | Default to dark theme |
| `fdroid` | F-Droid app store + Privileged Extension (silent installs/updates) |
| `firefox` | Firefox (Fennec F-Droid) as the browser, replacing Jelly — still available, but 320 MB staged, so no preset carries it now |
| `fulguris` | Fulguris as the browser, replacing Jelly — a WebView browser, 9 MB where Fennec stages 320 MB |
| `connectbot` | ConnectBot: an SSH client with saved hosts, keys and port forwarding |
| `linphone` | Linphone: a SIP client, for voice over data where the device has no VoLTE |
| `gapps` | Google apps: Play Store and GMS from MindTheGapps, plus Google's versions of the stock apps |
| `google-feed-off` | Google feed (-1 screen) off by default |
| `k9` | K-9 Mail (the Thunderbird for Android codebase) as the mail client |
| `nextcloud` | Nextcloud bundle: Files, Talk, NextPush, Deck, NC Passwords, Notes, DAVx5, Tasks — the current F-Droid build of each, fetched at build time |
| `kdeconnect` | KDE Connect: phone <-> desktop notifications, clipboard, files, remote input |
| `home-defaults` | Home screen defaults: no icon labels, no auto-add |
| `linux` | On-device Linux environment (chroot + Docker): container kernel config; the cgroup symlink patch is off here (3.10 predates kernfs) |
| `livedisplay-off` | LiveDisplay off by default |
| `minimal-home` | Minimal home screen: hotseat only, no second page |
| `nav-icons` | Nextbit Robin style nav-bar icons, drawn as scalable tintable vectors |
| `nfc-off` | NFC off by default |
| `oem` | The manufacturer's own boot animation, wallpapers and sounds, reclaimed from its stock ROM |
| `root` | Magisk baked into the boot image, so the zip flashes pre-rooted |
| `setupwizard-lineage` | Use Lineage SetupWizard over Google's (WITH_GAPPS) |
| `setupwizard-nag-skip` | Skip recovery/metrics/backup setup pages |
| `teal-skin` | Teal accent — fixed #009D94 Monet preset seed |
| `teal-wallpaper` | Teal-shag default wallpaper (baked into framework-res) |
| `termoneplus` | TermOne Plus terminal emulator |
| `themed-icons` | Themed (monochrome) app icons on by default |

## Device patches

50 patches across 18 upstream projects, applied at build time from `overlay/patches/`. Nothing
here is a fork: each is a single commit against the upstream tree, replayed on every build, so
upstream stays upstream and what we changed stays legible. One patch per thing it enables. Each entry
below: what broke → what the patch does → what it costs.

### `build/make`

- **build: warn instead of failing on a presigned APK with compressed libs** — the compression
  check ran on the copy-verbatim path and, on failure, pushed a presigned APK onto the rewriting
  path, which broke its v2 signature; PackageManager then dropped it silently at boot (no Firefox,
  no F-Droid, no Contacts, two dead dock tiles). Warn and copy verbatim: an APK with
  `extractNativeLibs=true` is entitled to compressed libs.

### `build/soong`

- **soong: expose `preprocessed` on `android_app_import`, so a presigned APK ships untouched** —
  uncompressing libs/dex and zipaligning rewrote the archive and invalidated the whole-file v2
  signature (Firefox 127 MB → 242 MB, Sig Block gone, not installed). Backports the later Soong
  property so the file is installed byte-for-byte.

### `device/lineage/sepolicy`

- **sepolicy: exclude pre-UM platforms from the `vendor_` m4 renames again** — 20.0 dropped the
  filter, so msm8992 got a half-rename (`vendor_hal_perf_default_exec` unknown) and the policy did
  not compile. Restores the 19.1 exclusion list; the deleted `qcom/legacy-vendor` dir is not
  restored because its only rule names a `pps` type 20.0 lacks.

### `device/nextbit/ether`

- **0001 Android 13 port — drop what 20.0 removed, pick the OSS WCNSS client** — modules 20.0
  deleted or folded (`audio.a2dp.default`, Snap, cryptfshw, `libhidltransport`,
  `libcnefeatureconfig`, the local libhidl shim, dead manifest entries) each failed the build or
  boot. Removes them; sets `WCNSS_QMI_OSS` because 20.0's `wcnss-service` no longer falls back to
  the open-source path and would link proprietary QMI libs this tree lacks.
- **0002 turbo tuning — thermal ceilings, big-cluster governor, real zram swap** — what the tag
  means; values in the table above. Restores Nextbit's ladders where 18.1 was more conservative
  than stock; `swapon_all` is called from `init.qcom.rc` because AOSP's `init.rc` stopped doing it
  and the declared 768 MB zram never mounted; perfd's sepolicy rule lives here because without it
  the scheduler tuning silently does not apply.
- **0003 sepolicy for modem bring-up, wifi, LiveDisplay and logging** — 2016 blobs against a 2022
  policy: rild/qmuxd, netmgrd/wcnss_service property access, LiveDisplay → mm-pp-daemon, and their
  file/property contexts. Denials were silent (no modem, no LiveDisplay, no logs). vendor_init's
  rule is the compilable subset — the original named a type 20.0 lacks.
- **0004 carrier config for T-Mobile US, and a WPA supplicant the WCNSS firmware can finish** —
  IMS switches (VoLTE/VT/Wi-Fi calling) via a carrier overlay scoped to MCC/MNC 310/260; inert
  until an ImsService exists (*Known issues*). PMF disabled in the supplicant overlay: the WCNSS
  firmware negotiates it, then cannot complete the 4-way handshake.
- **0005 stop asking the JPEG encoder to rotate — it cannot** — `needJpegRotation()` returned true
  unconditionally; the hardware encoder refused, the software fallback transposed the dimensions
  and banded the frame. Rotation is already covered by `CAM_QCOM_FEATURE_ROTATION` in the CPP.
- **0006 RobinLed — the rear cloud LED as a notification and battery indicator** — a
  NotificationListener that pulses at a rate scaled to outstanding notifications and shows charge
  level; liblight gives the rear cluster up so there is one writer. The boot chase moves to a
  system rc because A13 drops vendor-rc triggers on `init.svc.bootanim`, and writes the resolved
  sysfs path because init cannot read the `sysfs_leds`-labelled link.
- **0007 Firefox and F-Droid prebuilt modules, each on its own switch** — gated on the forge
  option (`WITH_FIREFOX` / `WITH_FDROID`) and on the APK being present, so a stale APK never leaks
  into a build and a missing one never fails the parse. Firefox overrides Jelly; it is no longer
  tied to `WITH_GAPPS`.
- **0008 default wallpaper via `ro.config.wallpaper`, OEM pack overrides it** — the property points
  at whatever the wallpaper option staged, sidestepping the framework-res RRO not reaching first
  boot. No option: unset, upstream default. `WITH_OEM`: points at `OEM_DEFAULT_WALLPAPER`.
- **0009 QS tile layout and RobinLed listener access** — NFC and LiveDisplay tiles in the default
  QS layout (fresh install only); auto-granted listener access for `com.nextbit.robinled`. Accent
  overlay dropped (Monet preset via `teal-skin` instead); dead DeskClock widget override dropped;
  no theme default here (the forge's `dark-default` sets it in `frameworks/base`, and a device
  overlay would silently win).
- **0010 tag the build turbo (`TARGET_UNOFFICIAL_BUILD_ID`)** — "turbo" in the zip name and
  `ro.lineage.version`; `TURBO_BUILD_ID` overrides it per preset.
- **0011 bring the modem up, and stop rild crashing on the way** — no working peripheral manager.
  (a) The 2016 `libperipheral_client.so` stack-allocates two `Parcel`s at 2016's `sizeof`; the
  current one is larger and the store hits the stack canary, so rild aborted on every start. A shim
  scoped to `libril-qc-qmi-1.so` returns failure from the five `pm_client_*` entry points, which the
  RIL handles by skipping ESOC setup the internal modem does not need. (b) Nothing called
  `subsystem_get("modem")`; `ether_modem_hold` (class core) opens and holds `/dev/subsys_modem`
  — rild cannot, it is uid radio and the node is 0640 system — so PIL loads the firmware and
  `smdcntl0`/qmux appear.
- **0012 stop mm-pp-daemon spinning a core on an uninitialised poll fd** — the daemon polls two
  descriptors and initialises one; `POLLNVAL` returns at once, ~6700 calls/s, 98 % of a core from
  boot (stock has the same bug). Shim rewrites fds that `fcntl()` rejects with `EBADF` to -1.
  Injected via `TARGET_LD_SHIM_LIBS` on `libdisp-aba.so` with `-z global` so it precedes libc;
  `LD_PRELOAD` is ignored under `AT_SECURE` after the domain transition.
- **0013 stop the camera daemon aborting on a double mutex destroy** — the ISP blob destroys a
  mutex twice; A7 bionic returned an error, A13 bionic aborts (eight tombstones a boot). Shim
  scoped to `mm-qcamera-daemon` makes `pthread_mutex_destroy` a no-op — safe, the struct is
  caller-owned with nothing to leak. Cost: real mutex misuse in that one daemon goes unreported.
- **0014 enumerate once when switching USB to adb** — `init.nbq.usb.rc` duplicated AOSP's
  `sys.usb.config=adb` block (configfs is 0 here), so every switch enumerated twice (18d1:4EE7 then
  2C3F:0009) with a full adbd transport tear-down between. Device copy removed; mtp/ptp/rndis/midi/
  diag stay, they have no AOSP counterpart.
- **0015 let wcnss_filter hold a wakelock** — `/sys/power/wake_lock` needs `CAP_BLOCK_SUSPEND`;
  sepolicy allowed it, the rc never asked. Every acquire failed EPERM (~1/s) and BT traffic could
  not keep the SoC awake. `capabilities BLOCK_SUSPEND` on the service.
- **0016 420 dpi** — the 5.2" 1080p panel is 424 dpi; upstream's 480 rendered a size too large.
  420 is the nearest bucket, xxhdpi assets still apply.
- **0017 let the gatekeeper and composer HALs read the properties they poll** — gatekeeper reads a
  `system_prop` at startup; denied, `IGatekeeper/default` never registers and `system_server` waits
  forever (boot animation with no crash). The composer HAL polls the bootanim property; denied reads
  spin at hundreds per second for the whole hang.

### `frameworks/base`

- **hwui: never block a binder thread on the RenderThread's draw lock** — launcher/SystemUI froze
  for exactly 4 s. This Adreno lacks `EGL_EXT_buffer_age`, so RenderThread dequeues inside `draw()`
  under `mFrameMetricsReporterMutex`; SurfaceFlinger's oneway `onTransactionCompleted` blocked on
  that lock on a binder thread, never sent `BC_FREE_BUFFER`, and the binder driver parked every
  later oneway — including the release RenderThread was waiting for — until the 4000 ms dequeue
  timeout. `onSurfaceStatsAvailable` now posts to the RenderThread. Invisible on drivers that
  dequeue in `getFrame()`, which is why upstream never saw it.
- **SystemUI: tolerate a null list from `getPackagesForOps`** — `AppOpsService` returns null on a
  first boot after a wipe; SystemUI NPE'd three times in `KeyguardService.onCreate`.

### `frameworks/libs/net`

- **bpf: do not abort when a pinned map cannot be opened** — no `bpf()` syscall on 3.10, so the
  `BpfMap` pinned-path constructor aborted `system_server` the first time anything asked for
  interface stats (fifteen restarts a boot, then RescueParty). Leaves the fd invalid so the
  existing `isValid()` checks run. `createMap()` still aborts. Cost: no per-UID accounting, no BPF
  firewall.
- **netlink: do not require `IFA_FLAGS`, which predates Linux 3.14** — the parser rejected every
  `RTM_NEWADDR` from a 3.10 kernel, so IpClient never saw the address, provisioning never
  completed, and WiFi dropped after 18 s holding a valid lease. Falls back to the 8-bit flags in
  `ifaddrmsg`. This was the actual WiFi blocker.

### `frameworks/native`

- **binder: ignore a threadpool shrink instead of aborting** — the passthrough audio HAL configures
  a pool of 16, then the A11 vendor HAL asks for fewer; `setThreadPoolMaxThreadCount` treated the
  shrink as fatal, `IDevicesFactory` never registered, and the watchdog killed `system_server` on
  the boot animation. Keeps the larger bound (a few idle threads).

### `hardware/qcom-caf/msm8994/display`

- **msm8994 display: drop libbfqio (removed from LineageOS after 18.1)** — the HAL still linked the
  compat shim and ckati failed (`hwcomposer.msm8992 missing libbfqio`). Same change upstream made
  for msm8996. Cost: the vsync thread loses realtime IO priority.

### `kernel/nextbit/msm8992`

- **0001 uapi: drop the `sockaddr_storage` alias that collides with A13 bionic** — A13's bionic
  declares the struct itself, so the exported header's alias became a redefinition and
  `libbt-vendor` would not compile. Alias removed as upstream Linux later did; `#ifndef __KERNEL__`,
  so the kernel is unaffected.
- **0002 enable the memory and blkio cgroup controllers** — A13 libprocessgroup mounts both at early
  init; neither was in the defconfig (18.1 never needed them).
- **0003 give pmsg more of the 2 MB pstore reservation** — 512 K pmsg wrapped after two boot-loop
  cycles and lost the first crash. Raised to 832 K from spare dump-record space; ftrace left at 64 K
  (a zero-size zone is an untested path in this driver).
- **0004 disable `RT_GROUP_SCHED` so `SCHED_FIFO` works in cgroups** — child cgroups default to
  zero RT runtime, so no Android process could use `SCHED_FIFO`; Bluetooth aborted in
  `timer_create` on every enable (camera-daemon was in the same position). What current Android
  kernels do.
- **0005 let the GPU governor react to UI, not just sustained 3D** — msm-adreno-tz's jump-to-max
  needed >95 % busy, >25 ms frames, 50 ms accumulated: game constants. Measured 30 s of UI: 69.7 %
  at 180 MHz, 0 % above 367 MHz, dropping frames. Now 80 % / one vsync / 25 ms; 180 MHz floor
  unchanged.

### `packages/modules/Bluetooth`

- **Bluetooth: allow disabling the LE vendor capabilities query** — old WCNSS controllers echo
  vendor HCI opcodes with the OGF dropped; HciLayer's strict match aborted on every enable once
  APCF commands started. `bluetooth.core.le.vendor_capabilities.enabled=false` skips the query.
  Cost: no offloaded scan filtering or batch scanning; alternative was no Bluetooth.

### `packages/modules/Connectivity`

- **0001 tolerate a kernel with no eBPF instead of crash-looping netd** — 19.1's netd fallback
  re-homed: A13 moved socket tagging here. `BpfHandler::init()` probes instead of requiring; on
  failure `tagSocket`/`untagSocket` return 0. No legacy qtaguid path exists on A13 to fall back to.
  Cost: no per-UID data usage, no BPF firewall, no tethering offload.
- **0002 do not throw on ENOSYS from a kernel with no eBPF** — `maybeThrow()` turned every ENOSYS
  (113 a boot) into a `ServiceSpecificException` that unwound network setup before
  `networkCreate()`; WiFi got a lease and never provisioned. Log and continue.
- **0003 report empty stats, not an error, when there is no eBPF** — fourth layer: the stats parser
  turned ENOSYS into `IOException` → `IllegalStateException` out of `updateLinkProperties()`, same
  symptom. Both parse entry points return 0 with no stats.

### `packages/modules/adb`

- **adb: a USB path that works on a kernel without functionfs AIO** — 3.10 has no FFS AIO, so
  adbd's default connection submitted reads that never completed ("unauthorized" forever). Restores
  a blocking `UsbFfsBlockingConnection` behind `BlockingConnectionAdapter` (own reader/writer
  threads, so a host that stops draining never blocks the fdevent loop); treats a zero-length bulk
  read as framing, not EOF; closes by signalling each blocked thread until it leaves its syscall
  (`sigaction` without `SA_RESTART`, `unix_read_interruptible`/`adb_writev`, because the wrappers
  retry on EINTR). This f_fs returns ENODEV after a DISABLE until reopened, so every enumeration is
  a fresh transport.

### `packages/services/Telephony`

- **Revert "Restrict USSD requests to the subscription's associated user."** — upstream 20.0
  applied it without its `frameworks/base` half (`checkSubscriptionAssociatedWithUser` does not
  exist on A13), so every lineage-20.0 build fails to compile. Backporting would drag in the A14
  subscription-to-user API. No security impact: the API it guards does not exist on 13.

### `system/bpf`

- **0001 bpfloader: do not reboot when bpfloader fails on a kernel without eBPF** — the 19.1
  one-liner, rebased past an A13 comment block that broke the context.
- **0002 bpfloader: publish `bpf.progs_loaded` even when the kernel has no eBPF** — the 19.1
  `break` still applied cleanly but A13 added a map self-test after it that returns before
  `SetProperty`, so every `waitForProgsLoaded()` caller hung and the device sat on the boot
  animation. Self-test gated behind `bpfUnsupported`; untouched on hardware with eBPF.

### `system/core`

- **0001 libprocessgroup: describe a cgroup-v1-only layout for msm8992** — 3.10 cannot mount
  `cgroup2`; the v2 root in `cgroups.json` failed and ueventd died 3.5 s in
  (`bootstrap-apexd-failed`). v2 root dropped; `freezer` re-declared as an Optional v1 controller
  at `/dev/freezer`. `/vendor/etc/cgroups.json` cannot do this — it merges, it cannot remove.
- **0002 libprocessgroup: treat a missing cgroup hierarchy as a no-op, not an error** — with the
  path empty, `createProcessGroup` tried `/uid_0` on the read-only rootfs and service start is
  fatal on that error. Return success when nothing is configured.
- **0003 libprocessgroup: give recovery a cgroup-v1-only profile too** — `cgroups.recovery.json`
  declared only the v2 root, so recovery could not boot at all (ueventd exited 4×, `InitFatalReboot`).
  v2 root dropped, `cpuset` declared Optional v1.
- **0004 libprocessgroup: signal the process group when there is no cgroup hierarchy** — the
  empty-path shortcut treated every service as already dead, so `stop`/`restart` were no-ops; in
  recovery adbd never released the FFS endpoints and sideload failed with `EBUSY`. Signals the
  process group directly (init gives every service its own).

### `system/netd`

- **0001 netd: restore the Android 11 no-eBPF fallback (A13 half)** — `BandwidthController` builds
  the legacy `xt_owner`/`xt_qtaguid` rules when BPF is absent instead of referencing pinned
  objects that do not exist (iptables-restore failed wholesale, netd exited). Probes for
  `XT_BPF_ALLOWLIST_PROG_PATH` directly; netd has no `TrafficController` on A13 to ask.
- **0002 netd: do not exit when there is no cgroup v2 root** — `main.cpp` exited before
  `libnetd_updatable_init()`, so the Connectivity degradation never ran: 107 restarts in ten
  minutes, framework never finished booting. `cg2_path` left empty and passed through.

### `vendor/lineage`

- **0001 lineage: restore `B64_FAMILY` (msm8992/msm8994) for the ether port** — 20.0 removed the
  pre-UM families, so `QCOM_HARDWARE_VARIANT` fell back to msm8992 (no such CAF dir) and every
  msm8994 CAF module vanished (`missing libstagefrighthw / libqdMetaData`). Restores the family,
  variant, `TARGET_USES_QCOM_BSP` and `GRALLOC_USAGE_HW_2D`; not `TARGET_USES_QCOM_BSP_LEGACY`
  (no references remain).
- **0002 lineage: add msm8992/msm8994 to `QCOM_BOARD_PLATFORMS`** — `is-vendor-board-platform`
  lives in a different file; without it modules gated on it are never defined and the only symptom
  is "non-existent modules in PRODUCT_PACKAGES" (`libbt-vendor`, `power-service-qti`).
- **0003 soong: create `generated_kernel_includes`' genDir before running `headers_install`** —
  RuleBuilder `rm -rf`s the genDir and never recreates it, so the kernel's `cd $(KBUILD_OUTPUT)`
  check fails. `mkdir -p` first; path stays absolute because `make -C` chdirs.
- **0004 lineage: restore `-fuse-ld=lld` in `HOSTCFLAGS` for pre-4.18 kernels** — `ld` is not on
  the sbox PATH; 20.0 sets lld only in `HOSTLDFLAGS`, which Kbuild ignores for single-file host
  tools like `fixdep`. 19.1 set both; 3.10 needs both.

### `vendor/qcom/opensource/power`

- **power: make the msm8992 duration constants file-local** — 20.0 added
  `kMaxLaunchDuration`/`kMaxInteractiveDuration` to `power-common.c` while every per-SoC file still
  defines its own; duplicate symbol at link. `static` in `power-8992.c` (latent for seven other
  legacy SoCs; only this one is patched).

## Layout

| | |
|---|---|
| `device.conf` | what this device is, and its presets |
| `overlay/patches/` | patches for this phone, one per feature |
| `overlay/local_manifests/` | extra projects the manifest does not carry |
| `vendored/` | trees whose upstreams are deleted, recovered from Software Heritage: the 19.1 device tree the patches apply to, and the pre-rename qcom `sepolicy-legacy` — see `vendored/README.md` |
| `forge/` | the shared build engine, vendored (do not edit here) |
| `PORT-LOG.md` | how the port was done and what was measured |

The upstream trees this port depends on that are at risk of disappearing are kept at
[ether-trees](https://github.com/TheDBP/ether-trees): the 18.1 kernel, device tree and CAF HALs
as full-history mirror branches, the recovered 19.1 device tree and `sepolicy-legacy` flat on
`main`. No proprietary blobs are mirrored.

## Support

This is unpaid work on phones their makers abandoned. If a build saved one from the drawer, [a donation](https://www.paypal.com/donate/?hosted_button_id=7U8PDZLK7742Q) keeps the next one coming.

## License

Apache-2.0 — see `LICENSE`. The patches under `overlay/patches/` modify Apache-2.0 (AOSP/LineageOS) and GPL-2.0 (kernel) code and carry those licenses; `vendored/` keeps its upstream licenses.

The kernel in every published image is GPL-2.0. Its complete corresponding source is the
`mirror/android_kernel_nextbit_msm8992/lineage-18.1` branch of
[ether-trees](https://github.com/TheDBP/ether-trees) with the five patches under
`overlay/patches/kernel/nextbit/msm8992/` applied on top.
