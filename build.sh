#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="AutoSidecar.app"

echo "Testing rule engine…"
swiftc -target arm64-apple-macos15 -swift-version 5 \
  Sources/Models.swift Sources/RuleEngine.swift Sources/UpdateManager.swift \
  Tests/RuleEngineTests.swift -o /tmp/autosidecar-tests
/tmp/autosidecar-tests
NAME="AutoSidecar"
BUNDLE_ID="com.ryanjc.autosidecar"
# iCloud adds Finder metadata that codesign rejects, so the bundle is built outside the repo.
STAGE="$(mktemp -d)"
APP="$STAGE/AutoSidecar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Generating icon…"
ICON_TMP="$(mktemp -d)"
ICONSET="$ICON_TMP/AppIcon.iconset"
swift tools/generate_icon.swift "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICON_TMP"

echo "Compiling…"
swiftc -O -target arm64-apple-macos15 -swift-version 5 -parse-as-library \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -framework IOKit -framework CoreWLAN -framework CoreLocation \
  -framework SystemConfiguration -framework ServiceManagement \
  -o "$APP/Contents/MacOS/$NAME" Sources/*.swift

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>自动随航</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSLocationUsageDescription</key><string>自动随航用定位权限读取当前 Wi-Fi 名称，用来把规则绑定到这个网络。不授权时，改用网关识别网络。</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>自动随航用定位权限读取当前 Wi-Fi 名称，用来把规则绑定到这个网络。不授权时，改用网关识别网络。</string>
</dict>
</plist>
EOF

codesign --force --sign - --entitlements entitlements.plist "$APP"
rm -rf AutoSidecar.app
ditto "$APP" AutoSidecar.app
mkdir -p release
rm -f release/AutoSidecar.app.zip
ditto -c -k --norsrc --keepParent "$APP" release/AutoSidecar.app.zip
rm -rf "$STAGE"
echo "Built AutoSidecar.app $VERSION"
