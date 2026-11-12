#!/bin/zsh
# Build, test and zip Slimey.app for a GitHub release: dist/Slimey-<version>.zip
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
./test.sh
VERSION=$VERSION ./build.sh
mkdir -p dist
rm -f "dist/Slimey-$VERSION.zip"
xattr -cr Slimey.app
codesign --verify --strict Slimey.app
ditto -c -k --norsrc --noextattr --keepParent Slimey.app "dist/Slimey-$VERSION.zip"
# Fail if any macOS metadata files slipped into the archive.
if unzip -l "dist/Slimey-$VERSION.zip" | grep -qE '/\._|__MACOSX'; then echo "zip contains macOS metadata files" >&2; exit 1; fi
shasum -a 256 "dist/Slimey-$VERSION.zip"
