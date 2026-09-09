# Chorus Kokoro

41 Kokoro voices across American and British English, Spanish, French, Hindi, Italian, and
Portuguese. The extension bundles the voice tensors, tokenizer, and espeak-ng data; the
containing app downloads the quantized Kokoro-82M model on first run.

Japanese and Chinese are excluded because the bundled phonemizer does not support them.

## Install and maintain

Requires macOS 14+ on Apple Silicon. Place the signed `Chorus Kokoro.app` in
`~/Applications`, open it, and choose **Install**. The approximately 86 MB model download
is verified before installation. Return to Chorus and choose **Voice apps → Refresh voices**.

Use **Repair** to download fresh verified model files, or **Upgrade** when a release
declares a newer model than the one installed. Use **Uninstall** to remove the downloaded
model. Uninstall the model before moving the app to Trash; deleting only the app leaves the
model behind.

Models live under `Artifacts/` in the companion's team-derived App Group container, not
inside the app. A build signed by another team uses a different container.

System voice registration requires signing. See [Building](../../Documentation/Building.md#signing).

## Development

| Directory | Contents |
| --- | --- |
| `App` | Installer entry point, metadata, entitlements, and `Provider.json` |
| `Extension` | `AVSpeechSynthesisProviderAudioUnit` implementation |
| `Engine` | Text normalization, SSML, phonemization, voices, and inference |
| `Native` | C interface to ONNX Runtime |
| `Resources` | `artifacts.sha256`, pinning the bundled voice and tokenizer files |
| `BuildSupport` | Dependency preparation and the engine smoke test |

Build from the repository root with `make debug APP=Kokoro`. See
[Building](../../Documentation/Building.md) for output and signing details.

## License

GPL-3.0-or-later, because the extension statically links espeak-ng. See [LICENSE](LICENSE).
Kokoro weights are Apache-2.0 and ONNX Runtime is MIT; see
[THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
