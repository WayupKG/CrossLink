#!/bin/bash
# Builds the release files into dist/: a signed Android APK and a macOS DMG (universal, ad hoc
# signed), plus SHA256SUMS.txt. Publish them with:
#
#     gh release create v<version> dist/* --title "CrossLink <version>" --notes-file <notes>
#
# The APK is signed with the release key. Its password is read from the login keychain
# (item "CrossLink Android release keystore") unless CROSSLINK_KEYSTORE_PASSWORD is set.
# Keep the keystore backed up: an APK signed with another key cannot update installed copies.
#
# Needs: JDK 17+ (JAVA_HOME), the Android SDK (ANDROID_HOME or android/local.properties),
# Xcode and xcodegen.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"

version=$(sed -nE 's/^ *versionName = "(.*)"/\1/p' "$root/android/app/build.gradle.kts")
mac_version=$(sed -nE "s/^ *CFBundleShortVersionString: '(.*)'/\1/p" "$root/macos/project.yml")
if [ -z "$version" ] || [ "$version" != "$mac_version" ]; then
    echo "Version mismatch: Android '$version', macOS '$mac_version'" >&2
    exit 1
fi

export CROSSLINK_KEYSTORE="${CROSSLINK_KEYSTORE:-$HOME/.android/crosslink-release.jks}"
if [ ! -f "$CROSSLINK_KEYSTORE" ]; then
    echo "No release keystore at $CROSSLINK_KEYSTORE" >&2
    exit 1
fi
if [ -z "${CROSSLINK_KEYSTORE_PASSWORD:-}" ]; then
    CROSSLINK_KEYSTORE_PASSWORD=$(security find-generic-password -s "CrossLink Android release keystore" -w)
fi
export CROSSLINK_KEYSTORE_PASSWORD

sdk="${ANDROID_HOME:-$(sed -n 's/^sdk.dir=//p' "$root/android/local.properties" 2>/dev/null || true)}"
sdk="${sdk:-$HOME/Library/Android/sdk}"
apksigner=$(ls -d "$sdk"/build-tools/*/apksigner | sort -V | tail -1)

rm -rf "$dist"
mkdir -p "$dist"

echo "==> Android $version"
(cd "$root/android" && ./gradlew --no-daemon --quiet clean assembleRelease)
apk="$dist/CrossLink-$version.apk"
cp "$root/android/app/build/outputs/apk/release/app-release.apk" "$apk"
"$apksigner" verify --print-certs "$apk" | grep -E 'certificate (DN|SHA-256)'

echo "==> macOS $version"
derived="$root/macos/build/release"
(cd "$root/macos" && xcodegen generate --quiet && \
    xcodebuild -project CrossLink.xcodeproj -scheme CrossLink -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$derived" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -quiet clean build)
app="$derived/Build/Products/Release/CrossLink.app"
# Ad hoc: there is no Developer ID yet, so the app is not notarized (see the release notes)
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
echo "architectures: $(lipo -archs "$app/Contents/MacOS/CrossLink")"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="$dist/CrossLink-$version-macOS.dmg"
hdiutil create -quiet -volname "CrossLink $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"

(cd "$dist" && shasum -a 256 CrossLink-* > SHA256SUMS.txt && cat SHA256SUMS.txt)
ls -lh "$dist"
