#!/bin/bash
set -euo pipefail
GRY='\033[0;37m'; GRN='\033[0;32m'; YLW='\033[1;33m'; N='\033[0m'

BASE_PRO="https://apt.procurs.us/pool/main/iphoneos-arm64"
BASE_BIN="https://apt.bingner.com/debs/1443.00"
WORK_DIR="${GITHUB_WORKSPACE}/work"
mkdir -p "${WORK_DIR}/debs"
> "${WORK_DIR}/urls.txt"

echo -e "${GRY}[>] Collecting URLs${N}"
HTML=$(curl -fsSL "${BASE_PRO}/1700/apt/" 2>/dev/null || true)
echo "$HTML" | grep -oE 'href="[^"]+\.deb"' | sed 's/href="//;s/"//' | while read -r FN; do
  echo "${BASE_PRO}/1700/apt/${FN}" >> "${WORK_DIR}/urls.txt"
done

HTML=$(curl -fsSL "${BASE_BIN}/" 2>/dev/null || true)
echo "$HTML" | grep -oE 'href="[^"]+\.deb"' | sed 's/href="//;s/"//' | head -n 2 | while read -r FN; do
  echo "${BASE_BIN}/${FN}" >> "${WORK_DIR}/urls.txt"
done

JOBS=$(sysctl -n hw.ncpu)
echo -e "${GRY}[>] Parallel workers: ${JOBS}${N}"

cat > "${WORK_DIR}/run.sh" <<'INNER'
#!/bin/bash
set -euo pipefail
URL="$1"
WORK_DIR="$2"
FN=$(basename "$URL")

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

if curl -fsSL "$URL" -o "original_$FN"; then
  cp "original_$FN" "$FN"
  rootless-patcher "$FN" >/dev/null 2>&1 || true
  
  NEW_DEB=""
  for d in *.deb; do
    if [[ "$d" == original_* ]]; then continue; fi
    if [ -s "$d" ]; then
      NEW_DEB="$d"
      break
    fi
  done
  
  if [ -n "$NEW_DEB" ]; then
    cp "$NEW_DEB" "${WORK_DIR}/debs/${FN}"
  else
    cp "original_$FN" "${WORK_DIR}/debs/${FN}"
  fi
fi
cd /
rm -rf "$TMP_DIR"
INNER
chmod +x "${WORK_DIR}/run.sh"

cat "${WORK_DIR}/urls.txt" | xargs -P "${JOBS}" -I {} bash "${WORK_DIR}/run.sh" {} "${WORK_DIR}"

echo -e "${GRY}[>] Generating Packages.entry${N}"
cd "${WORK_DIR}/debs"
for deb in *.deb; do
  [ -e "$deb" ] || continue
  dpkg-deb -f "$deb" > "/tmp/ctrl.txt" 2>/dev/null || continue
  grep -E '^(Package|Version|Architecture|Depends|Description|Author|Name):' /tmp/ctrl.txt | sed 's/^Architecture: .*/Architecture: iphoneos-arm64/' > "${WORK_DIR}/${deb%.deb}.entry"
  echo "Filename: placeholder" >> "${WORK_DIR}/${deb%.deb}.entry"
  echo "Size: $(stat -f%z "$deb")" >> "${WORK_DIR}/${deb%.deb}.entry"
  echo "MD5sum: $(md5 -q "$deb")" >> "${WORK_DIR}/${deb%.deb}.entry"
  echo "SHA256: $(shasum -a 256 "$deb" | awk '{print $1}')" >> "${WORK_DIR}/${deb%.deb}.entry"
  echo "" >> "${WORK_DIR}/${deb%.deb}.entry"
done
echo -e "  ${GRN}✓${N} Entries generated"