import SwiftUI
import UIKit

/// 长按桌面上的 App 图标弹出的快捷操作：搜索全部、验证码、密码本、新建备忘录。
/// 列表写在 Info.plist 里（UIApplicationShortcutItems），这里只负责接收点了哪个。
@MainActor
final class QuickAction: ObservableObject {
    static let shared = QuickAction()
    @Published var pending: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // App 没在运行时点的快捷操作，从这里传进来
        if let item = options.shortcutItem { let t = item.type; Task { @MainActor in QuickAction.shared.pending = t } }
        let c = UISceneConfiguration(name: nil, sessionRole: session.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // App 已经在后台时点的快捷操作
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let t = shortcutItem.type
        Task { @MainActor in QuickAction.shared.pending = t }
        completionHandler(true)
    }
}

/// 单独的搜索页：一打开就弹出键盘（快捷操作「搜索」用）
struct GlobalSearchScreen: View {
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索验证码、密码、备忘录、卡号…", text: $query)
                    .focused($focused).submitLabel(.search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16).padding(.vertical, 8)
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                Text("输入几个字，一次搜遍全部内容").foregroundStyle(.secondary)
                Spacer()
            } else {
                GlobalSearchResults(query: query)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }
}
