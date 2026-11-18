import SwiftUI

/// 首页方框和底部标签的自定义（存在这台手机上）。
/// 模块 id：codes / vault / notes / cards / vps / gpt / sheet:<表 id>
@MainActor
final class LayoutPrefs: ObservableObject {
    static let defaultTabs = ["codes", "vault", "notes"]
    @Published var tabs: [String] { didSet { save() } }          // 首页和「更多」之间的标签，最多 3 个
    @Published var homeOrder: [String] { didSet { save() } }     // 首页方框的顺序
    @Published var homeHidden: Set<String> { didSet { save() } } // 首页不显示的方框

    private let d = UserDefaults.standard
    init() {
        tabs = d.stringArray(forKey: "layout_tabs") ?? Self.defaultTabs
        homeOrder = d.stringArray(forKey: "layout_home_order") ?? []
        homeHidden = Set(d.stringArray(forKey: "layout_home_hidden") ?? [])
    }
    private func save() {
        d.set(tabs, forKey: "layout_tabs")
        d.set(homeOrder, forKey: "layout_home_order")
        d.set(Array(homeHidden), forKey: "layout_home_hidden")
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

    private func info(_ id: String) -> ModuleInfo { moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt) }

    var body: some View {
        List {
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
        .environment(\.editMode, .constant(.active))
        .navigationTitle("自定义首页和标签")
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
