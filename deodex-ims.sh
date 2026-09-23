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
