# Build configuration

Normal builds take two choices:

```sh
make debug APP=Chorus
make release APP=Kokoro
```

`APP` defaults to `Chorus`. Use `make debug` for Debug or `make release` for Release. Bare `make` runs Debug. Explicit Makefile targets invoke
XcodeGen and Xcode directly, with Bash scripts for resource preparation.
Xcode 26+ (Swift 6.2+) and XcodeGen 2.44+ are required. Kokoro preparation additionally
requires autoconf, automake, and libtool. The reader does not prepare provider dependencies.

## Ownership

| Configuration | Source |
| --- | --- |
| App name, scheme, bundle IDs, version, build number | `Hub/Project.yml` or `Providers/<App>/Project.yml` |
| Shared compiler settings and Debug/Release configurations | `BuildSupport/XcodeGen/Base.yml` |
| Optional signing team and identity | `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` environment variables |
| Project and build paths | `APP.xcodeproj` and `build/APP/` conventions |

Edit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` under `settings.base` in each
app's YAML. These native Xcode settings are inherited by the app and its extension; no Git
history calculation or version environment forwarding occurs. Increment the build number
before distributing a new binary. Project generation runs before each build so source
additions and configuration changes cannot leave an outdated project definition.

The generated project can be opened directly in Xcode; configure signing there separately
when building through its UI. No local team identifier is baked into generated project files.

## Signing

Set `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` in the environment. With both nonempty,
a build is signed; with either missing,
it is explicitly unsigned. Debug/Release controls compiler configuration
independently of signing. Configured signing failures stop the build instead of silently
falling back to unsigned output. Certificates and private keys stay in Keychain.

For a signed build:

```sh
DEVELOPMENT_TEAM=ABCDEFGHIJ CODE_SIGN_IDENTITY='Apple Development' make debug APP=Kokoro
```

To explicitly build without signing, regardless of the current shell environment:

```sh
env -u DEVELOPMENT_TEAM -u CODE_SIGN_IDENTITY make release APP=Chorus
env -u DEVELOPMENT_TEAM -u CODE_SIGN_IDENTITY make release APP=Kokoro
```

Unsigned archives are development artifacts, not notarized macOS distribution builds.
They may be blocked on another Mac, and the unsigned Kokoro extension is not a supported
system voice installation. Building with an Apple Development identity supports local
development but does not provide Developer ID distribution or notarization.

For general distribution, use a Developer ID Application identity and notarize the apps.
See [Apple's distribution guidance](https://developer.apple.com/developer-id/).
Provider App Group identifiers still derive from the signing team and configured group
name, matching the app's and extension's entitlements.

## Commands and outputs

- `make generate APP=Kokoro`: prepare required resources and generate `Kokoro.xcodeproj`.
- `make debug APP=Kokoro`: build in `build/Kokoro/Build/Products/Debug/`.
- `make release APP=Chorus`: build in `build/Chorus/Build/Products/Release/`.
- `make test`: reader and provider contract tests, plus plist validation.
- `make test-hub`: reader contract tests only.
- `make render APP=Chorus`: render reader views into `build/Chorus/`.
- `make render APP=Kokoro`: render the shared installer into `build/Kokoro/`.
- `make engine-smoke APP=Kokoro`: run inference with `KOKORO_MODEL_URL` set to a model file.
- `make clean APP=Kokoro`: remove only that app's generated project, build output, and
  archives. Downloaded dependencies remain cached.

There is no packaging command. Builds produce app bundles; creating release archives and
publishing them is a separate step. Release notes should identify the source commit, supported
architecture, and signing status. Remote release/model manifests and automatic updates are
not implemented.
