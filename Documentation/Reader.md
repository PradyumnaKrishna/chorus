# Chorus reader

Chorus reads text with macOS voices and optional voice providers such as Kokoro.

## First playback

Place `Chorus.app` in `~/Applications` and open it. In **Text to speech**, paste a paragraph,
choose a voice, adjust the speed, and select **Read aloud**. Built-in voices work without Kokoro.
See the [Kokoro guide](../Providers/Kokoro/README.md) to add neural voices.

## Reader behavior

- Closing the window hides the Dock icon; playback and menu-bar controls remain active.
  Choose **Open Chorus** to restore the window or **Quit Chorus** to exit.
- Pause and resume with Chorus, the floating player, or the keyboard media key.
- Choose Compact, Full, or Disabled floating player in **Settings**.
- Control–Option–Command–P toggles the player. Command–period stops speech and clears the
  completion queue. Hiding the player does not stop speech.
- Selection reading is opt-in on the floating player and requires Accessibility permission.
  It resets at launch, and hiding the player disables it.

## CLI integrations

Open **Integrations**, enable Codex or Claude Code, and confirm setup. Restart the CLI, then
approve the Chorus hook in Codex's `/hooks` screen or Claude Code's security prompt. If setup
fails, Chorus displays the configuration to merge manually. Existing settings are preserved.

Integrations apply to CLI sessions. Turning one off pauses reading without removing its hook.
Only the main turn's final answer is queued, and formatting and code are omitted from speech.
Custom `CODEX_HOME` and `CLAUDE_CONFIG_DIR` locations are supported.

## Troubleshooting

- **Missing Kokoro voices:** open the companion, install or repair the model, then refresh
  voices in Chorus. Confirm that the companion is signed.
- **Wrong companion opens:** Chorus prefers `~/Applications/Chorus Kokoro.app`, then
  `/Applications/Chorus Kokoro.app`, then macOS's registered location.
- **Selection reading does nothing:** enable it on the floating player and check Chorus's
  Accessibility permission. The source app must expose selected text through Accessibility.
- **No highlighting with Kokoro:** open the companion and choose **Upgrade** if it offers one.
- **Player shortcut unavailable:** another app may already use it; use the menu-bar player.
- **Downloaded app blocked:** use a signed, notarized distribution build. Do not disable
  system-wide security protections.
