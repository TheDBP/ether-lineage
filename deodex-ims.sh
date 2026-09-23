#!/usr/bin/env bash
# deodex-ims.sh — turn the stock ims.odex back into editable smali, and report the framework
# surface the APK expects. Step 1 of the VoLTE plan in VOLTE.md.
#
#   deodex-ims.sh <stock-rom.zip> <workdir>
#
# ether ships ims.apk dex-stripped: 27 KB of manifest with the 2.3 MB of code in an arm64 odex
# beside it. Importing the apk alone installs a shell with no code, so the apk has to be rebuilt
# from the odex before any of it can run.
#
# Needs a JDK and the baksmali/smali jars, which the Android tree already carries at
# prebuilts/extract-tools/common/smali/. Point SMALI_DIR elsewhere to override.
set -u

ZIP="${1:?usage: deodex-ims.sh <stock-rom.zip> <workdir>}"
W="${2:?usage: deodex-ims.sh <stock-rom.zip> <workdir>}"
SMALI_DIR="${SMALI_DIR:-build_output/src/prebuilts/extract-tools/common/smali}"
[ -f "$ZIP" ] || { echo "!! no such zip: $ZIP" >&2; exit 1; }
BK="$SMALI_DIR/baksmali.jar"; SM="$SMALI_DIR/smali.jar"
for j in "$BK" "$SM"; do [ -f "$j" ] || { echo "!! missing $j (set SMALI_DIR)" >&2; exit 1; }; done

mkdir -p "$W/in" || exit 1
echo ">> extracting ims.apk + ims.odex"
unzip -o -j -q "$ZIP" 'system/vendor/app/ims/ims.apk' 'system/vendor/app/ims/oat/arm64/ims.odex' -d "$W/in" || exit 1

# The odex is an ART OAT: its instructions are resolved against the boot image it was compiled
# against, so baksmali needs that same boot classpath to turn them back into portable smali.
echo ">> extracting the arm64 boot classpath"
unzip -o -q "$ZIP" 'system/framework/arm64/*' -d "$W" || exit 1

echo ">> deodexing"
java -jar "$BK" x -d "$W/system/framework/arm64" "$W/in/ims.odex" -o "$W/smali" 2>/dev/null || exit 1
n=$(find "$W/smali" -name '*.smali' | wc -l)
echo "   $n smali files"

# A partial deodex is the dangerous outcome: it still assembles, and fails at runtime. baksmali
# leaves quick opcodes in place when it cannot resolve them, so check rather than assume.
echo ">> checking the deodex is complete"
q=$(grep -rhoE '\b(execute-inline|invoke-virtual-quick|invoke-super-quick|i(get|put)(-object|-wide)?-quick)\b' "$W/smali" 2>/dev/null | wc -l)
u=$(grep -rl 'unresolvable\|Unable to resolve' "$W/smali" 2>/dev/null | wc -l)
echo "   leftover odex opcodes: $q    files with unresolved refs: $u"
[ "$q" -eq 0 ] && [ "$u" -eq 0 ] || { echo "!! incomplete deodex -- do not ship this" >&2; exit 1; }

echo ">> round-trip check (smali must reassemble before any edits)"
java -jar "$SM" a "$W/smali" -o "$W/classes-roundtrip.dex" 2>/dev/null || { echo "!! reassembly failed" >&2; exit 1; }
c=$(java -jar "$BK" list classes "$W/classes-roundtrip.dex" 2>/dev/null | grep -c 'org/codeaurora/ims')
echo "   reassembled, $c org.codeaurora.ims classes"

echo ">> framework surface the APK expects (step 2 builds these)"
grep -rhoE 'Lcom/android/ims[^;]*;' "$W/smali" 2>/dev/null | sed 's/^L//;s/;$//;s/\$.*//' | sort -u > "$W/surface.txt"
echo "   $(wc -l < "$W/surface.txt") distinct types -> $W/surface.txt"

# Step 2's inputs come from the device's own 7.1 boot image rather than an AOSP checkout: these are
# the exact classes this APK was compiled against, so signatures match by construction instead of
# by picking the right release tag. They are split across two jars.
#
# ims-common.jar holds the high-level helpers (ImsManager, ImsCall, ImsUt...). The parcelables and
# the internal AIDL interfaces live in framework.jar -- and specifically in its SECOND dex.
# `baksmali x <oat>` silently disassembles only the first dex of a multi-dex oat, so asking
# boot-framework.oat for com/android/ims returns nothing and looks like proof the classes are
# absent. Address the entry explicitly, using the name `baksmali list dex` prints, appended to the
# oat path as if it were a directory.
echo ">> recovering the 7.1 framework classes from the boot image"
java -jar "$BK" x -d "$W/system/framework/arm64" "$W/system/framework/arm64/boot-ims-common.oat" \
     -o "$W/legacy/ims-common" 2>/dev/null || exit 1
java -jar "$BK" x -d "$W/system/framework/arm64" \
     "$W/system/framework/arm64/boot-framework.oat//system/framework/framework.jar:classes2.dex" \
     -o "$W/legacy/framework2" 2>/dev/null || exit 1
echo "   ims-common: $(find "$W/legacy/ims-common" -name '*.smali' | wc -l) classes"
echo "   framework classes2: $(find "$W/legacy/framework2" -name '*.smali' | wc -l) classes"

echo ">> confirming every referenced type is recoverable"
{ find "$W/legacy/ims-common" -name '*.smali' | sed "s#$W/legacy/ims-common/##"
  find "$W/legacy/framework2" -name '*.smali' | sed "s#$W/legacy/framework2/##"; } \
  | sed 's#\.smali$##;s/\$.*//' | LC_ALL=C sort -u > "$W/have.txt"
miss=$(LC_ALL=C comm -23 <(LC_ALL=C sort -u "$W/surface.txt") "$W/have.txt")
if [ -n "$miss" ]; then echo "!! not recoverable from the boot image:"; echo "$miss" | sed 's/^/   /'; exit 1; fi
echo "   all $(wc -l < "$W/surface.txt") types present"

