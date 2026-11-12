#!/bin/zsh
# Build Slimey.app (universal: Apple silicon + Intel) with plain swiftc.
set -e
cd "$(dirname "$0")"
APP="Slimey.app"
VERSION="${VERSION:-0.1.0}"
mkdir -p .build
for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos13 -framework AppKit -framework WebKit -framework ServiceManagement \
        Sources/SlimeCore/*.swift Sources/Slimey/*.swift -o .build/Slimey-$arch
done
lipo -create .build/Slimey-arm64 .build/Slimey-x86_64 -output .build/Slimey
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/Slimey "$APP/Contents/MacOS/Slimey"
cp hooks/hook.sh "$APP/Contents/Resources/hook.sh"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Slimey</string>
    <key>CFBundleDisplayName</key><string>Slimey</string>
    <key>CFBundleIdentifier</key><string>io.github.moterry.slimey</string>
    <key>CFBundleExecutable</key><string>Slimey</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
