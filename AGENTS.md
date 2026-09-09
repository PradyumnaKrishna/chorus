# Repository guidance

## Documentation

- Keep documentation clear, current, and concise.
- Document stable behavior that users or contributors need; omit internal history,
  speculative plans, and minor presentation details.
- Keep the README as an overview. Put usage in `Documentation/Reader.md`, build details in
  `Documentation/Building.md`, architecture in `Documentation/Architecture.md`, and
  provider-specific guidance in the provider's README.
- Link to the document that owns a topic instead of repeating it.
- Fold small updates into existing guidance and remove stale or duplicated text.
- Edit `THIRD_PARTY_NOTICES.md` only when dependencies or licensing change.

## Quality bar

Treat Chorus as a production-quality open-source project. Follow the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
and Apple's
[Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).
Prefer clear, direct Swift and native platform conventions. Add structure only when it
improves correctness, maintainability, testing, security, or accessibility.

## Verification

- Run `make test` for shared behavior or configuration changes.
- Build the affected app with `make debug APP=Chorus` or `make debug APP=Kokoro`.
- Run `make render APP=Kokoro` for provider installer layout changes.
- Run `git diff --check` before handing off changes.
