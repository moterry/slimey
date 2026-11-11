#!/bin/zsh
# Render the demo video (en + zh MP4s, a README GIF and posters) into media/.
# Pass "frames" to render a handful of key frames instead.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -framework AppKit -framework WebKit -framework ServiceManagement -framework AVFoundation \
    Sources/SlimeCore/*.swift $(ls Sources/Slimey/*.swift | grep -v '/main.swift$') tools/video/main.swift \
    -o .build/make-video
.build/make-video "${OUT:-media}" "${1:-all}"
