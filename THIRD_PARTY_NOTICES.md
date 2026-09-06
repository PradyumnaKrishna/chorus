# Third-party notices

Chorus Kokoro incorporates the following components. Each retains its own license.

| Component | Use | License | Source |
| --- | --- | --- | --- |
| espeak-ng | Grapheme-to-phoneme conversion, statically linked | GPL-3.0-or-later | https://github.com/espeak-ng/espeak-ng |
| ONNX Runtime | Model inference, embedded dylib | MIT | https://github.com/microsoft/onnxruntime |
| Kokoro-82M ONNX | Downloaded model and bundled voice tensors | Apache-2.0 | https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX |

The Kokoro weights originate from [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M);
Chorus redistributes the ONNX conversion linked above. Chorus is not affiliated with either project.

## Corresponding source

Because the speech extension statically links espeak-ng, the distributed application is
GPL-3.0-or-later. The complete corresponding source is this repository, and every external
input is pinned and verified by checksum, so any release can be rebuilt from a tagged commit:

- espeak-ng by tag **and** commit, verified in `Providers/Kokoro/BuildSupport/Dependencies/espeak-ng.sh`
- ONNX Runtime by version and SHA-256, in `onnxruntime.sh`
- voice tensors and tokenizer by SHA-256, in `Providers/Kokoro/Resources/artifacts.sha256`
- the downloaded model by size and SHA-256, in `Providers/Kokoro/App/Resources/Provider.json`

Release notes name the commit each binary was built from. This satisfies GPL-3.0 §6(d).
