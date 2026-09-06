#!/bin/bash
# Stage only the native dependencies and resources owned by the Kokoro provider.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/Dependencies/espeak-ng.sh"
"$HERE/Dependencies/onnxruntime.sh"
"$HERE/Dependencies/resources.sh"
