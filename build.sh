#!/usr/bin/env bash
# build.sh — compile WindowSnapper and assemble a .app bundle.
#
# Requirements:
#   • Xcode Command Line Tools (xcode-select --install)
#   • macOS 13+, arm64 or x86_64
#
# Usage:
#   chmod +x build.sh && ./build.sh
#   open .build/WindowSnapper.app

set -euo pipefail

APP_NAME="WindowSnapper"
BUNDLE_ID="com.windowsnapper.app"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app/Contents"

SOURCES=(
    Sources/WindowSnapper/main.swift
    Sources/WindowSnapper/Models.swift
    Sources/WindowSnapper/WindowManager.swift
    Sources/WindowSnapper/GridView.swift
    Sources/WindowSnapper/GridOverlay.swift
    Sources/WindowSnapper/EventMonitor.swift
    Sources/WindowSnapper/AppDelegate.swift
)

# ── Clean ────────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

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
# Signing with a stable identity keeps Accessibility trust across rebuilds.
SIGN_ID=$(security find-identity -v -p codesigning | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -n "$SIGN_ID" ]; then
    echo "▶  Signing with: $SIGN_ID"
    codesign --force --sign "$SIGN_ID" --deep "$BUILD_DIR/$APP_NAME.app"
else
    echo "⚠️  No signing identity found — Accessibility trust won't persist across rebuilds."
    echo "   See README for setup instructions."
fi

# ── Install ────────────────────────────────────────────────────────────────
INSTALL_DIR="/Applications/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
rm -rf "$INSTALL_DIR"
cp -R "$BUILD_DIR/$APP_NAME.app" "$INSTALL_DIR"

echo ""
echo "✅  Built and installed: $INSTALL_DIR"
echo ""

open "$INSTALL_DIR"

echo "   First launch:  grant Accessibility permission when prompted."
echo "                  System Settings → Privacy & Security → Accessibility"
