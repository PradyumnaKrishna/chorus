# Adding a provider

Create `Providers/<Name>/Project.yml` with `name: <Name>` and an explicitly declared
scheme named `<Name>`. `make debug APP=<Name>` selects it without changes to the shared
Makefile or a central provider table. The generated project is `<Name>.xcodeproj` and
build outputs live under `build/<Name>/`.

Use `Providers/Kokoro/Project.yml` as an example. Paths are repository-relative because
generation supplies the repository as `--project-root`. Include
`BuildSupport/XcodeGen/Base.yml` with `relativePaths: false`. The selected scheme's first
build target must be the containing application; its dependencies build the extension.

Declare `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` under `settings.base`,
inherited by the app and extension.
Declare the app's product name and bundle IDs
in YAML; these do not need matching Makefile variables. The scheme must provide
Debug and Release configurations through the shared base.

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

- Load `Provider.json` and call `InstallerApplication.run`; shared installer branding
  and copy come from the descriptor.
- Set the same `CHORUS_GROUP_NAME` on the app and extension. Both entitlements and
  Info.plists use `$(CHORUS_APP_GROUP)`. Keep team identifiers out of committed configuration.
- Declare each downloadable model artifact with an HTTPS source, exact byte count,
  SHA-256, and relative destination. Tokenizers, voices, and native code stay bundled.
- Pin dependency versions and checksums in provider-owned preparation scripts.
- Use `.artifacts/<Name>/Brand/AppIcon.xcassets` for the generated shared-brand icon.
- Add the provider and its license to `THIRD_PARTY_NOTICES.md`.

Before submitting, run `make debug APP=<Name>`, `make test`, and
`make render APP=<Name>` for installer changes. Verify signed voice registration on a
destination Mac. See [Building](Building.md) for optional signing configuration.
