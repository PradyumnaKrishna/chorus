# Chorus reader

Chorus reads text using macOS voices and independently installed voice providers.
The soundwave menu-bar icon gives you playback controls even when the main window is closed.

## First playback

Place `Chorus.app` in `~/Applications` and open it. In **Text to speech**, paste a paragraph,
choose a macOS voice, adjust the speed, and start playback. Kokoro is optional; you do not
need to install a model to use the voices already available on your Mac.

## Build and verify

Use Xcode 26+ (Swift 6.2+) and XcodeGen; the app supports macOS 14+.

```sh
make debug APP=Chorus
make test
```

The reader is built at `build/Chorus/Build/Products/Debug/Chorus.app`.
`Chorus.xcodeproj` contains only the reader and its completion hook. Building it does
not prepare Kokoro dependencies. See [Build configuration](Building.md) for signing
and Release builds.

## Companion setup

Build the provider with `make debug APP=Kokoro`, configuring both signing values to
enable system voice registration. Place `Chorus Kokoro.app` in
`~/Applications`, then open it to install its model. Chorus's **Voice apps** page can
open the installed companion; it does not download, install, or remove apps.

Chorus Kokoro owns model download, verification, repair, and removal. Its model lives
under `Artifacts/` in its team-derived App Group container. Moving the companion to
Trash does not remove that model; use the companion's removal action first when needed.
Return to Chorus and refresh voices after setup. App presence and registered voice
availability are displayed separately; neither is presented as proof of model integrity.

## Reader behavior

- Closing the main window hides the Dock icon while playback and the soundwave menu stay
  available. Choose **Open Chorus** or **Settings…** in that menu to restore the window
  and Dock icon. Use **Quit Chorus** to exit the app.
- Paste text, choose a voice, and read, pause, resume, or stop. Stop clears the completion queue.
- While reading, macOS Now Playing and the keyboard media key can pause and resume speech,
  including when the main window is closed. Finishing or stopping clears Now Playing.
- Choose Compact, Full, or Disabled floating player in Settings. Kokoro uses Compact
  because its estimated timing is unsuitable for word highlighting. macOS voices support it.
- Control–Option–Command–P toggles the floating player. Command–period stops speech and
  clears the queue globally. Hide preserves playback.
- Selection reading is opt-in on the floating player and requires Accessibility permission.
  It resets at launch; hiding the player disables it. Clipboard and full-document reads
  are not used for selection monitoring.
- Integrations install their Chorus hook once after confirmation while preserving unrelated
  settings and hooks. Turning listening off leaves that configuration in place. Manual instructions
  remain available until setup is detected. Only final completion text is queued locally. Markdown formatting,
  link destinations, harness UI directives, and fenced code are removed before speech.
  Custom `CODEX_HOME` and `CLAUDE_CONFIG_DIR` locations are respected when available to Chorus.

`make test` checks completion input filtering, Unicode highlighting, voice classification,
and selection debounce. Native playback, global shortcuts, Accessibility permissions, and
provider registration should also be exercised on a destination Mac.

## CLI integrations

Open **Integrations** and enable the CLI you want to connect. Confirm setup, then restart the
CLI. Chorus merges its hook into the user-level settings and preserves unrelated configuration.
These integrations are for CLI sessions, not desktop assistant applications. If automatic
setup fails, Chorus opens manual instructions with the generated configuration.

Preserve existing hooks when merging the generated JSON. Codex uses its main-thread `Stop`
hook instead of the broader legacy `notify` callback, so title generation, subagents, and
other internal completions are not queued.

## Troubleshooting

- **Missing Kokoro voices:** open the companion, complete installation or repair, then
  refresh voices in Chorus. Confirm you are using a signed provider build.
- **Wrong companion opens:** Chorus prefers `~/Applications/Chorus Kokoro.app`, then
  `/Applications/Chorus Kokoro.app`, then macOS's registered location. Keep the intended
  copy in `~/Applications` and quit old copies.
- **Selection reading does nothing:** enable it on the floating player and check Chorus's
  Accessibility permission. The source app must expose selected text through Accessibility.
- **No highlighting with Kokoro:** this is expected; use a macOS voice for word highlighting.
- **Player shortcut unavailable:** check Settings and whether another app uses the same
  shortcut. The soundwave menu can still show the player.
- **Downloaded app blocked:** check the release's signing notes. Unsigned and development-signed
  builds are not notarized distribution builds. Do not disable system-wide security protections.

## Future hosted manifests (not implemented)

A hosted release catalog can describe reader and companion app updates independently:
schema version, bundle identifier, app version/build, minimum macOS version, architecture,
HTTPS archive URL, byte count, checksum, and expected signing identity.

Each companion can own a separate model manifest derived from its existing `Provider.json`:
model revision, engine compatibility, and the verified artifact list. Model updates must
remain compatible with the installed engine and bundled tokenizer/voice resources. Keep
local installation metadata so changing a feed cannot change which files an uninstall owns.

Before enabling remote feeds, specify authenticity verification, rollback behavior, and
atomic update semantics. HTTPS and checksums alone do not establish release authorship.
The embedded provider manifest remains authoritative in this version; no remote manifest
is fetched and no executable download flow is included.
