#!/usr/bin/env bash
# =============================================================================
# build-release.sh — Build release artifacts for Insomnia
#
# Compiles the CLI binary (universal or arm64) and constructs a .app bundle
# for the GUI target.  All output lands in the Distribution/ directory at the
# project root.
#
# Usage:
#   ./Scripts/build-release.sh
#
# Prerequisites:
#   - Xcode command-line tools (swift, xcodebuild)
#   - Run from the project root, or the script will cd there automatically
# =============================================================================

# --- Safety flags ------------------------------------------------------------
# -e  Exit immediately if any command fails
# -u  Treat unset variables as errors
# -o pipefail  Fail the pipeline if any piped command fails
set -euo pipefail

# --- Resolve project root ----------------------------------------------------
# SCRIPT_DIR: absolute path to the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT: one level up from Scripts/
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Work from the project root so all relative paths are predictable
cd "${PROJECT_ROOT}"

# --- Configuration -----------------------------------------------------------
# Output directory for all release artifacts
DIST_DIR="${PROJECT_ROOT}/Distribution"
# Name of the CLI executable target defined in Package.swift
CLI_TARGET="InsomniaCLI"
# Name of the GUI executable target defined in Package.swift
GUI_TARGET="Insomnia"
# Architecture to build for (Apple Silicon)
ARCH="arm64"
# Build configuration — Release enables optimizations and strips debug symbols
BUILD_CONFIG="release"

# --- Clean previous artifacts ------------------------------------------------
echo "🧹 Cleaning previous Distribution/ contents..."
# Remove and recreate to guarantee a fresh output directory
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# =============================================================================
# Step 1: Build the CLI binary
# =============================================================================
echo "🔨 Building CLI target '${CLI_TARGET}' for ${ARCH} (${BUILD_CONFIG})..."

# swift build compiles the SPM package
# -c release        → optimized build with no debug info
# --product          → build only the specified executable target
# --arch             → target architecture (arm64 for Apple Silicon)
swift build \
  -c "${BUILD_CONFIG}" \
  --product "${CLI_TARGET}" \
  --arch "${ARCH}"

# Locate the compiled CLI binary inside SPM's build directory
CLI_BIN_PATH="$(swift build -c "${BUILD_CONFIG}" --product "${CLI_TARGET}" --arch "${ARCH}" --show-bin-path)/${CLI_TARGET}"

# Verify the binary was actually produced
if [[ ! -f "${CLI_BIN_PATH}" ]]; then
  echo "❌ CLI binary not found at ${CLI_BIN_PATH}" >&2
  exit 1
fi

# Copy the CLI binary to the distribution directory, renamed to 'insomnia'
# for a cleaner user-facing command name
cp "${CLI_BIN_PATH}" "${DIST_DIR}/insomnia"
echo "✅ CLI binary → ${DIST_DIR}/insomnia"

# =============================================================================
# Step 2: Build the GUI app
# =============================================================================
echo "🔨 Building GUI target '${GUI_TARGET}' for ${ARCH} (${BUILD_CONFIG})..."

# Build the GUI executable via SPM (same as CLI but different product)
swift build \
  -c "${BUILD_CONFIG}" \
  --product "${GUI_TARGET}" \
  --arch "${ARCH}"

# Locate the compiled GUI binary
GUI_BIN_PATH="$(swift build -c "${BUILD_CONFIG}" --product "${GUI_TARGET}" --arch "${ARCH}" --show-bin-path)/${GUI_TARGET}"

# Verify the GUI binary exists
if [[ ! -f "${GUI_BIN_PATH}" ]]; then
  echo "❌ GUI binary not found at ${GUI_BIN_PATH}" >&2
  exit 1
fi

# =============================================================================
# Step 3: Create .app bundle structure
# =============================================================================
# macOS expects a specific directory layout for application bundles:
#   Insomnia.app/
#   └── Contents/
#       ├── Info.plist      ← app metadata (bundle ID, version, etc.)
#       ├── MacOS/
#       │   └── Insomnia    ← the actual executable
#       └── Resources/      ← icons, assets, localization files
APP_BUNDLE="${DIST_DIR}/${GUI_TARGET}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📦 Creating .app bundle at ${APP_BUNDLE}..."

# Create the required directory structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy the GUI executable into the MacOS directory
cp "${GUI_BIN_PATH}" "${MACOS_DIR}/${GUI_TARGET}"

# Copy the app icon into the Resources directory
if [[ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]]; then
  cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  echo "✅ App icon → ${RESOURCES_DIR}/AppIcon.icns"
fi

# --- Generate Info.plist -----------------------------------------------------
# Info.plist tells macOS how to launch and identify the application.
# CFBundleIdentifier  — reverse-DNS unique app identifier
# CFBundleName        — human-readable app name
# CFBundleExecutable  — filename of the binary in Contents/MacOS/
# CFBundleVersion     — build number (will be overridden by CI for releases)
# LSUIElement         — 1 = agent app (menu bar only, no Dock icon)
# NSHighResolutionCapable — enable Retina display support
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.gordonbeeming.insomnia</string>
    <key>CFBundleName</key>
    <string>${GUI_TARGET}</string>
    <key>CFBundleExecutable</key>
    <string>${GUI_TARGET}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

echo "✅ .app bundle → ${APP_BUNDLE}"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================="
echo "  Release build complete"
echo "========================================="
echo "  CLI binary:  ${DIST_DIR}/insomnia"
echo "  GUI app:     ${APP_BUNDLE}"
echo "========================================="
echo ""
echo "ℹ️  Next steps:"
echo "  • Sign with: codesign --deep --force --sign 'Developer ID Application: ...' ${APP_BUNDLE}"
echo "  • Notarize with: xcrun notarytool submit ..."
echo "  • Package with: hdiutil create -volname Insomnia -srcfolder ${APP_BUNDLE} ..."
