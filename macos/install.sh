#!/bin/bash
# Builds CrossLink (Release) and installs it to /Applications, replacing the running copy.
# The app is signed ad hoc, so after each install macOS asks once for the pairing key in the
# Keychain: choose "Always Allow", otherwise the Mac shows "Нет доступа к Связке ключей".
set -euo pipefail
cd "$(dirname "$0")"
target=/Applications/CrossLink.app

if [ -d "$target" ] && [ "$(defaults read "$target/Contents/Info" CFBundleIdentifier)" != kg.crosslink.macos ]; then
    echo "$target is another app; not replacing it" >&2
    exit 1
fi

xcodegen generate --quiet
xcodebuild -project CrossLink.xcodeproj -scheme CrossLink -configuration Release -derivedDataPath build \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -quiet build

pkill -x CrossLink || true
while pgrep -x CrossLink >/dev/null; do sleep 0.2; done
rm -rf "$target"
cp -R build/Build/Products/Release/CrossLink.app "$target"
# Picks up "Open With" and Services → "Отправить на телефон"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
/System/Library/CoreServices/pbs -update
open "$target"
echo "Installed $target"
