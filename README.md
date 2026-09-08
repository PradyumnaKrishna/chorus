<p align="center">
  <img src="BuildSupport/Brand/ChorusSoundwave.png" width="80" alt="Chorus soundwave">
</p>

# Chorus

Give your words a voice. Right on your Mac.

Chorus is a native macOS text-to-speech reader with a floating player, selected-text
reading, and optional CLI completion hooks. Use the voices already on your Mac, or add
**Kokoro** for 41 on-device neural voices across 7 languages.

[Getting started](#getting-started) · [Reader guide](Documentation/Reader.md) ·
[Build guide](Documentation/Building.md) · [Releases](https://github.com/PradyumnaKrishna/chorus/releases)

## Features

- Paste text, choose a voice, adjust speed, and listen.
- Control playback from the floating player or the Chorus soundwave menu-bar icon.
- Read selected text in compatible apps with optional Accessibility permission.
- Connect CLI completion hooks from the Integrations page.
- Install, repair, or remove Kokoro's model through its independent companion app.

macOS voices support word highlighting. Kokoro uses the compact player until reliable
word timing is available. Kokoro speech synthesis runs locally after the initial model download.

## Getting started

| App | Purpose | Requirements |
| --- | --- | --- |
| **Chorus** | Text reader and playback controls | macOS 14+, Apple Silicon or Intel |
| **Chorus Kokoro** | Optional neural voices and model maintenance | macOS 14+, Apple Silicon |

1. Obtain the apps from [Releases](https://github.com/PradyumnaKrishna/chorus/releases)
   when available, or [build from source](Documentation/Building.md).
2. Place `Chorus.app` in `~/Applications`, open it, and try a macOS voice.
3. For Kokoro, also place `Chorus Kokoro.app` in `~/Applications`. Open it and choose
   **Install** to download and verify its approximately 86 MB model.
4. Return to Chorus → **Voice apps**, choose **Refresh voices**, then select a Kokoro voice
   in **Text to speech**.

Installation is per user. Models live outside the app bundle in the companion's App Group
container. Chorus opens the installed companion; it does not download apps or install models.

> Unsigned release builds are not notarized and may be blocked by macOS. Kokoro requires
> signing for usable system voice registration; its unsigned build is a development artifact,
> not a ready-to-use system voice installation. See [Signing](Documentation/Building.md#signing).

Closing the reader hides its Dock icon while the menu-bar controls remain available.
Choose **Open Chorus** from the soundwave menu to return, or **Quit Chorus** to exit.

## Build

Requires Xcode 26+ (Swift 6.2+) and XcodeGen 2.44+. Kokoro also requires Apple Silicon
and the native dependency build tools:

```sh
brew install xcodegen autoconf automake libtool
```

```sh
make debug APP=Chorus     # reader
make debug APP=Kokoro     # companion
make release APP=Chorus   # optimized reader
make release APP=Kokoro   # optimized companion
make test                # contracts and plist validation
```

Builds are unsigned unless both `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` are present
in the environment. There are no signing configuration files. The provider requires
signing for usable system voice registration.

App versions, build numbers, bundle IDs, and project names live in each app's `Project.yml`.
Builds create `Chorus.xcodeproj` or `Kokoro.xcodeproj` and use separate `build/<App>/`
directories. [Full build configuration](Documentation/Building.md).

## Documentation

- [Reader guide](Documentation/Reader.md): setup, playback, selections, and troubleshooting.
- [Kokoro companion](Providers/Kokoro/README.md): supported voices, installation, and repair.
- [Building](Documentation/Building.md): commands, outputs, and environment-only signing.
- [Architecture](Documentation/Architecture.md): reader, companion, and shared-library boundaries.
- [Adding a provider](Documentation/AddingAProvider.md): create an independent voice app.

For bugs, [open an issue](https://github.com/PradyumnaKrishna/chorus/issues) with your macOS
version, Mac architecture, app version, affected voice, and reproduction steps. Redact
private text and credentials from any screenshots or logs.

## Layout

| Path | Contents |
| --- | --- |
| `Packages/ChorusKit` | Integration, installer, and provider contracts |
| `Providers/Kokoro` | Kokoro app, speech extension, engine, and native dependencies |
| `Hub`, `CLI`, `Shared` | Chorus reader, completion hook, and speech helpers |
| `BuildSupport` | Shared brand assets and XcodeGen templates |
| `Documentation` | [Architecture](Documentation/Architecture.md) and [Adding a provider](Documentation/AddingAProvider.md) |

Providers are independently signed, versioned, and released. They share the installer but
no engine binaries, App Groups, or release schedules.

## License

Shared Chorus code — `Packages/ChorusKit`, `BuildSupport`, and the root build
configuration — is MIT; see [LICENSE](LICENSE).

The restored reader in `Hub`, `CLI`, `Shared`, and `Tests/Hub` retains the
GPL-3.0-or-later licensing declared on `old-main`. It uses and bundles the full GPL text at
[Providers/Kokoro/LICENSE](Providers/Kokoro/LICENSE); the path is shared to avoid a duplicate copy.

`Providers/Kokoro` and the distributed **Chorus Kokoro** application are
**GPL-3.0-or-later**, because the speech extension statically links espeak-ng. MIT code may
be combined into it; the resulting application must satisfy GPL-3.0-or-later. Its full
license text ships inside the app.

This also means Chorus Kokoro cannot go to the Mac App Store, whose terms conflict with
GPL-3.0. Store distribution would require replacing espeak-ng.

Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
which also carries the corresponding-source statement.
