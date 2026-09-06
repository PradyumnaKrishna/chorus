#!/bin/bash
# Builds espeak-ng as a static library for macOS arm64 and stages the
# headers, libespeak-ng.a and espeak-ng-data/ under the ignored artifact cache.
set -euo pipefail

ESPEAK_TAG="${ESPEAK_TAG:-1.52.0}"
ESPEAK_REVISION="${ESPEAK_REVISION:-4870adfa25b1a32b4361592f1be8a40337c58d6c}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
VENDOR="$REPO_ROOT/.artifacts/Kokoro/Vendor/espeak-ng"
WORK="$REPO_ROOT/.artifacts/Kokoro/Source/espeak-ng"

if [ -f "$VENDOR/lib/libespeak-ng.a" ] && [ -d "$VENDOR/share/espeak-ng-data" ]; then
  echo "espeak-ng already staged at $VENDOR — skipping (rm -rf it to rebuild)"
  exit 0
fi

export PATH="/opt/homebrew/opt/libtool/libexec/gnubin:/opt/homebrew/bin:$PATH"

mkdir -p "$(dirname "$WORK")"
if [ ! -d "$WORK/.git" ]; then
  rm -rf "$WORK"
  git clone --depth 1 --branch "$ESPEAK_TAG" https://github.com/espeak-ng/espeak-ng.git "$WORK"
fi

ACTUAL_REVISION="$(git -C "$WORK" rev-parse HEAD)"
if [ "$ACTUAL_REVISION" != "$ESPEAK_REVISION" ]; then
  echo "espeak-ng $ESPEAK_TAG resolved to unexpected revision $ACTUAL_REVISION" >&2
  exit 1
fi

cd "$WORK"
[ -f configure ] || ./autogen.sh

# No audio backend, no async threads, no extra synths: we only ever call
# espeak_TextToPhonemes(), so everything else is dead weight in the .appex.
CFLAGS="-O2 -arch arm64 -mmacosx-version-min=13.0" \
CXXFLAGS="-O2 -arch arm64 -mmacosx-version-min=13.0" \
./configure \
  --prefix="$VENDOR" \
  --enable-static \
  --disable-shared \
  --with-pcaudiolib=no \
  --with-sonic=no \
  --with-mbrola=no \
  --with-klatt=no \
  --with-speechplayer=no \
  --with-async=no \
  --with-extdict-ru=no \
  --with-extdict-cmn=no

make -j"$(sysctl -n hw.ncpu)"
make install

echo "--- staged ---"
ls -la "$VENDOR/lib/libespeak-ng.a"
du -sh "$VENDOR/share/espeak-ng-data"
