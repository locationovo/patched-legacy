#!/bin/bash
set -euo pipefail
GRY='\033[0;37m'; GRN='\033[0;32m'; N='\033[0m'
WORK_DIR="${GITHUB_WORKSPACE}/work"
REPO_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download"

cd "${WORK_DIR}/debs"
BATCH=1
COUNT=0
> ../batch_files.txt

for deb in *.deb; do
  [ -e "$deb" ] || continue
  echo "$deb" >> ../batch_files.txt
  COUNT=$((COUNT + 1))
  
  if [ "$COUNT" -eq 1000 ] || [ "$deb" = "$(ls *.deb | tail -n 1)" ]; then
    echo -e "${GRY}[>] Publishing batch ${BATCH}${N}"
    TAG="patched-batch-${BATCH}"
    cat ../batch_files.txt | while read -r f; do
      sed -i '' "s|^Filename: placeholder|Filename: ${REPO_URL}/${TAG}/${f}|" "../${f%.deb}.entry"
    done
    cat ../batch_files.txt | sed 's/\.deb$/.entry/' | xargs -I {} cat "../{}" > "../Packages.entry"
    
    gh release create "$TAG" $(cat ../batch_files.txt | tr '\n' ' ') "../Packages.entry" -t "$TAG" -n "Batch $BATCH"
    
    BATCH=$((BATCH + 1))
    COUNT=0
    > ../batch_files.txt
  fi
done
rm -rf ../debs ../*.entry ../batch_files.txt ../urls.txt ../run.sh
echo -e "  ${GRN}✓${N} Published all batches"