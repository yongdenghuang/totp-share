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
    @State private var tab = Tab.home

    enum Tab: Hashable { case home, codes, vault, notes, more }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }
                .tabItem { Label("首页", systemImage: "square.grid.2x2") }.tag(Tab.home)
            NavigationStack { CodesView() }
                .tabItem { Label("验证码", systemImage: "key.horizontal") }.tag(Tab.codes)
            NavigationStack { VaultView() }
                .tabItem { Label("密码本", systemImage: "lock") }.tag(Tab.vault)
            NotesView()
                .tabItem { Label("备忘录", systemImage: "note.text") }.tag(Tab.notes)
            NavigationStack { MoreView() }
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }.tag(Tab.more)
        }
        .tint(.brand)
        .environmentObject(codes)
        .environmentObject(vault)
        .environmentObject(notes)
        .environmentObject(ledger)
        .onAppear { codes.api = api; vault.api = api; notes.api = api; ledger.api = api }
    }
}
