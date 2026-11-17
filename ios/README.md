# 合租管理 iOS App

一个原生外壳，里面打开你自己服务器上的后台（`/admin/hezu`）。网页功能和电脑上完全一样，原生部分负责：

- **面容 ID 解锁**：打开 App、以及离开超过设定时间后回来，都要先解锁（识别不了可以输锁屏密码）
- **多任务界面遮挡**：切出 App 时盖住内容，别人在多任务界面里看不到账号密码
- **登录长期保存**：登录时勾「记住这台设备」，30 天内打开不用再输密码
- **外部链接**：官网、VPS 面板这些网址在 App 里弹出 Safari 页面打开
- **下载**：导出的 Excel、JSON 备份会弹出系统分享面板，可以存到「文件」
- **下拉刷新**、左滑返回

服务器地址第一次打开时填写，只存在手机上，不在代码里。以后在系统「设置」→「合租管理」里可以改地址、
开关面容 ID、设置离开多久后重新上锁。

## 编译和安装

需要一台装了 Xcode 的 Mac。

```bash
brew install xcodegen          # 只需一次
cd ios && xcodegen             # 根据 project.yml 生成 HezuApp.xcodeproj
open HezuApp.xcodeproj
```

- **模拟器**：Xcode 顶部选一个 iPhone 模拟器，点 ▶︎ 运行
- **装到自己的 iPhone**：
  1. Xcode → Settings → Accounts 登录 Apple ID
  2. 选中 HezuApp 这个 target → Signing & Capabilities → Team 选你的 Apple ID；
     Bundle Identifier 如果提示被占用，改成别的（比如在后面加上你的名字）
  3. 用数据线连上 iPhone，在 iPhone 上打开「设置 → 隐私与安全性 → 开发者模式」
  4. Xcode 顶部选你的 iPhone，点 ▶︎；第一次要在 iPhone「设置 → 通用 → VPN 与设备管理」里信任这个开发者
- 免费的 Apple ID 装的 App **7 天后失效**，到时用 Xcode 再装一次即可（数据和登录都在服务器上，不会丢）；
  付费开发者账号（每年 99 美元）装的可以用一年

## 图标

`tools/make_icon.swift` 生成 1024×1024 的图标；iOS 图标不能带透明通道，生成后转一下：

```bash
swift tools/make_icon.swift /tmp/icon.png
sips -s format jpeg -s formatOptions 100 /tmp/icon.png --out /tmp/icon.jpg
sips -s format png /tmp/icon.jpg --out HezuApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```
