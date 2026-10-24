#!/bin/bash
# Builds CrossLink (Release) and installs it to /Applications, replacing the running copy.
# Signs it with "CrossLink Local Signing" (make-signing-cert.sh) when that certificate exists: the
# signature is then the same from build to build, and macOS asks for the pairing key in the Keychain
# only once ("Always Allow"). Without it the app is signed ad hoc and macOS asks after every install.
set -euo pipefail
cd "$(dirname "$0")"
target=/Applications/CrossLink.app
identity="CrossLink Local Signing"

if [ -d "$target" ] && [ "$(defaults read "$target/Contents/Info" CFBundleIdentifier)" != kg.crosslink.macos ]; then
    echo "$target is another app; not replacing it" >&2
    exit 1
fi

xcodegen generate --quiet
xcodebuild -project CrossLink.xcodeproj -scheme CrossLink -configuration Release -derivedDataPath build \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -quiet build
app=build/Build/Products/Release/CrossLink.app
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" --timestamp=none "$app"
else
    echo "No \"$identity\": signed ad hoc, macOS will ask for the Keychain again (see make-signing-cert.sh)" >&2
fi

pkill -x CrossLink || true
while pgrep -x CrossLink >/dev/null; do sleep 0.2; done
rm -rf "$target"
cp -R "$app" "$target"
# Picks up "Open With" and Services → "Отправить на телефон"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
/System/Library/CoreServices/pbs -update
open "$target"
echo "Installed $target"
