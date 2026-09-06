# Chorus

On-device text-to-speech voices for macOS. Each voice provider ships as a small app with a
speech synthesis extension, so its voices appear anywhere macOS speaks — VoiceOver, Spoken
Content, and any app using `AVSpeechSynthesizer`. Models are downloaded, verified, and
stored outside the signed app bundle.

The repository currently ships **Kokoro**: 41 voices across 7 languages, running entirely
on your Mac.

## Build

Requires macOS 14+ on Apple Silicon, Xcode, and:

```sh
brew install xcodegen autoconf automake libtool
```

```sh
make build-unsigned          # validates the full bundle
make build                   # signed; required for macOS to register the voices
make test                    # installer tests and plist validation
make package VERSION=0.1.0   # signed archive plus checksum in dist/
```

`make build` needs an Apple Developer team. Set `CHORUS_TEAM_ID` to your 10-character team
identifier, or leave it unset and it is read from your keychain — the build stops rather
than guess if you hold more than one. The app group, and therefore the container your model
installs into, derives from it, so a build signed with your own team stays entirely within
your own container.

After installing, enable the voice in System Settings → Accessibility → Spoken Content.

## Layout

| Path | Contents |
| --- | --- |
| `Packages/ChorusKit` | `ChorusProviderKit` (manifests, artifact store, downloads) and `ChorusInstallerUI` |
| `Providers/Kokoro` | Kokoro app, speech extension, engine, and native dependencies |
| `BuildSupport` | Shared brand assets and XcodeGen templates |
| `Documentation` | [Architecture](Documentation/Architecture.md) and [Adding a provider](Documentation/AddingAProvider.md) |

Providers are independently signed, versioned, and released. They share the installer but
no engine binaries, App Groups, or release schedules.

## License

Shared Chorus code — `Packages/ChorusKit`, `BuildSupport`, and the root build
configuration — is MIT; see [LICENSE](LICENSE).

`Providers/Kokoro` and the distributed **Chorus Kokoro** application are
**GPL-3.0-or-later**, because the speech extension statically links espeak-ng. MIT code may
be combined into it; the resulting application must satisfy GPL-3.0-or-later. Its full
license text is at [Providers/Kokoro/LICENSE](Providers/Kokoro/LICENSE) and ships inside
the app.

This also means Chorus Kokoro cannot go to the Mac App Store, whose terms conflict with
GPL-3.0. Store distribution would require replacing espeak-ng.

Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
which also carries the corresponding-source statement.
