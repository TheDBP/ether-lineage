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
# baksmali/smali come from the Android tree. Look where the tree actually is -- this runs both from
# the host (tree under build_output/src) and from inside the container (tree at /aosp, cwd /aosp).
if [ -z "${SMALI_DIR:-}" ]; then
  for _c in build_output/src/prebuilts/extract-tools/common/smali \
            prebuilts/extract-tools/common/smali \
            /aosp/prebuilts/extract-tools/common/smali; do
    [ -f "$_c/baksmali.jar" ] && SMALI_DIR="$_c" && break
  done
fi
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

# Hidden-API: libcore's type-specific System.arraycopy overloads -- arraycopy([BI[BII)V and friends
# -- are @hide/@UnsupportedAppUsage fast paths, not public API. A 2016 apk calling one directly dies
# on 13 with
#     java.lang.IllegalAccessError: Method 'void java.lang.System.arraycopy(byte[], ...)'
#     is inaccessible to class ...
# at the first call, which for ims.apk is inside ImsService.onCreate -- so com.android.phone
# crash-loops and IMS never comes up. The generic arraycopy(Object,int,Object,int,int) IS public and
# accepts arrays, so redirecting to it is semantically identical and keeps hidden-API enforcement on.
echo ">> redirecting hidden-API System.arraycopy overloads to the public one"
n=$(grep -rlE 'Ljava/lang/System;->arraycopy\(\[[A-Z]I\[[A-Z]II\)V' "$SRC" 2>/dev/null | wc -l)
if [ "$n" -gt 0 ]; then
  grep -rlE 'Ljava/lang/System;->arraycopy\(\[[A-Z]I\[[A-Z]II\)V' "$SRC" 2>/dev/null | while read -r f; do
    sed -i -E 's#Ljava/lang/System;->arraycopy\(\[[A-Z]I\[[A-Z]II\)V#Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V#g' "$f"
  done
fi
left=$(grep -rhoE 'Ljava/lang/System;->arraycopy\(\[[A-Z]I\[[A-Z]II\)V' "$SRC" 2>/dev/null | wc -l)
echo "   rewrote in $n file(s); specialized calls remaining: $left"
[ "$left" -eq 0 ] || { echo "!! specialized arraycopy survived the rewrite" >&2; exit 1; }

# Video telephony cannot load on 13 and takes the whole service down with it. ImsService.onCreate
# calls ImsVideoGlobals.init(), whose static initialiser dlopens the VT natives, and those were
# linked against a libgui that no longer exists:
#     UnsatisfiedLinkError: dlopen failed: cannot locate symbol
#     "_ZN7android7SurfaceC1ERKNS_2spINS_22IGraphicBufferProducerEEEb"
#     at com.qualcomm.ims.vt.ImsMedia.<clinit> ... at ImsService.onCreate
# i.e. android::Surface::Surface(sp<IGraphicBufferProducer> const&, bool). Shimming that is a
# different project; the bridge already reports no video support (getVideoCallProvider returns
# null), so drop the call. It returns void and its result is unused, so the line goes cleanly.
if [ "$T" = "ims" ]; then
  echo ">> dropping the video-telephony init that cannot dlopen on 13"
  f="$SRC/org/codeaurora/ims/ImsService.smali"
  [ -f "$f" ] || { echo "!! ImsService.smali not found" >&2; exit 1; }
  before=$(grep -c 'ImsVideoGlobals;->init(' "$f")
  [ "$before" -eq 1 ] || { echo "!! expected exactly 1 ImsVideoGlobals.init call, found $before" >&2; exit 1; }
  sed -i '/invoke-static {.*}, Lcom\/qualcomm\/ims\/vt\/ImsVideoGlobals;->init(.*)V/d' "$f"
  after=$(grep -c 'ImsVideoGlobals;->init(' "$f")
  [ "$after" -eq 0 ] || { echo "!! the ImsVideoGlobals.init call survived" >&2; exit 1; }
  echo "   removed 1 call"

  # Dropping init() is not enough on its own. openForSub does
  #     ImsVideoGlobals.getInstance().setActiveSub(sub)
  # and getInstance() throws RuntimeException when the singleton is null -- with the misleading text
  # "ImsVideoGlobals: Multiple initializaiton." So every startSession came back as an uncaught remote
  # exception and the IMS session was never usable, while the bridge logged a successful open.
  # setActiveSub's result is unused, so the whole call goes. Video stays unsupported either way.
  g="$SRC/org/codeaurora/ims/ImsService\$2.smali"
  [ -f "$g" ] || { echo "!! ImsService\$2.smali not found" >&2; exit 1; }
  gi=$(grep -c 'ImsVideoGlobals;->getInstance()' "$g")
  sa=$(grep -c 'ImsVideoGlobals;->setActiveSub(' "$g")
  [ "$gi" -eq 1 ] && [ "$sa" -eq 1 ] || {
    echo "!! expected one getInstance and one setActiveSub in ImsService\$2, found $gi/$sa" >&2; exit 1; }
  python3 - "$g" <<'PYIN'
import io,re,sys
p=sys.argv[1]; lines=io.open(p,encoding='utf-8').read().split('\n')
out=[]; i=0; removed=0
while i < len(lines):
    l=lines[i]
    if 'ImsVideoGlobals;->getInstance()' in l:
        # drop the invoke and the move-result that consumes it
        i+=1; removed+=1
        while i < len(lines) and lines[i].strip()=='':
            i+=1
        if i < len(lines) and lines[i].strip().startswith('move-result-object'):
            i+=1; removed+=1
        continue
    if 'ImsVideoGlobals;->setActiveSub(' in l:
        i+=1; removed+=1
        continue
    out.append(l); i+=1
io.open(p,'w',encoding='utf-8').write('\n'.join(out))
print("   removed %d instruction(s) from openForSub" % removed)
PYIN
  left=$(grep -c 'ImsVideoGlobals' "$g")
  [ "$left" -eq 0 ] || { echo "!! ImsVideoGlobals references survived in ImsService\$2" >&2; exit 1; }
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
