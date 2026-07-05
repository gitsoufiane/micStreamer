#!/usr/bin/env zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

./scripts/build-app.sh

app="$root/.build/release/MicStreamer.app"
dmg="$root/.build/release/MicStreamer.dmg"
stage="$(mktemp -d "${TMPDIR:-/tmp}/micstreamer-dmg.XXXXXX")"
trap 'rm -R "$stage"' EXIT

ditto "$app" "$stage/MicStreamer.app"
ln -s /Applications "$stage/Applications"

hdiutil create \
	-volname "MicStreamer" \
	-srcfolder "$stage" \
	-ov \
	-format UDZO \
	"$dmg"

echo "$dmg"
