import SwiftUI

/// 登录状态决定显示什么：检查中 → 登录页 → 主界面（底部五个标签）
struct MainShell: View {
    @StateObject private var api: API
    @StateObject private var toast = Toast()
    @Environment(\.scenePhase) private var phase

    init(base: URL) { _api = StateObject(wrappedValue: API(base: base)) }

    var body: some View {
        ZStack {
            switch api.status {
            case .unknown:
                ZStack {
                    Color("LaunchBackground").ignoresSafeArea()
                    VStack(spacing: 22) { AppMark(size: 72); ProgressView().tint(.white) }
                }
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
            ToastView()
        }
        .environmentObject(api)
        .environmentObject(toast)
        .task { await api.refreshSession() }
        .onChange(of: phase) { p in
            if p == .active { Task { await api.refreshSession() } }
            if p == .background { api.rememberCookies() }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var api: API
    @StateObject private var codes = CodesStore()
    @StateObject private var vault = VaultStore()
    @StateObject private var notes = NotesStore()
    @StateObject private var ledger = LedgerStore()
    @StateObject private var gpt = GPTStore()
    @StateObject private var komari = KomariStore()
    @StateObject private var layout = LayoutPrefs()
    @State private var tab = "home"
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        Group {
            if hSize == .regular { WideShell() } else { phoneTabs }   // Mac、iPad：左边栏；手机：底部标签
        }
        .environmentObject(codes)
        .environmentObject(vault)
        .environmentObject(notes)
        .environmentObject(ledger)
        .environmentObject(gpt)
        .environmentObject(komari)
        .environmentObject(layout)
        .onAppear { codes.api = api; vault.api = api; notes.api = api; ledger.api = api; gpt.api = api; komari.api = api }
        .onAppear(perform: sizeMacWindow)
    }

    /// Mac 版窗口：最小 980×660，第一次打开时给一个电脑上合适的大小
    private func sizeMacWindow() {
        guard isMac else { return }
        DispatchQueue.main.async {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 980, height: 660)
                if !UserDefaults.standard.bool(forKey: "mac_window_sized") {
                    UserDefaults.standard.set(true, forKey: "mac_window_sized")
                    scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.Mac(systemFrame: CGRect(x: 120, y: 80, width: 1320, height: 860)))
                }
            }
        }
    }

    private var phoneTabs: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }
                .tabItem { Label("首页", systemImage: "square.grid.2x2") }.tag("home")
            ForEach(layout.tabs, id: \.self) { id in
                let m = moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt)
                NavigationStack { ModuleView(id: id) }
                    .tabItem { Label(m.title, systemImage: tabIcon(m.icon)) }.tag(id)
            }
            NavigationStack { MoreView() }
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }.tag("more")
        }
        .tint(.brand)
        .onChange(of: layout.tabs) { t in if tab != "home" && tab != "more" && !t.contains(tab) { tab = "home" } }
    }

    /// 标签栏用不带 .fill 的线条图标，和系统 App 一致
    private func tabIcon(_ s: String) -> String { s.hasSuffix(".fill") ? String(s.dropLast(5)) : s }
}
