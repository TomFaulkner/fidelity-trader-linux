#!/bin/bash
# Materialize the Active Trader Pro ClickOnce payload.
#
# Wine has no ClickOnce support, so we walk the deployment chain by hand and
# download every file into ./atp-files. Copy that directory to
#   $WINEPREFIX/drive_c/Program Files/Fidelity/ActiveTraderPro
# and run ActiveTraderPro.exe directly. There is no install step.
#
# Usage: ./scripts/fetch-atp.sh [outdir]      (default: ./atp-files)
set -euo pipefail

OUT="${1:-atp-files}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

UA="Mozilla/5.0"
ATP="https://www.fidelity.com/webcontent/ATPInstaller/x64"
PROD="https://www.fidelity.com/webcontent/ActiveTraderPro-64/atp/ClickOnce"

echo "==> stage 1: bootstrapper deployment manifest"
curl -sSL -A "$UA" -o "$WORK/inst.application" "$ATP/ActiveTraderProInstaller64.application"

# -> application manifest path + the URL of the real deployment manifest
read -r APPREL VER < <(python3 - "$WORK/inst.application" <<'PY'
import sys, re
s = open(sys.argv[1], encoding='utf-8-sig').read()
m = re.search(r'codebase="([^"]+\.manifest)"', s)
v = re.search(r'name="ActiveTraderProInstaller64.application"\s+version="([\d.]+)"', s)
print(m.group(1).replace('\\', '/'), v.group(1) if v else '?')
PY
)
echo "    app manifest: $APPREL (deployment version $VER)"

echo "==> stage 2: small WPF installer (holds the real URL)"
INSTDIR="$(dirname "$APPREL")"
curl -sSL -A "$UA" -o "$WORK/inst.exe" "$ATP/$INSTDIR/ActiveTraderProInstaller64.exe.deploy"

# The real deployment URL is a UTF-16 string embedded in the installer.
REALURL="$(python3 - "$WORK/inst.exe" <<'PY'
import sys, re
d = open(sys.argv[1], 'rb').read().decode('utf-16-le', 'replace')
m = re.search(r'https?://[^\s\x00]*\.Application', d)
print(m.group(0) if m else '')
PY
)"
if [ -z "$REALURL" ]; then
    echo "    could not extract URL from installer; using known location"
    REALURL="$PROD/Prod-Deploy.Application"
fi
echo "    $REALURL"

echo "==> stage 3: real deployment manifest"
curl -sSL -A "$UA" -o "$WORK/prod.application" "$REALURL"
PRODBASE="$(dirname "$REALURL")"

MANIFEST="$(python3 - "$WORK/prod.application" <<'PY'
import sys, re
s = open(sys.argv[1], encoding='utf-8-sig').read()
m = re.search(r'codebase="([^"]+\.manifest)"', s)
print(m.group(1).replace('\\', '/'))
PY
)"
echo "    -> $MANIFEST"
curl -sSL -A "$UA" -o "$WORK/app.manifest" "$PRODBASE/${MANIFEST// /%20}"

echo "==> stage 4: downloading all files"
mkdir -p "$OUT"
python3 - "$WORK/app.manifest" "$PRODBASE" "$OUT" <<'PY'
import sys, os, urllib.parse, urllib.request, xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

man, base, out = sys.argv[1], sys.argv[2], sys.argv[3]
root = ET.parse(man).getroot()

items = []
for e in root.iter():
    tag = e.tag.split('}')[-1]; a = dict(e.attrib)
    if tag == 'file' and 'name' in a:
        items.append((a['name'].replace('\\', '/'), int(a.get('size', 0))))
    elif tag == 'dependentAssembly' and 'codebase' in a:
        items.append((a['codebase'].replace('\\', '/'), int(a.get('size', 0))))
items.append((os.path.basename(man), os.path.getsize(man)))

print(f"    {len(items)} files, {sum(s for _, s in items)/1e6:.0f} MB")
os.makedirs(out, exist_ok=True)

def get(it):
    rel, size = it
    dst = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
    if os.path.exists(dst) and os.path.getsize(dst) == size:
        return ('skip', rel)
    url = base + '/' + '/'.join(urllib.parse.quote(p) for p in rel.split('/'))
    if not rel.endswith('.manifest'):      # mapFileExtensions="true"
        url += '.deploy'
    for _ in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            data = urllib.request.urlopen(req, timeout=120).read()
            if len(data) != size:
                return ('SIZE', f'{rel} {len(data)}!={size}')
            open(dst, 'wb').write(data)
            return ('ok', rel)
        except Exception as ex:
            err = str(ex)
    return ('ERR', f'{rel} {err}')

bad = []
with ThreadPoolExecutor(max_workers=8) as ex:
    for i, (st, n) in enumerate(ex.map(get, items)):
        if st not in ('ok', 'skip'):
            bad.append((st, n)); print('   ', st, n, flush=True)
        if i % 100 == 0:
            print(f'    {i}/{len(items)}', flush=True)

print(f"    done, {len(bad)} problems")
PY

echo
echo "==> files in: $OUT"
echo "    install with:"
echo "      mkdir -p \"\$WINEPREFIX/drive_c/Program Files/Fidelity\""
echo "      cp -r $OUT \"\$WINEPREFIX/drive_c/Program Files/Fidelity/ActiveTraderPro\""
