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
    @State private var renaming: NavSection?                  // 正在改名的板块
    @State private var renameText = ""
    @State private var renamingItem: String?                  // 正在改名的那一项（模块 id）

    /// 全部入口（「更多」固定在最下面）
    private var allIDs: [String] { ["home"] + ledger.navSections.flatMap(\.items) }
    private var pins: [String] { layout.pins.filter { allIDs.contains($0) } }
    /// 左栏分组：常用（自己选的快捷入口，只存在这台设备上）/ 首页 / 网页上的那几个板块（名字、顺序、
    /// 每个板块里有什么，都和网页左侧导航同步）/ 更多。放进常用的就不在下面重复出现
    private var groups: [(key: String, title: String, ids: [String])] {
        [("pins", "常用", pins)]
        + (pins.contains("home") ? [] : [("top", "", ["home"])])
        + ledger.navSections.map { s in
            let ids = s.items.filter { !pins.contains($0) }
            // 折叠起来的板块只留当前打开的那一项
            return ("nav:" + s.id, s.label, ledger.navCollapsed.contains(s.id) ? ids.filter { $0 == selection } : ids)
        }
        + [("more", "", ["more"])]
    }
    private func navID(_ key: String) -> String? { key.hasPrefix("nav:") ? String(key.dropFirst(4)) : nil }

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
                        } else if let sec = navID(g.key), let n = ledger.navSections.first(where: { $0.id == sec }) {
                            HStack {
                                let folded = ledger.navCollapsed.contains(sec)
                                Button {
                                    withAnimation { Task { await ledger.navToggle(sec) } }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                                            .rotationEffect(.degrees(folded ? -90 : 0)).foregroundStyle(.tertiary)
                                        Text(g.title).font(.system(size: 13, weight: .bold)).foregroundStyle(ledger.navColor(sec))
                                        if folded { Text("\(n.items.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                            .padding(.horizontal, 6).padding(.vertical, 1).background(Color.secondary.opacity(0.15), in: Capsule()) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).help(folded ? "展开" : "折叠").accessibilityLabel((folded ? "展开" : "折叠") + "「\(g.title)」")
                                Spacer()
                                if sorting {
                                    Button { startRename(n) } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.borderless).help("给「\(g.title)」改名").accessibilityLabel("给「\(g.title)」改名")
                                }
                            }
                            .textCase(nil)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button { startRename(n) } label: { Label("改名…", systemImage: "pencil") }
                                colorMenu(sec)
                            }
                        } else if !g.title.isEmpty { Text(g.title) }
                    } footer: {
                        if g.key == "pins" && !g.ids.isEmpty {
                            Text("点「排序」后拖动右边的三条线调整顺序，板块名旁边的铅笔可以改名；右键任意一项可以「移到」别的板块；⌘1…⌘\(g.ids.count) 直接打开").font(.caption2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.editMode, .constant(sorting ? .active : .inactive))
            .navigationTitle("合租管理")
            .alert("板块改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("板块名字", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if let n = renaming { let v = String(renameText.prefix(20)); Task { await ledger.navRename(n.id, v) } }
                    renaming = nil
                }
            } message: { Text("网页和 App 的左栏一起改。留空恢复默认名字。") }
            .alert("改名", isPresented: Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })) {
                TextField("名字", text: $renameText)
                Button("取消", role: .cancel) { renamingItem = nil }
                Button("保存") {
                    if let id = renamingItem { let v = renameText; Task { await ledger.navRenameItem(id, v) } }
                    renamingItem = nil
                }
            } message: { Text(renamingItem?.hasPrefix("sheet:") == true ? "就是这张表的名字，网页和 App 一起改。" : "网页和 App 的左栏一起改。留空恢复默认名字。") }
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

    private func startRename(_ n: NavSection) { renameText = n.label; renaming = n }
    /// 换板块颜色（网页和 App 一起变）
    private func colorMenu(_ sec: String) -> some View {
        Menu {
            ForEach(LedgerStore.navColorList, id: \.key) { c in
                Button { Task { await ledger.navSetColor(sec, c.key) } } label: {
                    Label(c.name + (ledger.navColorKey(sec) == c.key ? " ✓" : ""), systemImage: "circle.fill")
                }
            }
        } label: { Label("颜色", systemImage: "paintpalette") }
    }

    /// 同一组里拖动排序（板块里的顺序存到服务器，网页也跟着变）
    private func move(_ g: (key: String, title: String, ids: [String]), from: IndexSet, to: Int) {
        if g.key == "pins" {
            layout.pins.move(fromOffsets: from, toOffset: to)
        } else if let sec = navID(g.key) {
            var o = g.ids
            o.move(fromOffsets: from, toOffset: to)
            Task { await ledger.navSetVisibleOrder(sec, visible: o) }
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
                if let sec = navID(group.key) {
                    Button { Task { await ledger.navSetVisibleOrder(sec, visible: LayoutPrefs.shifted(group.ids, id, by: -1)) } } label: { Label("上移", systemImage: "arrow.up") }.disabled(group.ids.first == id)
                    Button { Task { await ledger.navSetVisibleOrder(sec, visible: LayoutPrefs.shifted(group.ids, id, by: 1)) } } label: { Label("下移", systemImage: "arrow.down") }.disabled(group.ids.last == id)
                }
            }
            if id != "home", let cur = ledger.navSection(of: id) {
                Button {
                    renameText = moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt).title
                    renamingItem = id
                } label: { Label("改名…", systemImage: "pencil") }
                Menu {
                    ForEach(ledger.navSections.filter { $0.id != cur.id }) { s in
                        Button(s.label) { Task { await ledger.navMove(id, to: s.id) } }
                    }
                } label: { Label("移到", systemImage: "arrow.right.square") }
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
