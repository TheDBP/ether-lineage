#!/usr/bin/env bash
# verify-volte-plan.sh — check every factual claim in VOLTE.md against the tree, the stock blobs and
# the bullhead reference. Prints PASS/FAIL per claim; exits non-zero if any fails.
#
#   ./verify-volte-plan.sh [--inventory DIR] [--bullhead DIR]
#
# Defaults assume the layout VOLTE.md describes: the extracted stock IMS blobs under
# $BUILD_ROOT/tmp/ims-inventory, and device_lge_bullhead under a sibling upstream-reference/.
#
# A checker that cannot fail is worth nothing: this one was negative-tested by pointing it at
# missing inputs, which is how C4d was found passing vacuously (an empty manifest dump has no
# intent-filter, so "has none" succeeded). It now requires the service element to exist first.
set -u
R="$(cd "$(dirname "$0")" && pwd)"
SRC="$R/build_output/src"
BUILD_ROOT="${BUILD_ROOT:-$R/build_output}"
W="${IMS_INVENTORY:-$BUILD_ROOT/tmp/ims-inventory}"
B="${BULLHEAD_DIR:-$(cd "$R/.." && pwd)/upstream-reference/device_lge_bullhead}"
while [ $# -gt 0 ]; do
  case "$1" in
    --inventory) W="$2"; shift 2 ;;
    --bullhead)  B="$2"; shift 2 ;;
    *) echo "!! unknown argument: $1" >&2; exit 2 ;;
  esac
done
A="$SRC/out/host/linux-x86/bin/aapt2"
MISSING="${IMS_MISSING:-$W/../ims-missing.txt}"
fail=0
ck(){ if [ "$2" = 1 ]; then printf '  PASS  %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# C1 transport
n=$(strings "$W/system/vendor/lib64/libril-qc-qmi-1.so" 2>/dev/null | grep -c 'qcril_qmi_ims_socket_agent')
ck "C1  libril-qc-qmi-1.so exports qcril_qmi_ims_socket_agent ($n)" "$([ "$n" -ge 3 ] && echo 1 || echo 0)"
z=$(unzip -l "$R/Ether_Stock_ROM_*.zip" 2>/dev/null | grep -ciE 'NON-HLOS|modem\.img')
ck "C1b no modem image in the stock zip (claim marked unverified)" "$([ "$z" -eq 0 ] && echo 1 || echo 0)"

# C2 inventory
miss=$(wc -l < $MISSING 2>/dev/null || echo 0)
ck "C2  58 missing IMS files ($miss)" "$([ "$miss" -eq 58 ] && echo 1 || echo 0)"
ent=$(grep -cvE '^\s*(#|$)' "$R/proprietary-files-ims.txt" 2>/dev/null || echo 0)
ck "C2b proprietary-files-ims.txt has 58 entries ($ent)" "$([ "$ent" -eq 58 ] && echo 1 || echo 0)"

# C3 carrier config patch
p=$(ls "$R"/overlay/patches/device/nextbit/ether/0004-*.patch 2>/dev/null | head -1)
n=$(grep -ciE 'mcc310|mnc260|volte|ims' "$p" 2>/dev/null || echo 0)
ck "C3  device patch 0004 carries IMS/carrier config ($n lines)" "$([ -n "$p" ] && [ "$n" -ge 10 ] && echo 1 || echo 0)"

# C4 pre-P shape
m=$("$A" dump xmltree --file AndroidManifest.xml "$W/system/vendor/app/ims/ims.apk" 2>/dev/null)
ck "C4  package org.codeaurora.ims"        "$(echo "$m" | grep -qc 'package="org.codeaurora.ims"' >/dev/null && echo "$m" | grep -q 'package="org.codeaurora.ims"' && echo 1 || echo 0)"
ck "C4b service runs in com.android.phone" "$(echo "$m" | grep -q 'process(0x01010011)="com.android.phone"' && echo 1 || echo 0)"
ck "C4c sharedUserId android.uid.phone"    "$(echo "$m" | grep -q 'sharedUserId(0x0101000b)="android.uid.phone"' && echo 1 || echo 0)"
# must find the service element first, or "no intent-filter" passes vacuously on an empty dump
has_svc=$(echo "$m" | grep -c 'E: service')
svc=$(echo "$m" | awk '/E: service/{f=1} f&&/E: intent-filter/{print "HAS"; exit} f&&/E: receiver/{exit}')
ck "C4d service exists AND has no intent-filter" "$([ "$has_svc" -ge 1 ] && [ -z "$svc" ] && echo 1 || echo 0)"

# C5 pre-P registration surface
s=$(strings "$W/system/vendor/app/ims/oat/arm64/ims.odex" 2>/dev/null)
ck "C5  odex references IImsService"       "$(echo "$s" | grep -q 'com/android/ims/internal/IImsService' && echo 1 || echo 0)"

# C6 compat path alive on 13
ck "C6  compat ImsService in frameworks/base" "$([ -f "$SRC/frameworks/base/telephony/java/android/telephony/ims/compat/ImsService.java" ] && echo 1 || echo 0)"
ck "C6b ImsServiceControllerCompat in opt/telephony" "$([ -f "$SRC/frameworks/opt/telephony/src/java/com/android/internal/telephony/ims/ImsServiceControllerCompat.java" ] && echo 1 || echo 0)"
ck "C6c MmTelFeatureCompatAdapter in opt/telephony"  "$([ -f "$SRC/frameworks/opt/telephony/src/java/com/android/internal/telephony/ims/MmTelFeatureCompatAdapter.java" ] && echo 1 || echo 0)"
ck "C6d ImsResolver still scans compat"   "$(grep -q 'compat ImsService' "$SRC/frameworks/opt/telephony/src/java/com/android/internal/telephony/ims/ImsResolver.java" 2>/dev/null && echo 1 || echo 0)"

# C7 bullhead citation
ck "C7  bullhead 5cef16f exists"          "$(git -C "$B" show -s --format=%s 5cef16f 2>/dev/null | grep -q 'Disable pre-P IMS stack' && echo 1 || echo 0)"
ck "C7b it only changed the blobs list"   "$(git -C "$B" show --stat --format= 5cef16f 2>/dev/null | grep -q 'lineage-proprietary-blobs-vendor.txt' && echo 1 || echo 0)"

# C8/C9/C10 bullhead material
ck "C8  bullhead init defines imsqmidaemon" "$(grep -q '^service imsqmidaemon' "$B/init.bullhead.rc" 2>/dev/null && echo 1 || echo 0)"
ck "C8b property trigger QMI_DAEMON_STATUS" "$(grep -q 'sys.ims.QMI_DAEMON_STATUS=1' "$B/init.bullhead.rc" 2>/dev/null && echo 1 || echo 0)"
ck "C9  bullhead sepolicy/ims.te exists"    "$([ -f "$B/sepolicy/ims.te" ] && echo 1 || echo 0)"
ck "C9b ims_socket + qcom_ims_prop types"   "$(grep -q 'type ims_socket' "$B/sepolicy/file.te" 2>/dev/null && grep -q 'type qcom_ims_prop' "$B/sepolicy/property.te" 2>/dev/null && echo 1 || echo 0)"
ck "C10 Android.mk IMS_SYMLINKS"            "$(grep -q 'IMS_SYMLINKS' "$B/Android.mk" 2>/dev/null && echo 1 || echo 0)"

echo
[ "$fail" -eq 0 ] && echo "RESULT: CLEAN" || echo "RESULT: $fail FAILURE(S)"
exit $fail
