#!/bin/bash
# 免费 Apple ID 签名的 App 只能用 7 天。这个脚本每小时由 launchd 运行一次：
# 装在手机上的版本剩不到 REFRESH_HOURS 小时就重新签名、通过 Wi-Fi（或数据线）装到 iPhone 上。
# 手机不在、Mac 锁着等情况下装不上，就等下一个小时再试。
#
# 设备和开发团队写在本机的配置文件里（不进 git）：
#   ~/Library/Application Support/hezu-refresh/config   内容：DEVICE=<iPhone UDID>  TEAM=<团队 ID>
# 手动强制续签一次：FORCE=1 ios/tools/refresh-iphone.sh
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin

STATE="$HOME/Library/Application Support/hezu-refresh"
LOG="$HOME/Library/Logs/hezu-refresh.log"
mkdir -p "$STATE"
# shellcheck disable=SC1091
. "$STATE/config"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE=com.hezu.manager
APP="$REPO/build/dev/Build/Products/Release-iphoneos/合租管理.app"
REFRESH_HOURS=${REFRESH_HOURS:-60}      # 剩不到 2.5 天就续签
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
notify() { osascript -e "display notification \"$1\" with title \"合租管理 自动续签\"" >/dev/null 2>&1 || true; }
expiry() { # 描述文件的到期时间（秒）
  local d
  d=$(security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null) || return 1
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$d" +%s
}
fmt() { date -r "$1" '+%m-%d %H:%M'; }

now=$(date +%s)
if [ -f "$STATE/installed-expiry" ]; then exp=$(cat "$STATE/installed-expiry"); else exp=$(expiry "$APP/embedded.mobileprovision" || echo 0); fi
left=$(( (exp - now) / 3600 ))
if [ "${FORCE:-0}" != 1 ] && [ "$left" -gt "$REFRESH_HOURS" ]; then exit 0; fi

# 同一时间只跑一个（上次的锁超过 2 小时算是卡死了，直接清掉）
LOCK="$STATE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rm -rf "$LOCK"; mkdir "$LOCK"; else exit 0; fi
fi
trap 'rm -rf "$LOCK"' EXIT

log "手机上的版本还剩 ${left} 小时，开始续签"
if ! xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -q "available"; then
  log "找不到 iPhone（不在同一个 Wi-Fi、关机或锁着），下个小时再试"
  if [ "$left" -lt 24 ]; then notify "还剩 ${left} 小时过期，但连不上 iPhone。请让手机和 Mac 连同一个 Wi-Fi 并解锁一下。"; fi
  exit 0
fi

# 删掉这个 App 快到期的旧描述文件，让 Xcode 重新申请一个 7 天的
for dir in "${PROFILE_DIRS[@]}"; do
  for f in "$dir"/*.mobileprovision; do
    [ -f "$f" ] || continue
    appid=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Entitlements.application-identifier raw - 2>/dev/null) || continue
    case "$appid" in *".$BUNDLE") ;; *) continue ;; esac
    e=$(expiry "$f") || continue
    if [ "${RENEW_ALL:-0}" = 1 ] || [ $((e - now)) -lt $((6 * 86400)) ]; then
      log "删除旧描述文件 $(basename "$f")（$(fmt "$e") 到期）"
      rm -f "$f"
    fi
  done
done

cd "$REPO" || exit 1
if ! xcodebuild -project HezuApp.xcodeproj -scheme HezuApp -configuration Release \
    -destination "id=$DEVICE" -derivedDataPath build/dev DEVELOPMENT_TEAM="$TEAM" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > "$STATE/build.log" 2>&1; then
  log "编译失败，详情见 $STATE/build.log"
  grep -E "error:" "$STATE/build.log" | head -5 >> "$LOG"
  notify "续签失败：编译出错，Mac 上的日志里有详情。"
  exit 1
fi

new=$(expiry "$APP/embedded.mobileprovision" || echo 0)
if ! xcrun devicectl device install app --device "$DEVICE" "$APP" > "$STATE/install.log" 2>&1; then
  log "安装失败（手机锁屏或断开了？），下个小时再试"
  tail -5 "$STATE/install.log" >> "$LOG"
  exit 1
fi
echo "$new" > "$STATE/installed-expiry"
log "已续签并装到 iPhone，新的到期时间 $(fmt "$new")"
if [ $((new - now)) -lt $((5 * 86400)) ]; then
  notify "已重新安装，但到期时间只到 $(fmt "$new")，可能没拿到新的描述文件。"
else
  notify "已自动续签，可以用到 $(fmt "$new")。"
fi
