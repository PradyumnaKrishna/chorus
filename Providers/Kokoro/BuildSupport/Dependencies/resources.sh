#!/bin/bash
# Downloads the voice style tensors and phoneme vocabulary bundled with the
# extension. The container app downloads the large ONNX model during install.
set -euo pipefail

REPO="onnx-community/Kokoro-82M-v1.0-ONNX"
BASE="https://huggingface.co/$REPO/resolve/main"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="$REPO_ROOT/.artifacts/Kokoro/Models"
LOCKFILE="$REPO_ROOT/Providers/Kokoro/Resources/artifacts.sha256"

mkdir -p "$OUT/voices"

fetch() { # url dest sha256
  if [ -s "$2" ] && echo "$3  $2" | shasum -a 256 --check --status; then
    echo "  have $(basename "$2")"
    return
  fi
  echo "  get $(basename "$2")"
  curl -fL --retry 3 --progress-bar "$1" -o "$2.part"
  echo "$3  $2.part" | shasum -a 256 --check --status || {
    rm -f "$2.part"
    echo "Checksum verification failed for $(basename "$2")" >&2
    exit 1
  }
  mv "$2.part" "$2"
}

echo "Pinned provider resources:"
while read -r checksum artifact; do
  [ -n "$checksum" ] || continue
  fetch "$BASE/$artifact" "$OUT/$artifact" "$checksum"
done < "$LOCKFILE"

echo
echo "Staged in $OUT:"
du -sh "$OUT"
ls "$OUT/voices" | wc -l | xargs echo "  voices:"
