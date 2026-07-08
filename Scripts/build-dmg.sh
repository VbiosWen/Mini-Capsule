#!/bin/bash
# Mini Capsule — DMG build script
# Builds a signed and notarized DMG for direct distribution.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "==> Building ${APP_NAME} ${VERSION} for DMG distribution..."

# Step 1: Build and archive
echo "==> Archiving..."
xcodebuild archive \
    -project "${PROJECT_DIR}/Mini Capsule.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_DIR}/${APP_NAME}.xcarchive" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    CODE_SIGN_ENTITLEMENTS="${PROJECT_DIR}/Mini Capsule/Configs/DMG.entitlements" \
    CODE_SIGN_IDENTITY="Developer ID Application"

# Step 2: Export the .app from the archive
echo "==> Exporting .app..."
APP_PATH="${ARCHIVE_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"

# Step 3: Create DMG
echo "==> Creating DMG..."
DMG_PATH="${ARCHIVE_DIR}/${DMG_NAME}.dmg"
TMP_DMG="${ARCHIVE_DIR}/tmp.dmg"

hdiutil create -size 100m -fs HFS+ -volname "${APP_NAME}" "${TMP_DMG}"
hdiutil attach "${TMP_DMG}" -mountpoint "/Volumes/${APP_NAME}"

# Copy .app and Applications shortcut
cp -R "${APP_PATH}" "/Volumes/${APP_NAME}/"
ln -s /Applications "/Volumes/${APP_NAME}/Applications"

# Optional: set DMG background
if [ -f "${PROJECT_DIR}/Resources/dmg-background.png" ]; then
    mkdir -p "/Volumes/${APP_NAME}/.background"
    cp "${PROJECT_DIR}/Resources/dmg-background.png" "/Volumes/${APP_NAME}/.background/"
fi

hdiutil detach "/Volumes/${APP_NAME}"
hdiutil convert "${TMP_DMG}" -format UDZO -o "${DMG_PATH}"
rm -f "${TMP_DMG}"

# Step 4: Verify code signature
echo "==> Verifying code signature..."
codesign --deep --strict --verify --verbose=1 "${APP_PATH}"

# Step 5: Notarize
echo "==> Submitting for notarization..."
xcrun notarytool submit "${DMG_PATH}" \
    --team-id "${DEVELOPMENT_TEAM}" \
    --apple-id "${ASC_EMAIL}" \
    --password "${ASC_PASSWORD}" \
    --wait

# Step 6: Staple notarization ticket
echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "==> Done! DMG created at: ${DMG_PATH}"
