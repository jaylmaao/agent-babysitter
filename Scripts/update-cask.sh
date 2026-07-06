#!/bin/bash
# Stamp the Homebrew cask with a release's version and DMG sha256.
#   Scripts/update-cask.sh 0.8.0 build/AgentBabysitter-0.8.0.dmg
# Then copy Packaging/homebrew/Casks/agent-babysitter.rb into the
# jaylmaao/homebrew-tap repo (Casks/) and push — that publishes it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: update-cask.sh <version> <dmg-path>}"
DMG="${2:?usage: update-cask.sh <version> <dmg-path>}"
CASK="Packaging/homebrew/Casks/agent-babysitter.rb"

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" "$CASK"
echo "Stamped $CASK: version=$VERSION sha256=$SHA"
