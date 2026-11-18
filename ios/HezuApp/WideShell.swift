import SwiftUI

/// 宽屏（Mac、iPad 横屏）用的界面：左边一栏列出全部模块，右边是内容。
/// 手机上还是底部标签（MainTabView 里按屏幕宽度选）。
/// 快捷键：⌘1…⌘9 切到左栏第几个，⌘R 刷新当前内容。

/// 首页方块点了以后要打开哪个模块（宽屏时由左栏接管，手机上为 nil）
private struct OpenModuleKey: EnvironmentKey { static let defaultValue: ((String) -> Void)? = nil }
extension EnvironmentValues {
    var openModule: ((String) -> Void)? {
        get { self[OpenModuleKey.self] }
        set { self[OpenModuleKey.self] = newValue }
    }
}

/// 是不是 Mac 版
var isMac: Bool { ProcessInfo.processInfo.isMacCatalystApp }

struct WideShell: View {
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var gpt: GPTStore
    @EnvironmentObject var api: API
    @AppStorage("wide_selection") private var selection = "home"
    @State private var reloadToken = 0
    @State private var columns = NavigationSplitViewVisibility.all

    /// 左栏的分组：概览 / 合租账本 / 工具 / 后台
    private var groups: [(title: String, ids: [String])] {
        [("", ["home"]),
         ("合租账本", ledger.sheetInfo.map { "sheet:" + $0.id } + ["cards", "vps"]),
         ("工具", ["codes", "vault", "notes", "gpt"]),
         ("后台", ["more"])]
    }
    private var flat: [String] { groups.flatMap(\.ids) }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: Binding(get: { selection }, set: { if let v = $0 { selection = v } })) {
                ForEach(groups, id: \.title) { g in
                    Section(g.title) {
                        ForEach(g.ids, id: \.self) { id in sidebarRow(id).tag(id) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("合租管理")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            .background(shortcuts)
        } detail: {
            NavigationStack {
                detail(selection).id(selection + "#\(reloadToken)")
            }
            .environment(\.openModule) { id in selection = id }
        }
        .tint(.brand)
        .onAppear { if !flat.contains(selection) { selection = "home" } }
    }

    @ViewBuilder
    private func detail(_ id: String) -> some View {
        switch id {
        case "home": HomeView(tab: Binding(get: { selection }, set: { selection = $0 }))
        case "more": MoreView()
        default: ModuleView(id: id)
        }
    }

    private func sidebarRow(_ id: String) -> some View {
        let m: ModuleInfo = id == "home" ? ModuleInfo(title: "首页", sub: "", icon: "square.grid.2x2.fill", color: .brand)
            : id == "more" ? ModuleInfo(title: "更多", sub: "", icon: "ellipsis.circle.fill", color: .gray)
            : moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt)
        let colors = id == "home" ? [Color.brand, Color.brand] : id == "more" ? [Color.gray, Color.gray] : tileColors(id, ledger)
        return HStack(spacing: 10) {
            Image(systemName: m.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(m.title).lineLimit(1)
            Spacer(minLength: 4)
            if !m.sub.isEmpty { Text(m.sub).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
    }

    /// 看不见的按钮，只为了接快捷键
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(flat.prefix(9).enumerated()), id: \.offset) { i, id in
                Button("") { selection = id }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Button("") {
                reloadToken += 1   // 重新建一次右边的页面，各页面出现时会重新读数据
                Task { await ledger.load(); await codes.load(); await gpt.load() }
            }.keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
