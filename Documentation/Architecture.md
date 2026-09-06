# Architecture

## Product boundary

The Chorus reader (`Hub`) uses macOS speech APIs and a completion hook (`CLI`) sharing
contracts in `Shared`. It opens an installed companion for model maintenance, but does
not embed providers or access their model containers. Companion downloads and remote
update feeds remain deferred.

Each app's `Project.yml` declares its own project, scheme, version, and build number.
`Chorus.xcodeproj` and `Kokoro.xcodeproj` are generated independently, with outputs under
`build/Chorus/` and `build/Kokoro/`. [Build configuration](Building.md).

Each provider is a containing app with exactly one speech synthesis extension:

```text
Chorus Kokoro.app
├── Contents/MacOS/Chorus Kokoro          installer
└── Contents/PlugIns/KokoroSynthesizer.appex   engine + voices
```

The app installs the model; the extension speaks. Providers never load one another's code.

## ChorusKit

Two libraries, split by what an app extension can link:

- **`ChorusProviderKit`** — Foundation only: manifest parsing, the artifact store, and
  downloading. Linked by both the app and the extension.
- **`ChorusInstallerUI`** — AppKit and SwiftUI: the installer window. Linked by the app.

That boundary is why a provider never restates artifact layout its manifest already
declares. The extension asks `ArtifactStore` where the model is and whether it is installed,
using the same `Provider.json` the installer wrote against.

## Installer contract

`ProviderDescriptor` is the whole interface between a provider and the installer. Every
artifact declares a stable identifier, an HTTPS source, a relative destination, an exact
byte count, and a SHA-256 digest.

Install and repair download everything before committing anything, and verification
completes before an existing file is touched. During the commit, existing files are backed
up and restored if any operation fails. Uninstall removes only declared paths.

## App group and signing

macOS grants a sandboxed app its group container on the strength of the team identifier in
its code signature, so the `<team>.<name>` form needs no portal registration and no
provisioning profile. That is what lets any contributor build with their own team.

No team identifier is committed. A provider declares `CHORUS_GROUP_NAME`;
`CHORUS_APP_GROUP` prefixes it with `$(DEVELOPMENT_TEAM)`, and the build expands that one
value into both entitlements files and the `ChorusAppGroup` key of both `Info.plist` files.
The team reaches `xcodebuild` rather than XcodeGen, so the generated project names no team
and is identical for everyone.

Downloaded data lives under `Artifacts/` in that container. Only data belongs there —
libraries, tokenizers, voice definitions, and phonemizer data stay sealed in the signed
bundle.
