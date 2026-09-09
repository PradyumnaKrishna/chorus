# Adding a provider

Create `Providers/<Name>/Project.yml` with `name: <Name>` and an explicitly declared
scheme named `<Name>`. `make debug APP=<Name>` selects it without changes to the shared
Makefile or a central provider table. The generated project is `<Name>.xcodeproj` and
build outputs live under `build/<Name>/`.

Use `Providers/Kokoro/Project.yml` as an example. Paths are repository-relative because
generation uses the repository as `--project-root`. Include `BuildSupport/XcodeGen/Base.yml`
with `relativePaths: false`. The scheme builds the containing app, which depends on the
extension. Keep the product name, bundle IDs, `MARKETING_VERSION`, and
`CURRENT_PROJECT_VERSION` in the provider YAML.

## Layout

```text
Providers/<Name>/
├── LICENSE
├── README.md
├── Project.yml
├── App/            entry point, Info.plist, Entitlements.plist, Resources/Provider.json
├── Extension/      AVSpeechSynthesisProviderAudioUnit
├── Engine/         synthesis
└── BuildSupport/   bootstrap.sh, dependencies, optional test-engine.sh
```

## Requirements

- Load `Provider.json` and call `InstallerApplication.run`; the descriptor supplies the
  installer branding and copy.
- Set the same `CHORUS_GROUP_NAME` on the app and extension. Both entitlements and
  Info.plists use `$(CHORUS_APP_GROUP)`. Keep team identifiers out of committed configuration.
- Declare each downloadable model artifact with an HTTPS source, exact byte count,
  SHA-256, and relative destination. Tokenizers, voices, and native code stay bundled.
- Pin dependency versions and checksums in provider-owned preparation scripts.
- Use `.artifacts/<Name>/Brand/AppIcon.xcassets` for the generated shared-brand icon.
- Add the provider and its license to `THIRD_PARTY_NOTICES.md`.

Before submitting, run `make debug APP=<Name>` and `make test`. Run
`make render APP=<Name>` for installer changes and verify signed voice registration on a Mac.
See [Building](Building.md) for signing.
