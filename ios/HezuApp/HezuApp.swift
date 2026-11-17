import SwiftUI

/// 合租管理的 iOS App：一个原生外壳，里面打开你自己服务器上的后台网页。
/// 原生部分负责：面容 ID 解锁、切到后台时遮住内容、登录状态长期保存、外部链接用 Safari 打开、
/// 导出的 Excel 等文件用系统分享面板保存、下拉刷新。网页本身的功能和电脑上完全一样。
@main
struct HezuApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(lock)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var lock: AppLock
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            if let url = settings.homeURL {
                WebScreen(home: url)
            } else {
                SetupView()
            }
            if settings.homeURL != nil && settings.lockEnabled && lock.locked {
                LockView()
                    .transition(.opacity)
            } else if lock.covered {
                PrivacyCover()
            }
        }
        .animation(.easeOut(duration: 0.2), value: lock.locked)
        .onAppear { lock.start(enabled: settings.lockEnabled && settings.homeURL != nil) }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .active:
                settings.reload()   // 可能在「设置」App 里改过
                lock.becameActive(enabled: settings.lockEnabled && settings.homeURL != nil,
                                  after: settings.lockAfterSeconds)
            case .inactive:
                lock.covered = true // 多任务界面里不露出账号密码
            case .background:
                lock.wentToBackground()
            @unknown default:
                break
            }
        }
    }
}

/// 切到后台、多任务界面里显示的遮挡页
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            AppMark()
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 72
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.43, green: 0.42, blue: 0.97), Color(red: 0.66, green: 0.33, blue: 0.97)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Text("租").font(.system(size: size * 0.5, weight: .bold)).foregroundColor(.white))
    }
}
