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
    @EnvironmentObject var layout: LayoutPrefs
    @AppStorage("wide_selection") private var selection = "home"
    @State private var reloadToken = 0
    @State private var columns = NavigationSplitViewVisibility.all
    private static var launched = false
    @AppStorage("wide_sorting") private var sorting = false   // 「排序」模式：每行右边出现拖动把手

    /// 全部入口（「更多」固定在最下面）
    private var allIDs: [String] { ["home"] + ledger.moduleIDs.filter { $0.hasPrefix("sheet:") } + ["cards", "vps", "codes", "vault", "notes", "gpt"] }
    private var pins: [String] { layout.pins.filter { allIDs.contains($0) } }
    /// 左栏分组：常用（自己选的快捷入口）/ 合租账本 / 工具；放进常用的就不在下面重复出现
    private var groups: [(key: String, title: String, ids: [String])] {
        let rest = { (ids: [String]) in layout.sideOrdered(ids.filter { !pins.contains($0) }) }
        return [("pins", "常用", pins),
                ("top", "", rest(["home"])),
                ("ledger", "合租账本", rest(ledger.moduleIDs.filter { $0.hasPrefix("sheet:") } + ["cards", "vps"])),
                ("tools", "工具", rest(["codes", "vault", "notes", "gpt"])),
                ("more", "", ["more"])]
            .filter { !$0.ids.isEmpty || $0.key == "pins" }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: Binding(get: { selection }, set: { if let v = $0 { selection = v } })) {
                ForEach(groups, id: \.key) { g in
                    Section {
                        if g.key == "pins" && g.ids.isEmpty {
                            Text("右键任意一项 →「添加到常用」").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(g.ids, id: \.self) { id in
                            sidebarRow(id, shortcut: g.key == "pins" ? g.ids.firstIndex(of: id).map { $0 + 1 } : nil)
                                .tag(id)
                                .contextMenu { menu(id, group: g) }
                                .moveDisabled(id == "more")
                        }
                        // 系统自带的列表拖动排序（Mac 上直接拖；「排序」模式下拖右边的三条线）
                        .onMove { from, to in move(g, from: from, to: to) }
                    } header: {
                        if g.key == "pins" {
                            HStack {
                                Text(g.title)
                                Spacer()
                                Button {
                                    withAnimation { sorting.toggle() }
                                } label: {
                                    Label(sorting ? "完成" : "排序", systemImage: sorting ? "checkmark" : "arrow.up.arrow.down")
                                        .font(.caption.weight(.semibold)).labelStyle(.titleAndIcon)
                                }
                                .buttonStyle(.borderless).textCase(nil)
                            }
                        } else if !g.title.isEmpty { Text(g.title) }
                    } footer: {
                        if g.key == "pins" && !g.ids.isEmpty {
                            Text("点「排序」后拖动右边的三条线调整顺序；右键「添加到常用 / 从常用移除」；⌘1…⌘\(g.ids.count) 直接打开").font(.caption2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.editMode, .constant(sorting ? .active : .inactive))
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
        .onAppear {
            if !Self.launched { Self.launched = true; sorting = false }   // 每次打开 App 都从非排序状态开始（只在启动时一次）
            if !allIDs.contains(selection) && selection != "more" { selection = "home" }
        }
    }

    @ViewBuilder
    private func detail(_ id: String) -> some View {
        switch id {
        case "home": HomeView(tab: Binding(get: { selection }, set: { selection = $0 }))
        case "more": MoreView()
        default: ModuleView(id: id)
        }
    }

    /// 同一组里拖动排序
    private func move(_ g: (key: String, title: String, ids: [String]), from: IndexSet, to: Int) {
        if g.key == "pins" {
            layout.pins.move(fromOffsets: from, toOffset: to)
        } else {
            var o = g.ids
            o.move(fromOffsets: from, toOffset: to)
            layout.sideOrder = layout.sideOrder.filter { !g.ids.contains($0) } + o
        }
    }

    @ViewBuilder
    private func menu(_ id: String, group: (key: String, title: String, ids: [String])) -> some View {
        if id != "more" {
            if layout.pins.contains(id) {
                Button { layout.togglePin(id) } label: { Label("从常用移除", systemImage: "star.slash") }
                Button { layout.pinShift(id, by: -1) } label: { Label("上移", systemImage: "arrow.up") }.disabled(group.ids.first == id)
                Button { layout.pinShift(id, by: 1) } label: { Label("下移", systemImage: "arrow.down") }.disabled(group.ids.last == id)
            } else {
                Button { layout.togglePin(id) } label: { Label("添加到常用", systemImage: "star") }.disabled(layout.pins.count >= LayoutPrefs.maxPins)
                Button { layout.sideShift(id, by: -1, in: group.ids) } label: { Label("上移", systemImage: "arrow.up") }.disabled(group.ids.first == id)
                Button { layout.sideShift(id, by: 1, in: group.ids) } label: { Label("下移", systemImage: "arrow.down") }.disabled(group.ids.last == id)
            }
        }
    }

    private func sidebarRow(_ id: String, shortcut: Int?) -> some View {
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
            if sorting { EmptyView() }   // 排序时右边是拖动把手，不放数字，免得名字被挤掉
            else if let shortcut, shortcut <= 9 { Text("⌘\(shortcut)").font(.caption2.monospaced()).foregroundStyle(.tertiary) }
            else if !m.sub.isEmpty { Text(m.sub).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
    }

    /// 看不见的按钮，只为了接快捷键：⌘1…⌘9 打开常用里的第几个，⌘R 刷新
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(pins.prefix(9).enumerated()), id: \.offset) { i, id in
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
