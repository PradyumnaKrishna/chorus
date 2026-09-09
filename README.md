<p align="center">
  <img src="BuildSupport/Brand/ChorusSoundwave.png" width="80" alt="Chorus soundwave">
</p>

# Chorus

Give your words a voice. Right on your Mac.

Chorus is a native macOS text-to-speech reader. It works with built-in macOS voices and
adds 41 on-device Kokoro voices through an optional companion app.

[Getting started](#getting-started) · [Reader guide](Documentation/Reader.md) ·
[Build guide](Documentation/Building.md) · [Releases](https://github.com/PradyumnaKrishna/chorus/releases)

## Features

- Paste text or read selected text from compatible apps.
- Control playback from the app, floating player, menu bar, or media keys.
- Follow the spoken word while macOS and Kokoro voices read.
- Read completed Codex and Claude Code responses through optional CLI hooks.
- Manage Kokoro's model independently from the reader.

## Getting started

| App | Purpose | Requirements |
| --- | --- | --- |
| **Chorus** | Reader and playback controls | macOS 14+, Apple Silicon or Intel |
| **Chorus Kokoro** | Optional Kokoro voices | macOS 14+, Apple Silicon |

1. Download the apps from [Releases](https://github.com/PradyumnaKrishna/chorus/releases)
   or [build them](Documentation/Building.md).
2. Place `Chorus.app` in `~/Applications`, open it, and try a macOS voice.
3. To add Kokoro, place `Chorus Kokoro.app` in `~/Applications`, open it, and install its
   model. Return to Chorus and choose **Voice apps → Refresh voices**.

See the [reader guide](Documentation/Reader.md) for playback, integrations, and
troubleshooting, or the [Kokoro guide](Providers/Kokoro/README.md) for model maintenance.

## Build

Requires Xcode 26+, Swift 6.2+, and XcodeGen 2.44+. Kokoro also needs Apple Silicon and
its native build tools:

```sh
brew install xcodegen autoconf automake libtool
```

```sh
make debug APP=Chorus     # reader
make debug APP=Kokoro     # companion
make release APP=Chorus   # optimized reader
make release APP=Kokoro   # optimized companion
make test                 # contracts and plist validation
```

Builds are unsigned unless `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` are both set.
Kokoro requires signing for system voice registration. See the [build guide](Documentation/Building.md).

## Documentation

- [Reader guide](Documentation/Reader.md): setup, playback, selections, and troubleshooting.
- [Kokoro companion](Providers/Kokoro/README.md): supported voices, installation, and repair.
- [Building](Documentation/Building.md): commands, outputs, and environment-only signing.
- [Architecture](Documentation/Architecture.md): reader, companion, and shared-library boundaries.
- [Adding a provider](Documentation/AddingAProvider.md): create an independent voice app.

For bugs, [open an issue](https://github.com/PradyumnaKrishna/chorus/issues) with the app
version, macOS version, Mac architecture, affected voice, and reproduction steps. Remove
private text and credentials from screenshots and logs.

## License

Shared code in `Packages/ChorusKit` and `BuildSupport` is MIT; see [LICENSE](LICENSE).
The reader code in `Hub`, `CLI`, `Shared`, and `Tests/Hub` is GPL-3.0-or-later.
`Providers/Kokoro` is also GPL-3.0-or-later because it statically links espeak-ng; see
[Providers/Kokoro/LICENSE](Providers/Kokoro/LICENSE). This prevents Mac App Store
distribution unless espeak-ng is replaced.

Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
which also carries the corresponding-source statement.
