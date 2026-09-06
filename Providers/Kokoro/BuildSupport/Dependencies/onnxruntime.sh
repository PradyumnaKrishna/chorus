#!/bin/bash
# Downloads the prebuilt ONNX Runtime for macOS arm64 and stages the headers
# and dylib under the ignored artifact cache.
set -euo pipefail

ORT_VERSION="${ORT_VERSION:-1.29.0}"
ORT_SHA256="${ORT_SHA256:-d0706fc34f315d8c88639d0a8c81f2e09e815f282cabed3493c06a054352cf92}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
VENDOR="$REPO_ROOT/.artifacts/Kokoro/Vendor/onnxruntime"

if [ -f "$VENDOR/lib/libonnxruntime.dylib" ]; then
  echo "onnxruntime already staged at $VENDOR — skipping"
  exit 0
fi

TARBALL="onnxruntime-osx-arm64-$ORT_VERSION"
URL="https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/$TARBALL.tgz"
WORK="$REPO_ROOT/.artifacts/Kokoro/Downloads/onnxruntime"

mkdir -p "$WORK" "$VENDOR"
echo "Downloading $TARBALL..."
curl -fL --retry 3 --progress-bar "$URL" -o "$WORK/ort.tgz"
echo "$ORT_SHA256  $WORK/ort.tgz" | shasum -a 256 --check --status || {
  echo "Checksum verification failed for $TARBALL" >&2
  exit 1
}
tar -xzf "$WORK/ort.tgz" -C "$WORK"

cp -R "$WORK/$TARBALL/include" "$VENDOR/include"
mkdir -p "$VENDOR/lib"
cp "$WORK/$TARBALL/lib/libonnxruntime.$ORT_VERSION.dylib" "$VENDOR/lib/libonnxruntime.dylib"

# The dylib ships with an absolute install name; rewrite it so it can be
# embedded in the extension bundle and found via @rpath.
install_name_tool -id "@rpath/libonnxruntime.dylib" "$VENDOR/lib/libonnxruntime.dylib"

# Rewriting the load command invalidates the signature, and the loader kills
# any process that maps an invalidly-signed dylib. Re-sign ad hoc.
codesign --force --sign - "$VENDOR/lib/libonnxruntime.dylib"

echo "--- staged ---"
otool -D "$VENDOR/lib/libonnxruntime.dylib"
ls -la "$VENDOR/lib/libonnxruntime.dylib"
