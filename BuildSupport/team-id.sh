#!/bin/bash
# Prints the Apple Developer team identifier to sign with.
#
# The OU field of an Apple Development certificate is the team identifier. We
# refuse to guess when the keychain holds more than one, because picking the
# wrong team silently changes the app group container path — and that path is
# baked into every installed user's machine.
set -euo pipefail

if [ -n "${CHORUS_TEAM_ID:-}" ]; then
  echo "$CHORUS_TEAM_ID"
  exit 0
fi

teams="$(security find-certificate -c "Apple Development" -a -p 2>/dev/null \
  | openssl storeutl -noout -text /dev/stdin 2>/dev/null \
  | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | sort -u || true)"

count="$(printf '%s' "$teams" | grep -c . || true)"

case "$count" in
  1) echo "$teams" ;;
  0) echo "No Apple Development certificate found. Set CHORUS_TEAM_ID explicitly." >&2; exit 1 ;;
  *) {
       echo "Multiple signing teams found:"
       echo "$teams" | sed 's/^/  /'
       echo "Set CHORUS_TEAM_ID to the one you are releasing under."
     } >&2
     exit 1 ;;
esac
