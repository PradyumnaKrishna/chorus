# Chorus Kokoro

41 Kokoro voices across American and British English, Spanish, French, Hindi, Italian, and
Portuguese. The extension bundles the voice tensors, tokenizer, and espeak-ng data; the
containing app downloads the quantized Kokoro-82M model on first run.

Japanese and Chinese voices are excluded: they need a grapheme-to-phoneme path espeak-ng
does not provide for Kokoro, and shipping them would sound wrong.

| Directory | Contents |
| --- | --- |
| `App` | Installer entry point, metadata, entitlements, and `Provider.json` |
| `Extension` | `AVSpeechSynthesisProviderAudioUnit` implementation |
| `Engine` | Text normalization, SSML, phonemization, voices, and inference |
| `Native` | C interface to ONNX Runtime |
| `Resources` | `artifacts.sha256`, pinning the bundled voice and tokenizer files |
| `BuildSupport` | Dependency preparation and the engine smoke test |

Build from the repository root with `make build PROVIDER=Kokoro`.

## License

GPL-3.0-or-later, because the extension statically links espeak-ng. See [LICENSE](LICENSE).
Kokoro weights are Apache-2.0 and ONNX Runtime is MIT; see
[THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
