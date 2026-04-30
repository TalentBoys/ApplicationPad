---
name: applicationpad-release
description: Build, sign, notarize, and publish a new version of ApplicationPad. Creates both DMG (for website download) and ZIP (for Sparkle auto-update), updates appcast.xml, and deploys to Cloud Foundry. Use this skill when the user says "release", "publish", "deploy a new version", "bump version", or anything about releasing ApplicationPad.
user_invocable: true
---

# ApplicationPad Release & Publish

Build a new release of ApplicationPad: bump version, build Release, sign with Developer ID, notarize, create DMG + ZIP, update appcast.xml, update website download link, and deploy to Cloud Foundry.

## Input

The user provides the new version number (e.g., "2.1", "1.98", "2.0.1"). Any version string is valid — it does not have to follow major.minor convention. If not provided, ask the user what version they want to release (show the current `MARKETING_VERSION` from `project.pbxproj` for reference).

## Credentials

```
APPLE_ID:           513967622@qq.com
APPLE_PASSWORD:     vebr-zsam-fabx-owrc
APPLE_TEAM_ID:      R7VZ438Y25
SIGNING_IDENTITY:   Developer ID Application: Yu Jin (R7VZ438Y25)
```

## Key Paths

```
PROJECT_DIR:    /Users/I501206/Documents/Own Project/ApplicationPad/ApplicationPad
PBXPROJ:        $PROJECT_DIR/ApplicationPad.xcodeproj/project.pbxproj
ENTITLEMENTS:   $PROJECT_DIR/ApplicationPad.entitlements
INFO_PLIST:     $PROJECT_DIR/ApplicationPad/Info.plist
WEBSITE_DIR:    $PROJECT_DIR/website
BUILD_DIR:      $PROJECT_DIR/build/Release
SPARKLE_BIN:    /Users/I501206/Library/Developer/Xcode/DerivedData/ApplicationPad-akknipxafseurahjsegsxlkhagbk/SourcePackages/artifacts/sparkle/Sparkle/bin
```

## Steps

### 1. Bump Version

In `project.pbxproj`, update **both** Debug and Release target configurations:
- `MARKETING_VERSION` → new version (e.g., `1.9`)
- `CURRENT_PROJECT_VERSION` → increment by 1 from current value

### 2. Build Release

```bash
cd "$PROJECT_DIR"
rm -rf build/Release/ApplicationPad.app
xcodebuild -project ApplicationPad.xcodeproj -scheme ApplicationPad \
  -configuration Release build CONFIGURATION_BUILD_DIR="$(pwd)/build/Release"
```

Verify `** BUILD SUCCEEDED **` in output.

### 3. Sign with Developer ID

Sign Sparkle components first, then the main app. The order matters.

```bash
cd "$BUILD_DIR"
IDENTITY="Developer ID Application: Yu Jin (R7VZ438Y25)"
ENTITLEMENTS="$PROJECT_DIR/ApplicationPad.entitlements"
APP="ApplicationPad.app"

# Sparkle internals
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework"

# Main app (with entitlements)
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP"

# Verify
codesign --verify --deep --strict "$APP"
```

### 4. Create DMG (for website download)

DMG must include an Applications symlink for drag-to-install.

```bash
rm -rf dmg_staging && mkdir dmg_staging
cp -R ApplicationPad.app dmg_staging/
ln -s /Applications dmg_staging/Applications
hdiutil create -volname "ApplicationPad" -srcfolder dmg_staging \
  -ov -format UDZO "ApplicationPad-$VERSION.dmg"
codesign --force --timestamp --sign "$IDENTITY" "ApplicationPad-$VERSION.dmg"
rm -rf dmg_staging
```

### 5. Create ZIP (for Sparkle auto-update)

Sparkle needs ZIP format because DMG installation fails under App Sandbox.

```bash
ditto -c -k --sequesterRsrc --keepParent ApplicationPad.app "ApplicationPad-$VERSION.zip"
```

### 6. Notarize DMG

```bash
xcrun notarytool submit "ApplicationPad-$VERSION.dmg" \
  --apple-id "513967622@qq.com" \
  --password "vebr-zsam-fabx-owrc" \
  --team-id "R7VZ438Y25" \
  --wait
```

Verify `status: Accepted`, then staple:

```bash
xcrun stapler staple "ApplicationPad-$VERSION.dmg"
```

### 7. Sign ZIP with Sparkle EdDSA

```bash
"$SPARKLE_BIN/sign_update" "ApplicationPad-$VERSION.zip"
```

Save the output `sparkle:edSignature="..."` and `length="..."` values for the appcast.

### 8. Update appcast.xml

Add a new `<item>` at the top of the channel in `$WEBSITE_DIR/appcast.xml`:

```xml
<item>
  <title>Version $VERSION</title>
  <pubDate>$RFC2822_DATE</pubDate>
  <sparkle:version>$BUILD_NUMBER</sparkle:version>
  <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <description><![CDATA[
    <h2>What's New in $VERSION</h2>
    <ul>
      <li>...</li>
    </ul>
  ]]></description>
  <enclosure
    url="https://applicationpad.cfapps.eu12.hana.ondemand.com/ApplicationPad-$VERSION.zip"
    type="application/octet-stream"
    sparkle:edSignature="$ED_SIGNATURE"
    length="$ZIP_LENGTH"
  />
</item>
```

The enclosure must point to the **ZIP** file (not DMG). Ask the user for release notes or use a generic message.

### 9. Update Website Download Link

In `$WEBSITE_DIR/index.html`, update the download button href to point to the new DMG:

```html
<a href="ApplicationPad-$VERSION.dmg" class="btn-download">
```

### 10. Copy Files & Deploy

```bash
cp "$BUILD_DIR/ApplicationPad-$VERSION.dmg" "$WEBSITE_DIR/"
cp "$BUILD_DIR/ApplicationPad-$VERSION.zip" "$WEBSITE_DIR/"
cd "$WEBSITE_DIR"
cf push
```

Verify the app is running from the `cf push` output.

### 11. Report Results

Tell the user:
- Version number and build number
- DMG path and size
- Notarization status
- Website URL: https://applicationpad.cfapps.eu12.hana.ondemand.com
- Appcast URL: https://applicationpad.cfapps.eu12.hana.ondemand.com/appcast.xml
