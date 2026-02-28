#!/usr/bin/env bash
# release.sh — build Zoned.app and package a release ZIP for Homebrew distribution.
#
# Usage:
#   chmod +x release.sh && ./release.sh
#
# Output:
#   .release/Zoned-<version>.zip  (upload to GitHub Releases)

set -euo pipefail

APP_NAME="Zoned"
BUILD_DIR=".build"
RELEASE_DIR=".release"
APP_DIR="$BUILD_DIR/$APP_NAME.app/Contents"

SOURCES=(
    Sources/WindowSnapper/main.swift
    Sources/WindowSnapper/Models.swift
    Sources/WindowSnapper/KeyCodeMapping.swift
    Sources/WindowSnapper/KeyBindingSettings.swift
    Sources/WindowSnapper/KeyRecorderView.swift
    Sources/WindowSnapper/PreferencesWindowController.swift
    Sources/WindowSnapper/WindowManager.swift
    Sources/WindowSnapper/GridView.swift
    Sources/WindowSnapper/GridOverlay.swift
    Sources/WindowSnapper/EventMonitor.swift
    Sources/WindowSnapper/AppDelegate.swift
)

# ── Clean ────────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"
mkdir -p "$RELEASE_DIR"

echo "▶  Compiling…"

# Detect host architecture
ARCH=$(uname -m)
case "$ARCH" in
    arm64)  TARGET="arm64-apple-macos13.0" ;;
    x86_64) TARGET="x86_64-apple-macos13.0" ;;
    *)      echo "Unknown architecture: $ARCH"; exit 1 ;;
esac

swiftc \
    -target "$TARGET" \
    -framework AppKit \
    -framework Carbon \
    -framework ApplicationServices \
    -O \
    "${SOURCES[@]}" \
    -o "$APP_DIR/MacOS/$APP_NAME"

# ── Bundle ───────────────────────────────────────────────────────────────────
cp Resources/Info.plist "$APP_DIR/Info.plist"

# ── Code Sign ────────────────────────────────────────────────────────────────
SIGN_ID=$(security find-identity -v -p codesigning | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -n "$SIGN_ID" ]; then
    echo "▶  Signing with: $SIGN_ID"
    codesign --force --sign "$SIGN_ID" --deep "$BUILD_DIR/$APP_NAME.app"
else
    echo "⚠️  No signing identity found — users may see Gatekeeper warnings."
fi

# ── Package ──────────────────────────────────────────────────────────────────
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Info.plist")
ZIP_NAME="Zoned-${VERSION}.zip"

ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/$APP_NAME.app" "$RELEASE_DIR/$ZIP_NAME"
SHA=$(shasum -a 256 "$RELEASE_DIR/$ZIP_NAME" | awk '{print $1}')

echo ""
echo "✅  $RELEASE_DIR/$ZIP_NAME"
echo "    SHA-256: $SHA"
echo "    Version: $VERSION"
echo ""
echo "Next steps:"
echo "  1. git tag v$VERSION && git push --tags"
echo "  2. GitHub → Releases → create release from tag v$VERSION"
echo "  3. Upload $RELEASE_DIR/$ZIP_NAME to the release"
echo "  4. Update sha256 and version in homebrew-zoned/Casks/zoned.rb"
echo "  5. Push the tap repo"
