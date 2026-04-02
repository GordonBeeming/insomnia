#!/usr/bin/env bash
# =============================================================================
# package-for-homebrew.sh — Prepare Insomnia CLI for Homebrew distribution
#
# Creates a tar.gz archive of the CLI binary, computes its SHA256 checksum,
# and prints ready-to-paste Homebrew formula and cask stanzas.
#
# Usage:
#   ./Scripts/package-for-homebrew.sh <version>
#
# Example:
#   ./Scripts/package-for-homebrew.sh 1.2.0
#
# Prerequisites:
#   - The CLI binary must already exist in Distribution/ (run build-release.sh first)
#   - shasum (ships with macOS)
# =============================================================================

# --- Safety flags ------------------------------------------------------------
# -e  Exit immediately on error
# -u  Error on unset variables
# -o pipefail  Propagate pipe failures
set -euo pipefail

# --- Resolve project root ----------------------------------------------------
# Absolute path to this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is one level above Scripts/
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Validate arguments ------------------------------------------------------
# Exactly one argument is required: the version string (e.g., "1.2.0")
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 1.2.0" >&2
  exit 1
fi

# VERSION: semantic version string used in archive name and formula output
VERSION="$1"

# --- Validate version format --------------------------------------------------
# Accept major.minor (e.g., "0.3") or major.minor.patch (e.g., "1.2.3")
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "❌ Invalid version format: '${VERSION}'" >&2
  echo "   Expected format like 0.3 or 1.2.3" >&2
  exit 1
fi

# --- Configuration -----------------------------------------------------------
# Name of the CLI binary (must match the target name in Package.swift)
CLI_NAME="insomnia"
# Directory containing built release artifacts
DIST_DIR="${PROJECT_ROOT}/Distribution"
# Full path to the CLI binary
CLI_BIN="${DIST_DIR}/${CLI_NAME}"
# GitHub repository slug — used to construct download URLs
REPO="gordonbeeming/insomnia"
# Name for the output archive
ARCHIVE_NAME="${CLI_NAME}-${VERSION}-arm64-apple-macosx.tar.gz"
# Full path to the output archive
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

# --- Verify the CLI binary exists --------------------------------------------
if [[ ! -f "${CLI_BIN}" ]]; then
  echo "❌ CLI binary not found at ${CLI_BIN}" >&2
  echo "   Run Scripts/build-release.sh first." >&2
  exit 1
fi

# =============================================================================
# Step 1: Create a tar.gz archive of the CLI binary
# =============================================================================
echo "📦 Creating archive: ${ARCHIVE_NAME}..."

# -C changes into the directory so the archive contains just the binary name
# -czf creates a gzip-compressed tar archive
tar -C "${DIST_DIR}" -czf "${ARCHIVE_PATH}" "${CLI_NAME}"

echo "✅ Archive created → ${ARCHIVE_PATH}"

# =============================================================================
# Step 2: Compute SHA256 checksum
# =============================================================================
# Homebrew requires a SHA256 hash to verify download integrity
# shasum -a 256 produces the hash; awk extracts just the hex string
SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"

echo "🔑 SHA256: ${SHA256}"

# =============================================================================
# Step 3: Print Homebrew formula stanza (for CLI — tap formula)
# =============================================================================
# This is the Ruby code that goes into a Homebrew formula file.
# The formula tells Homebrew how to download, verify, and install the CLI.
echo ""
echo "========================================="
echo "  Homebrew Formula (paste into formula.rb)"
echo "========================================="
cat <<FORMULA

class Insomnia < Formula
  # Human-readable description shown in 'brew info'
  desc "CLI tool to keep your Mac awake"
  # Project homepage
  homepage "https://github.com/${REPO}"
  # Download URL pointing to the GitHub release asset
  url "https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE_NAME}"
  # SHA256 checksum for download verification
  sha256 "${SHA256}"
  # MIT license identifier
  license "MIT"

  def install
    # Install the binary into Homebrew's bin directory
    bin.install "${CLI_NAME}"
  end

  test do
    # Verify the binary runs and prints version info
    assert_match "${VERSION}", shell_output("#{bin}/${CLI_NAME} --version")
  end
end
FORMULA

# =============================================================================
# Step 4: Print Homebrew cask stanza (for GUI — .app bundle)
# =============================================================================
# Casks are used for macOS .app bundles distributed as DMGs or zips.
echo ""
echo "========================================="
echo "  Homebrew Cask (paste into cask.rb)"
echo "========================================="
cat <<CASK

cask "insomnia" do
  # Version number — Homebrew uses this to check for updates
  version "${VERSION}"
  # SHA256 of the DMG file (replace with actual DMG hash before publishing)
  sha256 "REPLACE_WITH_DMG_SHA256"

  # Download URL for the DMG release asset
  url "https://github.com/${REPO}/releases/download/v#{version}/Insomnia-#{version}.dmg"
  # Human-readable name
  name "Insomnia"
  # Project homepage
  homepage "https://github.com/${REPO}"

  # Install the .app bundle into /Applications
  app "Insomnia.app"
end
CASK

# =============================================================================
# Step 5: Print next steps for the maintainer
# =============================================================================
echo ""
echo "========================================="
echo "  Next steps"
echo "========================================="
echo "  1. Upload ${ARCHIVE_NAME} to the GitHub release for v${VERSION}"
echo "  2. If distributing the GUI, create a DMG and update the cask SHA256"
echo "  3. Copy the formula/cask stanzas into your Homebrew tap repository"
echo "  4. Test with: brew install --build-from-source <tap>/${CLI_NAME}"
echo "  5. Push the tap and verify: brew install <tap>/${CLI_NAME}"
