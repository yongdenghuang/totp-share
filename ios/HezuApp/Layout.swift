import SwiftUI

/// 首页方框和底部标签的自定义（存在这台手机上）。
/// 模块 id：codes / vault / notes / cards / vps / gpt / sheet:<表 id>
@MainActor
final class LayoutPrefs: ObservableObject {
    static let defaultTabs = ["codes", "vault", "notes"]
    @Published var tabs: [String] { didSet { save() } }          // 首页和「更多」之间的标签，最多 3 个
    @Published var homeOrder: [String] { didSet { save() } }     // 首页方框的顺序
    @Published var homeHidden: Set<String> { didSet { save() } } // 首页不显示的方框
    // 宽屏（Mac、iPad）左栏：顶上「常用」放几个快捷入口（最多 9 个，⌘1…⌘9 打开），其余模块的顺序可以拖动调整
    static let maxPins = 9
    @Published var pins: [String] { didSet { save() } }
    @Published var sideOrder: [String] { didSet { save() } }

    private let d = UserDefaults.standard
    init() {
        tabs = d.stringArray(forKey: "layout_tabs") ?? Self.defaultTabs
        homeOrder = d.stringArray(forKey: "layout_home_order") ?? []
        homeHidden = Set(d.stringArray(forKey: "layout_home_hidden") ?? [])
        pins = d.stringArray(forKey: "layout_pins") ?? ["home", "codes", "vault", "notes"]
        sideOrder = d.stringArray(forKey: "layout_side_order") ?? []
    }
    private func save() {
        d.set(tabs, forKey: "layout_tabs")
        d.set(homeOrder, forKey: "layout_home_order")
        d.set(Array(homeHidden), forKey: "layout_home_hidden")
        d.set(pins, forKey: "layout_pins")
        d.set(sideOrder, forKey: "layout_side_order")
    }

    /// 左栏某一组按保存的顺序排（新出现的接在后面）
    func sideOrdered(_ ids: [String]) -> [String] {
        let known = sideOrder.filter { ids.contains($0) }
        return known + ids.filter { !known.contains($0) }
    }
    /// 拖到 target 上：往下拖放在它后面，往上拖放在它前面
    static func moved(_ list: [String], _ id: String, onto target: String) -> [String] {
        var o = list
        guard id != target, let from = o.firstIndex(of: id), let t = o.firstIndex(of: target) else { return list }
        o.remove(at: from)
        let ti = o.firstIndex(of: target)!
        o.insert(id, at: from < t ? ti + 1 : ti)
        return o
    }
    func sideMove(_ id: String, onto target: String, in ids: [String]) {
        sideOrder = sideOrder.filter { !ids.contains($0) } + Self.moved(sideOrdered(ids), id, onto: target)
    }
    func sideShift(_ id: String, by delta: Int, in ids: [String]) {
        var o = sideOrdered(ids)
        guard let i = o.firstIndex(of: id) else { return }
        let j = max(0, min(o.count - 1, i + delta)); guard j != i else { return }
        o.swapAt(i, j)
        sideOrder = sideOrder.filter { !ids.contains($0) } + o
    }
    func pinMove(_ id: String, onto target: String) { pins = Self.moved(pins, id, onto: target) }
    func pinShift(_ id: String, by delta: Int) {
        guard let i = pins.firstIndex(of: id) else { return }
        let j = max(0, min(pins.count - 1, i + delta)); guard j != i else { return }
        var p = pins; p.swapAt(i, j); pins = p
    }
    func togglePin(_ id: String) {
        if pins.contains(id) { pins.removeAll { $0 == id } }
        else if pins.count < Self.maxPins { pins.append(id) }
    }

    /// 按保存的顺序排好全部模块；新出现的模块（新建的表）接在后面
    func ordered(_ all: [String]) -> [String] {
        let known = homeOrder.filter { all.contains($0) }
        return known + all.filter { !known.contains($0) }
    }
}

struct ModuleInfo { let title: String; let sub: String; let icon: String; let color: Color }

extension LedgerStore {
    /// 所有可以放到首页 / 底部标签的模块
    var moduleIDs: [String] { sheetInfo.map { "sheet:" + $0.id } + ["codes", "vault", "notes", "vps", "cards", "gpt"] }
}

/// 模块的名字、图标、颜色、数量
@MainActor
func moduleInfo(_ id: String, ledger: LedgerStore, codes: CodesStore, vault: VaultStore, notes: NotesStore, gpt: GPTStore) -> ModuleInfo {
    let purple = Color(red: 0.43, green: 0.36, blue: 0.96)
    switch id {
    case "codes": return ModuleInfo(title: "验证码", sub: "\(codes.accounts.count) 个", icon: "key.horizontal.fill", color: Color(red: 0.05, green: 0.58, blue: 0.53))
    case "vault": return ModuleInfo(title: "密码本", sub: "\(vault.items.count) 条", icon: "lock.fill", color: Color(red: 0.86, green: 0.36, blue: 0.19))
    case "notes": return ModuleInfo(title: "备忘录", sub: "\(notes.notes.count) 条", icon: "note.text", color: Color(red: 0.85, green: 0.6, blue: 0.1))
    case "vps": return ModuleInfo(title: "VPS", sub: "\(ledger.vps.count) 台", icon: "server.rack", color: Color(red: 0.15, green: 0.45, blue: 0.85))
    case "cards": return ModuleInfo(title: "支付卡", sub: "\(ledger.cards.count) 张", icon: "creditcard.fill", color: Color(red: 0.4, green: 0.42, blue: 0.47))
    case "gpt": return ModuleInfo(title: "GPT 账号", sub: "\(gpt.accounts.count) 个", icon: "brain.head.profile", color: Color(red: 0.06, green: 0.64, blue: 0.5))
    default:
        let sid = String(id.dropFirst(6))
        guard let s = ledger.sheetInfo.first(where: { $0.id == sid }) else { return ModuleInfo(title: "已删除的表", sub: "", icon: "questionmark", color: .gray) }
        return ModuleInfo(title: s.name, sub: s.mode == "resale" ? "\(s.rows) 个项目" : "\(s.rows) 个号",
                          icon: s.grouped ? "person.2.fill" : s.mode == "resale" ? "bolt.fill" : "play.rectangle.fill", color: purple)
    }
}

/// 打开某个模块（放在标签里或者从首页点进去都用这个）
struct ModuleView: View {
    let id: String
    var body: some View {
        switch id {
        case "codes": CodesView()
        case "vault": VaultView()
        case "notes": NotesView()
        case "vps": VPSView()
        case "cards": CardsView()
        case "gpt": GPTView()
        default: LedgerSheetView(sheetID: String(id.dropFirst(6)))
        }
    }
}

/// 「更多 → 自定义首页和标签」
struct LayoutSettingsView: View {
    @EnvironmentObject var layout: LayoutPrefs
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var gpt: GPTStore

    @Environment(\.horizontalSizeClass) private var hSize
    private func info(_ id: String) -> ModuleInfo {
        id == "home" ? ModuleInfo(title: "首页", sub: "", icon: "square.grid.2x2.fill", color: .brand) : moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt)
    }

    var body: some View {
        List {
            if hSize == .regular { pinsSection } else { tabsSection }
            homeSection
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(hSize == .regular ? "自定义首页和左栏" : "自定义首页和底部标签")
    }

    /// 宽屏：左栏「常用」里的快捷入口
    private var pinsSection: some View {
        Section {
            ForEach(layout.pins, id: \.self) { id in
                HStack {
                    Image(systemName: info(id).icon).foregroundStyle(info(id).color).frame(width: 26)
                    Text(info(id).title)
                    Spacer()
                    if let i = layout.pins.firstIndex(of: id), i < 9 { Text("⌘\(i + 1)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
            }
            .onMove { layout.pins.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { layout.pins.remove(atOffsets: $0) }
            if layout.pins.count < LayoutPrefs.maxPins {
                Menu {
                    ForEach((["home"] + ledger.moduleIDs).filter { !layout.pins.contains($0) }, id: \.self) { id in
                        Button { layout.pins.append(id) } label: { Label(info(id).title, systemImage: info(id).icon) }
                    }
                } label: { Label("添加快捷入口", systemImage: "plus.circle") }
            }
            Button("恢复默认（首页、验证码、密码本、备忘录）") { layout.pins = ["home", "codes", "vault", "notes"] }
        } header: { Text("左栏「常用」") } footer: { Text("最多 \(LayoutPrefs.maxPins) 个，按顺序对应 ⌘1…⌘9。也可以直接在左栏拖动，或者右键「添加到常用 / 从常用移除」。") }
    }

    private var tabsSection: some View {
            Section {
                ForEach(0..<3, id: \.self) { i in
                    Picker("第 \(i + 1) 个", selection: Binding(
                        get: { i < layout.tabs.count ? layout.tabs[i] : "" },
                        set: { v in
                            var t = layout.tabs
                            while t.count < 3 { t.append("") }
                            if let j = t.firstIndex(of: v), !v.isEmpty, j != i { t[j] = t[i] }   // 已经在别的位置：两个互换
                            t[i] = v
                            layout.tabs = t.filter { !$0.isEmpty }
                        })) {
                        Text("不显示").tag("")
                        ForEach(ledger.moduleIDs, id: \.self) { id in Label(info(id).title, systemImage: info(id).icon).tag(id) }
                    }
                }
                Button("恢复默认（验证码、密码本、备忘录）") { layout.tabs = LayoutPrefs.defaultTabs }
            } header: { Text("底部标签") } footer: { Text("「首页」和「更多」固定在两头，中间最多放 3 个常用的模块。") }
    }

    private var homeSection: some View {
            Section {
                ForEach(layout.ordered(ledger.moduleIDs), id: \.self) { id in
                    let m = info(id), hidden = layout.homeHidden.contains(id)
                    HStack {
                        Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 26)
                        Text(m.title).foregroundStyle(hidden ? .secondary : .primary)
                        Spacer()
                        Button {
                            if hidden { layout.homeHidden.remove(id) } else { layout.homeHidden.insert(id) }
                        } label: { Image(systemName: hidden ? "eye.slash" : "eye").foregroundStyle(hidden ? .secondary : Color.brand) }
                            .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    var o = layout.ordered(ledger.moduleIDs); o.move(fromOffsets: from, toOffset: to); layout.homeOrder = o
                }
                Button("恢复默认顺序，全部显示") { layout.homeOrder = []; layout.homeHidden = [] }
            } header: { Text("首页方框") } footer: { Text("拖动右边的三条线调整顺序（也可以直接在首页长按方块拖动），点眼睛隐藏或显示。") }
    }
}

// MARK: - 首页方块的颜色（五颜六色，每个模块固定一种，挪位置颜色跟着走）
private func pair(_ a: String, _ b: String) -> [Color] { [Color(hex: a), Color(hex: b)] }
private let fixedTileColors: [String: [Color]] = [
    "codes": pair("#14b8a6", "#0d9488"),   // 青绿
    "vault": pair("#fb923c", "#ea580c"),   // 橙
    "notes": pair("#facc15", "#eab308"),   // 黄
    "vps":   pair("#38bdf8", "#2563eb"),   // 蓝
    "cards": pair("#f472b6", "#db2777"),   // 粉
    "gpt":   pair("#4ade80", "#16a34a"),   // 绿
]
/// 合租表依次用这些颜色
private let sheetTileColors: [[Color]] = [
    pair("#a78bfa", "#7c3aed"),  // 紫
    pair("#f87171", "#dc2626"),  // 红
    pair("#818cf8", "#4f46e5"),  // 靛
    pair("#e879f9", "#c026d3"),  // 品红
    pair("#22d3ee", "#0891b2"),  // 天青
    pair("#a3e635", "#65a30d"),  // 青柠
    pair("#fbbf24", "#d97706"),  // 琥珀
    pair("#fb7185", "#e11d48"),  // 玫红
    pair("#2dd4bf", "#0f766e"),  // 碧绿
    pair("#94a3b8", "#475569"),  // 石板灰
]
@MainActor
func tileColors(_ id: String, _ ledger: LedgerStore) -> [Color] {
    if let c = fixedTileColors[id] { return c }
    let sid = String(id.dropFirst(6))
    let i = ledger.sheetInfo.firstIndex { $0.id == sid } ?? 0
    return sheetTileColors[i % sheetTileColors.count]
}
