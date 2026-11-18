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

    var body: some View {
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
        .environmentObject(codes)
        .environmentObject(vault)
        .environmentObject(notes)
        .environmentObject(ledger)
        .environmentObject(gpt)
        .environmentObject(komari)
        .environmentObject(layout)
        .onAppear { codes.api = api; vault.api = api; notes.api = api; ledger.api = api; gpt.api = api; komari.api = api }
        .onChange(of: layout.tabs) { t in if tab != "home" && tab != "more" && !t.contains(tab) { tab = "home" } }
    }

    /// 标签栏用不带 .fill 的线条图标，和系统 App 一致
    private func tabIcon(_ s: String) -> String { s.hasSuffix(".fill") ? String(s.dropLast(5)) : s }
}
