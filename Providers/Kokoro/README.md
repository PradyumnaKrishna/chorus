# Chorus Kokoro

41 Kokoro voices across American and British English, Spanish, French, Hindi, Italian, and
Portuguese. The extension bundles the voice tensors, tokenizer, and espeak-ng data; the
containing app downloads the quantized Kokoro-82M model on first run.

Japanese and Chinese voices are excluded: they need a grapheme-to-phoneme path espeak-ng
does not provide for Kokoro, and shipping them would sound wrong.

## Install and maintain

Requires macOS 14+ on Apple Silicon. Place the signed `Chorus Kokoro.app` in
`~/Applications`, open it, and choose **Install**. The approximately 86 MB model download
is checked against its expected size and SHA-256 checksum before installation.
Return to Chorus → **Voice apps** and choose **Refresh voices** after setup.

Use **Repair** to download fresh verified model files. Use **Uninstall** to remove the
downloaded files owned by this provider. To remove the app completely, uninstall the model
first, quit the app, then move it to Trash; deleting only the app leaves its model behind.

Models live under `Artifacts/` in the companion's team-derived App Group container, not
inside the app bundle. A build signed by another team uses a different container. Installing
in `~/Applications` sets up the companion for your current macOS account, not every user.

Unsigned builds are for development inspection; usable system voice registration requires
signing. See [Building](../../Documentation/Building.md#signing).

## Development

| Directory | Contents |
| --- | --- |
| `App` | Installer entry point, metadata, entitlements, and `Provider.json` |
| `Extension` | `AVSpeechSynthesisProviderAudioUnit` implementation |
| `Engine` | Text normalization, SSML, phonemization, voices, and inference |
| `Native` | C interface to ONNX Runtime |
| `Resources` | `artifacts.sha256`, pinning the bundled voice and tokenizer files |
| `BuildSupport` | Dependency preparation and the engine smoke test |

Build from the repository root with `make debug APP=Kokoro`. This creates
`Kokoro.xcodeproj` and writes outputs under `build/Kokoro/`. Configure both signing
values as described in [Building](../../Documentation/Building.md) for usable system voices.

## License

GPL-3.0-or-later, because the extension statically links espeak-ng. See [LICENSE](LICENSE).
Kokoro weights are Apache-2.0 and ONNX Runtime is MIT; see
[THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
