# Adding a provider

Create `Providers/<Name>`. Nothing outside that directory needs editing — the `Makefile`
derives everything from `PROVIDER`, and `project.yml` includes the fragment through
`${CHORUS_PROVIDER}`.

```text
Providers/<Name>/
├── LICENSE
├── README.md
├── Project.yml
├── App/            entry point, Info.plist, Entitlements.plist, Resources/Provider.json
├── Extension/      AVSpeechSynthesisProviderAudioUnit
├── Engine/         synthesis
└── BuildSupport/   dependency preparation
```

That derivation fixes three names:

| Convention | Becomes |
| --- | --- |
| `Providers/<Name>` | the value of `PROVIDER` |
| `Chorus<Name>` | scheme and container target |
| `Chorus <Name>` | `PRODUCT_NAME`, and so the `.app` and archive names |

## Requirements

- The app entry point loads `Provider.json` and calls `InstallerApplication.run`. Do not
  fork the installer for branding or copy — those come from the manifest.
- Set `CHORUS_GROUP_NAME` on both targets to the same value. Never write a team identifier;
  both entitlements files and both `Info.plist` files use `$(CHORUS_APP_GROUP)`.
- Declare every downloadable file in `Provider.json` with an HTTPS source, exact byte count,
  and SHA-256. Installation succeeds only when the complete set verifies.
- Pin external dependencies by version *and* checksum in the provider's `BuildSupport`.
- Add the provider and its license to `THIRD_PARTY_NOTICES.md`.

## Before submitting

Build unsigned, run `make test`, run `make render` if you touched the installer, and
validate a signed app and extension on a destination Mac.
