#!/bin/bash
set -euo pipefail

[ -f .env.local ] && source .env.local

APP_NAME="SimpleLime"
BUNDLE_ID="com.whitehappypony.SimpleLime"
DISPLAY_NAME="SimpleLime"
VERSION="0.3.4"
BUILD="1"
MIN_OS="13.0"
IDENTITY="${IDENTITY:-Developer ID Application: Alex Malikov (525W3628D2)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"

APP="${APP_NAME}.app"
DMG="${APP_NAME}.dmg"
BINARY=".build/apple/Products/Release/${APP_NAME}"
ICON="Resources/AppIcon.icns"
CLI="Resources/simplelime"

step() {
    echo ""
    echo "── $1"
}

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

case "${1:-release}" in

build)
    step "Building universal binary"
    swift build -c release --arch arm64 --arch x86_64
    ;;

app)
    bash "${SELF}" build
    step "Creating ${APP}"
    rm -rf "${APP}"
    mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
    cp "${BINARY}" "${APP}/Contents/MacOS/"
    [ -f "${ICON}" ] && cp "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
    if [ -f "${CLI}" ]; then
        cp "${CLI}" "${APP}/Contents/Resources/simplelime"
        chmod +x "${APP}/Contents/Resources/simplelime"
    fi

    cat > "${APP}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Text Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.text</string>
                <string>public.plain-text</string>
                <string>public.source-code</string>
                <string>public.json</string>
                <string>public.xml</string>
                <string>public.shell-script</string>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_OS}</string>
    <key>LSSupportsOpeningDocumentsInPlace</key><true/>
    <key>NSBonjourServices</key>
    <array>
        <string>_simplelime._tcp</string>
    </array>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Aleksei Malikov. MIT License.</string>
    <key>NSLocalNetworkUsageDescription</key><string>SimpleLime uses the local network to find trusted devices and exchange notes between your Macs.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

    cat > "${APP}/Contents/Resources/Credits.html" << 'CREDITS'
<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: -apple-system, sans-serif; font-size: 11px; color: #999; text-align: center; }
a { color: #4a9eff; text-decoration: none; }
a:hover { text-decoration: underline; }
</style>
</head>
<body>
<p>Made by <a href="https://malikov.tech">Aleksei Malikov</a></p>
<p>
<a href="https://malikov.tech/simplelime">Website</a> ·
<a href="https://github.com/alexrett/simplelime">GitHub</a>
</p>
</body>
</html>
CREDITS

    echo "✓ ${APP} created"
    ;;

sign)
    bash "${SELF}" app
    step "Signing ${APP}"
    codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${APP}"
    codesign --verify --verbose=2 "${APP}"
    echo "✓ Signed"
    ;;

notarize)
    bash "${SELF}" sign
    step "Notarizing"
    ditto -c -k --keepParent "${APP}" "/tmp/${APP_NAME}.zip"
    xcrun notarytool submit "/tmp/${APP_NAME}.zip" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${APP}"
    rm "/tmp/${APP_NAME}.zip"
    echo "✓ Notarized & stapled"
    ;;

dmg)
    bash "${SELF}" notarize
    step "Creating ${DMG}"
    rm -f "${DMG}"
    STAGING="$(mktemp -d)"
    cp -R "${APP}" "${STAGING}/"
    ln -s /Applications "${STAGING}/Applications"
    hdiutil create -volname "${DISPLAY_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}"
    rm -rf "${STAGING}"
    shasum -a 256 "${DMG}"
    echo "✓ ${DMG} ready"
    ;;

release)
    bash "${SELF}" dmg
    step "Done"
    echo "Upload ${DMG} to GitHub Releases"
    echo "  gh release create v${VERSION} ${DMG} --title '${DISPLAY_NAME} v${VERSION}'"
    ;;

clean)
    rm -rf .build "${APP}" "${DMG}"
    echo "✓ Cleaned"
    ;;

*)
    echo "Usage: $0 {build|app|sign|notarize|dmg|release|clean}"
    exit 1
    ;;
esac
