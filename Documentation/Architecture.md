# Architecture

## Product boundary

The Chorus reader (`Hub`) uses macOS speech APIs. Its bundled helper (`CLI`) receives coding
assistant completions, and both share `ChorusIntegrationKit`. The reader can open provider
companions but does not install their models or access their containers.

CLI integrations use main-thread `Stop` hooks and reject subagent lifecycle events. The
Codex parser retains legacy `notify` compatibility for existing installations. The reader
merges its command into user-level settings and falls back to manual setup for unsupported
files. `SpeechText` converts completion Markdown to plain text before queueing it. Manual
text and Accessibility selections remain literal.

`ChorusIntegrationKit` is a separate Swift package target so the hook and reader consume
one tested contract.

Each app's `Project.yml` declares its own project, scheme, version, and build number.
Projects and build outputs are generated independently. See [Building](Building.md).

Each provider is a containing app with exactly one speech synthesis extension:

```text
Chorus Kokoro.app
├── Contents/MacOS/Chorus Kokoro          installer
└── Contents/PlugIns/KokoroSynthesizer.appex   engine + voices
```

The app installs the model; the extension speaks. Word highlighting uses model timing output,
but older models without timings still support speech.

## ChorusKit

The shared package separates extension-safe code from UI code:

- **`ChorusProviderKit`** — Foundation-only manifests, downloads, and artifact storage.
- **`ChorusInstallerUI`** — AppKit and SwiftUI installer UI.
- **`ChorusIntegrationKit`** — completion parsing and hook configuration.

The provider app and extension use the same `Provider.json`, so artifact layout has one source
of truth.

## Installer contract

`ProviderDescriptor` defines the provider and its artifacts. Each artifact has an identifier,
HTTPS source, relative destination, byte count, and SHA-256 digest.

`ArtifactStore` reports absent, outdated, or installed rather than a boolean, so a manifest
declaring a new artifact offers an upgrade instead of appearing uninstalled.

Install and repair verify all downloads before replacing existing files. Failed commits restore
the previous files. Uninstall removes only paths declared by the installed provider.

## App group and signing

No development team is committed. Providers declare `CHORUS_GROUP_NAME`; the build prefixes
it with `$(DEVELOPMENT_TEAM)` and applies the resulting App Group to the app and extension.
This gives each signing team its own container without changing generated project files.

Downloaded data lives under `Artifacts/` in that container. Only data belongs there —
libraries, tokenizers, voice definitions, and phonemizer data stay sealed in the signed
bundle.
