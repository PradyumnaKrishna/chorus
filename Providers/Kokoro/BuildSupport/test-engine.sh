#!/bin/bash
# Builds a small CLI against the engine sources and synthesizes one phrase,
# bypassing the audio unit. Useful for checking phonemization and inference
# without reinstalling the app. Writes /tmp/kokoro-test.wav.
#
#   KOKORO_MODEL_URL=/path/to/model_q8f16.onnx make engine-smoke APP=Kokoro
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

APP_PATH="${1:?Pass the built Chorus Kokoro.app path}"
TEXT="${2:-Hello world, this is Kokoro speaking on macOS.}"
VOICE="${3:-af_bella}"
OUT=".build/harness"
RESOURCES="$APP_PATH/Contents/PlugIns/KokoroSynthesizer.appex/Contents/Resources"
MODEL_URL="${KOKORO_MODEL_URL:-$REPO_ROOT/.artifacts/Kokoro/Models/kokoro.onnx}"

if [ ! -d "$RESOURCES" ]; then
  echo "Build the app first: make debug APP=Kokoro" >&2
  exit 1
fi
if [ ! -f "$MODEL_URL" ]; then
  echo "Set KOKORO_MODEL_URL to an installed or downloaded Kokoro ONNX model." >&2
  exit 1
fi

mkdir -p "$OUT" .build/module-cache

clang -target arm64-apple-macos14.0 -c -O2 Providers/Kokoro/Native/CKokoroORT/kokoro_ort.c \
  -IProviders/Kokoro/Native/CKokoroORT/include \
  -I.artifacts/Kokoro/Vendor/onnxruntime/include -o "$OUT/kokoro_ort.o"

swiftc -O -target arm64-apple-macos14.0 -module-cache-path .build/module-cache -swift-version 5 \
  Providers/Kokoro/Engine/*.swift Providers/Kokoro/Tests/EngineSmoke/main.swift "$OUT/kokoro_ort.o" \
  -import-objc-header Providers/Kokoro/Extension/Kokoro-Bridging-Header.h \
  -IProviders/Kokoro/Native/CKokoroORT/include \
  -I.artifacts/Kokoro/Vendor/espeak-ng/include \
  -I.artifacts/Kokoro/Vendor/onnxruntime/include \
  -L.artifacts/Kokoro/Vendor/espeak-ng/lib -lespeak-ng \
  -L.artifacts/Kokoro/Vendor/onnxruntime/lib -lonnxruntime \
  -o "$OUT/kokoro-cli"

DYLD_LIBRARY_PATH="$REPO_ROOT/.artifacts/Kokoro/Vendor/onnxruntime/lib" "$OUT/kokoro-cli" \
  "$RESOURCES" "$MODEL_URL" "$TEXT" "$VOICE"
