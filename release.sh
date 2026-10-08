#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
VERSION="$(tr -d '[:space:]' < VERSION)"

NOTES="${1:-自动随航 ${VERSION}}"
gh release create "v${VERSION}" release/AutoSidecar.app.zip \
  --repo RyanJC0416/AutoSidecar \
  --title "${VERSION}" \
  --notes "$NOTES"
echo "Released v${VERSION}"
