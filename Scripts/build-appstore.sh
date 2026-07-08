#!/bin/bash
# Mini Capsule — App Store build script
# Builds and exports a .pkg for Mac App Store submission.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "==> Building ${APP_NAME} ${VERSION} for App Store distribution..."

# Step 1: Build and archive with App Store entitlements
echo "==> Archiving..."
xcodebuild archive \
    -project "${PROJECT_DIR}/Mini Capsule.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_DIR}/${APP_NAME}-AppStore.xcarchive" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    CODE_SIGN_ENTITLEMENTS="${PROJECT_DIR}/Mini Capsule/Configs/AppStore.entitlements" \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    OTHER_CODE_SIGN_FLAGS="--options=runtime"

# Step 2: Export .pkg for App Store Connect
echo "==> Exporting .pkg..."
EXPORT_PLIST="${ARCHIVE_DIR}/exportOptions.plist"

cat > "${EXPORT_PLIST}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_DIR}/${APP_NAME}-AppStore.xcarchive" \
    -exportPath "${ARCHIVE_DIR}/${APP_NAME}-AppStore" \
    -exportOptionsPlist "${EXPORT_PLIST}"

PKG_PATH="${ARCHIVE_DIR}/${APP_NAME}-AppStore/${APP_NAME}.pkg"

# Step 3: Validate the package
echo "==> Validating .pkg..."
xcrun altool --validate-app \
    -f "${PKG_PATH}" \
    -t macOS \
    -u "${ASC_EMAIL}" \
    -p "${ASC_PASSWORD}"

# Step 4: Upload to App Store Connect
echo "==> Uploading to App Store Connect..."
xcrun altool --upload-app \
    -f "${PKG_PATH}" \
    -t macOS \
    -u "${ASC_EMAIL}" \
    -p "${ASC_PASSWORD}"

echo "==> Done! .pkg uploaded to App Store Connect."
