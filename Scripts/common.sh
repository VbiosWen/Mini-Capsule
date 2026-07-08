#!/bin/bash
# Mini Capsule — shared build variables
# Replace the placeholders below with your own values.

set -euo pipefail

# === REPLACE ME: Your Apple Developer Team ID ===
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"

# === REPLACE ME: Your app's Bundle Identifier ===
export BUNDLE_ID="com.yourcompany.Mini-Capsule"

# === REPLACE ME: App Store Connect credentials (for App Store upload) ===
export ASC_EMAIL="you@example.com"
# Use @keychain:AC_PASSWORD to store securely, or set APP_SPECIFIC_PASSWORD
export ASC_PASSWORD="@keychain:AC_PASSWORD"

# === Project settings (usually no need to change) ===
export APP_NAME="Mini Capsule"
export VERSION="1.0"
export PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SCHEME="Mini Capsule"
export ARCHIVE_DIR="${PROJECT_DIR}/build"
export DMG_NAME="${APP_NAME}-${VERSION}"
