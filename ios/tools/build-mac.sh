#!/bin/bash
# 编译 Mac 版（Mac Catalyst，和手机版同一套代码），装到「应用程序」里并打开。
# 只在这台 Mac 上本地签名（ad-hoc），不需要 Apple ID，也不会像手机版那样 7 天过期。
# 改了代码想更新 Mac 版：ios/tools/build-mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen -q
xcodebuild -project HezuApp.xcodeproj -scheme HezuApp -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build -quiet
APP="build/mac/Build/Products/Release-maccatalyst/合租管理.app"
osascript -e 'quit app "合租管理"' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/合租管理.app"
cp -R "$APP" /Applications/
open "/Applications/合租管理.app"
echo "已装到「应用程序」：合租管理.app"
