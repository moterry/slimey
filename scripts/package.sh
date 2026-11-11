#!/bin/zsh
# Build, test and zip Slimey.app for a GitHub release: dist/Slimey-<version>.zip
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
./test.sh
VERSION=$VERSION ./build.sh
mkdir -p dist
rm -f "dist/Slimey-$VERSION.zip"
ditto -c -k --keepParent Slimey.app "dist/Slimey-$VERSION.zip"
shasum -a 256 "dist/Slimey-$VERSION.zip"
