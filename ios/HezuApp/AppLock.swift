import LocalAuthentication
import SwiftUI

/// 面容 ID / 触控 ID 解锁（识别不了时可以输手机锁屏密码）。
/// 打开 App 时上锁；切到后台超过设定的时间再回来，也重新上锁。
@MainActor
final class AppLock: ObservableObject {
    @Published var locked = true
    @Published var covered = false
    @Published var message: String?
    private var backgroundAt: Date?
    private var busy = false

    func start(enabled: Bool) {
        locked = enabled
        if enabled { unlock() }
    }

    func wentToBackground() {
        covered = true
        if backgroundAt == nil { backgroundAt = Date() }
    }

    func becameActive(enabled: Bool, after seconds: Double) {
        if !enabled {
            locked = false
        } else if let t = backgroundAt, Date().timeIntervalSince(t) >= seconds {
            locked = true
        }
        backgroundAt = nil
        covered = false
        if locked && enabled { unlock() }
    }

    func unlock() {
        guard !busy else { return }
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 手机没有设置锁屏密码时没法验证，只能直接放行，并提醒一下
            message = "这台手机没有设置锁屏密码，无法用面容 ID 保护。建议在系统设置里开启。"
            locked = false
            return
        }
        busy = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁合租管理") { ok, err in
            Task { @MainActor in
                self.busy = false
                if ok {
                    self.locked = false
                    self.message = nil
                } else if let e = err as? LAError, e.code != .userCancel, e.code != .appCancel, e.code != .systemCancel {
                    self.message = e.localizedDescription
                }
            }
        }
    }
}

struct LockView: View {
    @EnvironmentObject var lock: AppLock

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 18) {
                AppMark(size: 84)
                Text("合租管理").font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("已上锁").foregroundColor(.white.opacity(0.6))
                Button {
                    lock.unlock()
                } label: {
                    Label("解锁", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
                if let m = lock.message {
                    Text(m).font(.footnote).foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                Text("服务器地址、面容 ID 等可以在系统「设置」→「合租管理」里修改")
                    .font(.caption).foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 24)
            }
        }
    }
}
