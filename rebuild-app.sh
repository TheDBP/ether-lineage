#!/usr/bin/env bash
# rebuild-app.sh — turn the smali from deodex-app.sh back into an installable apk. Step 2.
#
#   rebuild-app.sh <workdir-from-deodex-app.sh> <ims|cne>
#
# cne is a straight reassemble: CNEService references nothing Android removed, so its classes go
# back untouched.
#
# ims cannot be. It is built against com.android.ims, which Android 9 deleted, so the apk is
# rewritten into org.codeaurora.ims.legacy.* and the 7.1 framework classes it needs are recovered
# from the stock boot image, renamed the same way, and merged into its dex. The apk then carries
# its own copy of the legacy framework and needs no uses-library.
#
# Two rules the rename has to respect, and they pull in opposite directions:
#
#   * AIDL descriptor strings MUST be renamed. Android 13 still ships
#     com/android/ims/internal/IImsService.aidl with different methods, so leaving 7.1 interfaces
#     advertising the same descriptor invites a binder call across incompatible signatures.
#   * Broadcast action strings must NOT be. "com.android.ims.IMS_SERVICE_UP" and friends are a
#     contract with whoever listens, not class names.
#
# The rule that separates them: rewrite a string only when it exactly names a class being renamed.
#
# Output apk is UNSIGNED and has no META-INF. ims declares sharedUserId="android.uid.phone", so it
# must be signed with the platform key -- ship it via android_app_import with certificate:
# "platform" and let the build sign it. Do not presign.
set -u

W="${1:?usage: rebuild-app.sh <workdir> <ims|cne>}"
T="${2:?usage: rebuild-app.sh <workdir> <ims|cne>}"
SMALI_DIR="${SMALI_DIR:-build_output/src/prebuilts/extract-tools/common/smali}"
BK="$SMALI_DIR/baksmali.jar"; SM="$SMALI_DIR/smali.jar"
for j in "$BK" "$SM"; do [ -f "$j" ] || { echo "!! missing $j (set SMALI_DIR)" >&2; exit 1; }; done
[ -d "$W/smali" ] || { echo "!! $W/smali not found -- run deodex-app.sh first" >&2; exit 1; }

case "$T" in
  ims) APK=ims.apk ;;
  cne) APK=CNEService.apk ;;
  *)   echo "!! target must be ims or cne" >&2; exit 1 ;;
esac
[ -f "$W/in/$APK" ] || { echo "!! $W/in/$APK not found" >&2; exit 1; }

SRC="$W/smali"
if [ "$T" = "ims" ]; then
  echo ">> computing the legacy closure and renaming"
  python3 - "$W" <<'PY' || exit 1
import os,re,sys,shutil,collections
W=sys.argv[1]
OLD_P='com/android/ims'; NEW_P='org/codeaurora/ims/legacy'
OLD_D='com.android.ims';  NEW_D='org.codeaurora.ims.legacy'
roots=[l.strip() for l in open(f'{W}/surface.txt') if l.strip()]
idx={}
for base in (f'{W}/legacy/ims-common',f'{W}/legacy/framework2'):
    for dp,_,fns in os.walk(base):
        for fn in fns:
            if fn.endswith('.smali'):
                p=os.path.join(dp,fn); c=os.path.relpath(p,base)[:-6]
                if c.startswith(OLD_P): idx.setdefault(c,p)
ref=re.compile(rb'L('+OLD_P.encode()+rb'[A-Za-z0-9_/$]*);')
seen=set(); q=[c for r in roots for c in idx if c==r or c.startswith(r+'$')]
while q:
    c=q.pop()
    if c in seen or c not in idx: continue
    seen.add(c)
    for m in ref.finditer(open(idx[c],'rb').read()):
        t=m.group(1).decode()
        for c2 in idx:
            if (c2==t or c2.startswith(t+'$')) and c2 not in seen: q.append(c2)
miss=[r for r in roots if r not in idx]
if miss:
    print('!! not recoverable: '+', '.join(miss)); sys.exit(1)
dotted={c.replace('/','.') for c in seen}
type_re=re.compile(r'L'+OLD_P+r'([A-Za-z0-9_/$]*);')
str_re=re.compile(r'"([^"]*)"')
def rewrite(txt):
    txt=type_re.sub(lambda m:'L'+NEW_P+m.group(1)+';',txt)
    return str_re.sub(lambda m:'"'+NEW_D+m.group(1)[len(OLD_D):]+'"' if m.group(1) in dotted else m.group(0),txt)
out=f'{W}/merged'; shutil.rmtree(out,ignore_errors=True)
shutil.copytree(f'{W}/smali',out)
for dp,_,fns in os.walk(out):
    for fn in fns:
        if fn.endswith('.smali'):
            p=os.path.join(dp,fn)
            # Read fully, THEN write. open(p,'w') truncates as soon as it is evaluated, so doing
            # both in one expression hands rewrite() an empty string and silently blanks the file.
            txt=open(p).read()
            open(p,'w').write(rewrite(txt))
for c in seen:
    d=os.path.join(out,NEW_P+c[len(OLD_P):]+'.smali')
    os.makedirs(os.path.dirname(d),exist_ok=True)
    src_txt=open(idx[c]).read()
    open(d,'w').write(rewrite(src_txt))
bad=[os.path.join(dp,fn) for dp,_,fns in os.walk(out) for fn in fns
     if fn.endswith('.smali') and 'L'+OLD_P in open(os.path.join(dp,fn)).read()]
print(f"   legacy classes merged: {len(seen)}")
print(f"   files still referencing {OLD_P}: {len(bad)}")
if bad: sys.exit(1)
PY
  SRC="$W/merged"
fi

echo ">> assembling classes.dex"
java -jar "$SM" a "$SRC" -o "$W/classes.dex" 2>/dev/null || { echo "!! assembly failed" >&2; exit 1; }
echo "   $(java -jar "$BK" list classes "$W/classes.dex" 2>/dev/null | wc -l) classes"

echo ">> rebuilding $APK"
OUT="$W/${APK%.apk}-rebuilt.apk"
rm -f "$OUT"; cp "$W/in/$APK" "$OUT" || exit 1
zip -q -d "$OUT" 'META-INF/*' >/dev/null 2>&1
( cd "$W" && zip -q -j "$(basename "$OUT")" classes.dex ) || exit 1

# An apk that kept its stripped state, or quietly lost content, still builds and installs. Compare
# against the original rather than assuming a fixed layout -- CNEService.apk legitimately has no
# resources.arsc and no res/, it is a manifest-only app.
unzip -l "$OUT" 2>/dev/null | grep -q 'classes\.dex' || { echo "!! no classes.dex in the apk" >&2; exit 1; }
unzip -l "$OUT" 2>/dev/null | grep -qE ' META-INF/' && { echo "!! stale signature left in place" >&2; exit 1; }
lost=$(LC_ALL=C comm -23 \
  <(unzip -Z1 "$W/in/$APK" 2>/dev/null | grep -vE '^META-INF/' | LC_ALL=C sort) \
  <(unzip -Z1 "$OUT"       2>/dev/null | LC_ALL=C sort))
[ -z "$lost" ] || { echo "!! entries lost from the original apk:"; echo "$lost" | sed 's/^/   /'; exit 1; }
n=$(unzip -p "$OUT" classes.dex 2>/dev/null | wc -c)
echo "   $OUT  (classes.dex $n bytes, unsigned, resources intact)"
