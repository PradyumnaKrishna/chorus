# Build configuration

## Requirements

- Xcode 26+ with Swift 6.2+
- XcodeGen 2.44+
- Apple Silicon, autoconf, automake, and libtool for Kokoro

```sh
brew install xcodegen autoconf automake libtool
```

## Build

```sh
make debug APP=Chorus
make release APP=Kokoro
```

`APP` defaults to `Chorus`; bare `make` creates a Debug build. Each build regenerates the
selected Xcode project and keeps output under `build/<App>/`.

### Commands

| Command | Result |
| --- | --- |
| `make debug APP=Kokoro` | Debug app in `build/Kokoro/Build/Products/Debug/` |
| `make release APP=Chorus` | Release app in `build/Chorus/Build/Products/Release/` |
| `make generate APP=Kokoro` | Prepared resources and `Kokoro.xcodeproj` |
| `make test` | Reader, provider, package, and plist checks |
| `make render APP=Kokoro` | Installer snapshots in `build/Kokoro/` |
| `make engine-smoke APP=Kokoro` | Inference using `KOKORO_MODEL_URL` |
| `make clean APP=<App>` | Generated project, build, and archive output for that app |

## Signing

Set both signing values in the environment:

For a signed build:

```sh
DEVELOPMENT_TEAM=ABCDEFGHIJ CODE_SIGN_IDENTITY='Apple Development' make debug APP=Kokoro
```

If either value is missing, the build is explicitly unsigned. To ignore values from the
current shell:

```sh
env -u DEVELOPMENT_TEAM -u CODE_SIGN_IDENTITY make release APP=Chorus
env -u DEVELOPMENT_TEAM -u CODE_SIGN_IDENTITY make release APP=Kokoro
```

Unsigned apps are development artifacts and may be blocked on another Mac. Kokoro requires
signing for system voice registration. Apple Development signing supports local testing;
distribution requires Developer ID signing and notarization. See
[Apple's distribution guidance](https://developer.apple.com/developer-id/).

## Configuration ownership

| Configuration | Source |
| --- | --- |
| App name, scheme, bundle IDs, version, build number | `Hub/Project.yml` or `Providers/<App>/Project.yml` |
| Shared compiler settings | `BuildSupport/XcodeGen/Base.yml` |
| Signing team and identity | Build environment |

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the app's `Project.yml` before
distribution. The app and extension inherit those values. Generated projects contain no
developer team and can be opened directly in Xcode.

There is no packaging or publishing command. Release notes should identify the source commit,
supported architecture, and signing status.
