import SwiftUI
import UniformTypeIdentifiers

func daysUntil(_ iso: String) -> Int? {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
    guard iso.count == 10, let d = f.date(from: iso) else { return nil }
    let today = Calendar.current.startOfDay(for: Date())
    return Calendar.current.dateComponents([.day], from: today, to: d).day
}

func relText(_ d: Int) -> String { d < 0 ? "过期 \(-d) 天" : d == 0 ? "今天" : d == 1 ? "明天" : "\(d) 天后" }

struct HomeView: View {
    @Binding var tab: String
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var gpt: GPTStore
    @EnvironmentObject var layout: LayoutPrefs
    @State private var module = ""
    @State private var showModule = false
    @State private var dest: LedgerRoute = .vps
    @State private var showDest = false
    @State private var showAllDue = false
    @State private var query = ""
    @State private var showSearch = false
    @State private var newNote = false
    @State private var dragging: String?
    @ObservedObject private var quick = QuickAction.shared

    @Environment(\.openModule) private var openModule
    @Environment(\.horizontalSizeClass) private var hSize
    /// 手机 3 列；宽屏按宽度自动排（每个方块至少 150 宽）
    private var cols: [GridItem] {
        hSize == .regular ? [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)] : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty { dashboard } else { GlobalSearchResults(query: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索验证码、密码、备忘录、卡号…")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle("合租管理")
        .task {
            ledger.api = api; codes.api = api; vault.api = api; notes.api = api
            if !ledger.loaded { await reloadAll() }
        }
        .navigationDestination(isPresented: $showDest) { LedgerDestination(route: dest) }
        .navigationDestination(isPresented: $showModule) { ModuleView(id: module) }
        .navigationDestination(isPresented: $showSearch) { GlobalSearchScreen() }
        .navigationDestination(isPresented: $newNote) { NoteEditor(initial: Note()) }
        .toolbar { ToolbarItem(placement: .primaryAction) { NavigationLink { LayoutSettingsView() } label: { Image(systemName: "slider.horizontal.3") } } }
        .onAppear { handleQuick(quick.pending) }
        .onChange(of: quick.pending) { handleQuick($0) }
    }

    /// 桌面图标的快捷操作
    private func handleQuick(_ action: String?) {
        guard let action else { return }
        quick.pending = nil
        tab = "home"
        showSearch = false; showModule = false; showDest = false; newNote = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch action {
            case "search": showSearch = true
            case "newnote": newNote = true
            case "codes", "vault", "notes": open(action)
            default: break
            }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profitCard
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(layout.ordered(ledger.moduleIDs).filter { !layout.homeHidden.contains($0) }, id: \.self) { id in
                        let m = moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt)
                        tile(m.title, m.sub, m.icon, tileColors(id, ledger)) { open(id) }
                            .opacity(dragging == id ? 0.35 : 1)
                            .scaleEffect(dragging == id ? 0.94 : 1)
                            // 长按方块拖到别的位置，松手就记住新顺序
                            .onDrag {
                                dragging = id
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                return NSItemProvider(object: id as NSString)
                            } preview: {
                                tile(m.title, m.sub, m.icon, tileColors(id, ledger)) {}.frame(width: 120)
                            }
                            .onDrop(of: [UTType.text], delegate: TileDrop(target: id, dragging: $dragging, move: moveTile))
                    }
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { _ in dragging = nil; return true }
                Text(isMac ? "按住方块拖动可以调整顺序" : "长按方块拖动可以调整顺序").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, -8)
                dueSection
                if let e = ledger.error { ErrorBanner(message: e) { Task { await ledger.load() } } }
            }
            .padding(hSize == .regular ? 24 : 16)
            .frame(maxWidth: hSize == .regular ? 1200 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await reloadAll() }
    }

    private func reloadAll() async {
        async let a: Void = ledger.load()
        async let b: Void = codes.loaded ? () : codes.load()
        async let c: Void = vault.load()
        async let d: Void = notes.load()
        _ = await (a, b, c, d)
    }

    private var total: Calc.Stats { ledger.monthTotal }
    private func go(_ r: LedgerRoute) {
        switch r {
        case .sheet(let id): open("sheet:" + id)
        case .cards: open("cards")
        case .vps: open("vps")
        }
    }
    /// 底部标签里有这个模块就切过去，没有就在首页里点进去
    private func open(_ id: String) {
        if let openModule { openModule(id); return }          // 宽屏：切左栏
        if layout.tabs.contains(id) { tab = id } else { module = id; showModule = true }
    }

    private var profitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(monthLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(total.n) 个号 · \(Int(total.heads)) 人付费").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Text("本月利润").font(.caption).foregroundStyle(.white.opacity(0.75))
            Text(money(total.profit)).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 0) {
                stat("收费", money(total.income))
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                stat("续费成本", money(total.cost))
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                stat("利润率", total.income > 0 ? "\(Int((total.profit / total.income * 100).rounded()))%" : "—")
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.33, blue: 0.93), Color(red: 0.6, green: 0.33, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .redacted(reason: ledger.loaded ? [] : .placeholder)
    }

    private var monthLabel: String {
        let p = ledger.latestMonth.split(separator: "-")
        return p.count == 2 ? "\(p[0]) 年 \(Int(p[1]) ?? 0) 月" : "本月"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }.frame(maxWidth: .infinity)
    }

    /// 彩色方块：每个模块一种颜色，渐变底、白字
    private func tile(_ title: String, _ sub: String, _ icon: String, _ colors: [Color], _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 6)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: colors[0].opacity(0.3), radius: 6, y: 3)
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func moveTile(_ from: String, _ to: String) {
        var o = layout.ordered(ledger.moduleIDs)
        guard let i = o.firstIndex(of: from), let j = o.firstIndex(of: to), i != j else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            o.move(fromOffsets: IndexSet(integer: i), toOffset: j > i ? j + 1 : j)
            layout.homeOrder = o
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待续费").font(.title3.weight(.semibold))
                Text("\(ledger.due.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("账号 7 天内 · VPS 30 天内").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                if ledger.due.isEmpty {
                    Text(ledger.loaded ? "近期没有要续费的" : "加载中…").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(20)
                }
                let list = showAllDue ? ledger.due : Array(ledger.due.prefix(6))
                ForEach(Array(list.enumerated()), id: \.element.id) { i, d in
                    Button { go(d.route) } label: {
                        HStack(spacing: 12) {
                            Text(relText(d.days)).font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background((d.days < 0 ? Color.bad : Color.warn).opacity(0.13), in: Capsule())
                                .foregroundStyle(d.days < 0 ? Color.bad : Color.warn)
                                .frame(width: 92, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                Text(d.meta).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }.buttonStyle(.plain)
                    if i < list.count - 1 { Divider().padding(.leading, 14) }
                }
                if ledger.due.count > 6 {
                    Divider()
                    Button(showAllDue ? "收起" : "全部 \(ledger.due.count) 项") { withAnimation { showAllDue.toggle() } }
                        .font(.subheadline).padding(12)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct WebPage: Identifiable, Hashable {
    var id: String { path }
    let title: String
    let path: String
}

// MARK: - 更多
struct MoreView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var gpt: GPTStore
    @State private var confirmLogout = false
    @State private var renaming: NavSection?
    @State private var renameText = ""

    var body: some View {
        List {
            // 和网页左侧导航一样的几个板块：名字、顺序、每个板块里有什么都同步。
            // 点板块名旁边的铅笔改名；长按某一项可以上移、下移、移到别的板块
            ForEach(ledger.navSections) { sec in
                Section {
                    ForEach(sec.items, id: \.self) { id in
                        let m = moduleInfo(id, ledger: ledger, codes: codes, vault: vault, notes: notes, gpt: gpt)
                        NavigationLink { ModuleView(id: id) } label: { Label(m.title, systemImage: m.icon) }
                            .contextMenu { itemMenu(id, sec) }
                    }
                    .onMove { from, to in
                        var o = sec.items; o.move(fromOffsets: from, toOffset: to)
                        Task { await ledger.navSetOrder(sec.id, o) }
                    }
                } header: {
                    HStack {
                        Text(sec.label).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        Spacer()
                        Button { renameText = sec.label; renaming = sec } label: { Image(systemName: "pencil").font(.subheadline) }
                            .buttonStyle(.borderless).accessibilityLabel("给「\(sec.label)」改名")
                    }
                    .textCase(nil)
                }
            }
            Section("管理") {
                NavigationLink { SheetsManager() } label: { Label("表设置（新建、改名、排序）", systemImage: "tablecells") }
                NavigationLink { LedgerDataView() } label: { Label("导入导出、备份、历史版本", systemImage: "arrow.up.arrow.down.square") }
                NavigationLink { GroupsManager() } label: { Label("分组管理", systemImage: "folder") }
            }
            Section {
                NavigationLink { LayoutSettingsView() } label: { Label("自定义首页和底部标签", systemImage: "square.grid.3x3.square") }
                if isMac {
                    NavigationLink { MacAppSettings() } label: { Label("App 设置（解锁保护）", systemImage: "desktopcomputer") }
                } else {
                    Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                        Label("App 设置（服务器地址、面容 ID）", systemImage: "iphone")
                    }
                }
                Button(role: .destructive) { confirmLogout = true } label: { Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right") }
            } footer: {
                if case .loggedIn(let u) = api.status { Text("已登录：\(u) · \(api.host)") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("更多")
        .alert("板块改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("板块名字", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let n = renaming { let v = String(renameText.prefix(20)); Task { await ledger.navRename(n.id, v) } }
                renaming = nil
            }
        } message: { Text("网页和 App 的左栏一起改。留空恢复默认名字。") }
        .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await api.logout() } }
        } message: { Text("下次打开 App 要重新输入用户名和密码。") }
    }

    @ViewBuilder
    private func itemMenu(_ id: String, _ sec: NavSection) -> some View {
        Button { Task { await ledger.navShift(id, by: -1) } } label: { Label("上移", systemImage: "arrow.up") }.disabled(sec.items.first == id)
        Button { Task { await ledger.navShift(id, by: 1) } } label: { Label("下移", systemImage: "arrow.down") }.disabled(sec.items.last == id)
        Menu {
            ForEach(ledger.navSections.filter { $0.id != sec.id }) { s in
                Button(s.label) { Task { await ledger.navMove(id, to: s.id) } }
            }
        } label: { Label("移到", systemImage: "arrow.right.square") }
    }

    private func webLink(_ title: String, _ icon: String, _ path: String) -> some View {
        NavigationLink {
            EmbeddedWeb(path: path).ignoresSafeArea(edges: .bottom).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        } label: { Label(title, systemImage: icon) }
    }
}

/// 拖到哪个方块上面，就把拖着的方块挪到那个位置
struct TileDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let move: (String, String) -> Void
    func dropEntered(info: DropInfo) { if let d = dragging, d != target { move(d, target) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// Mac 版的 App 设置（手机上这些在系统「设置」→ 合租管理 里）
struct MacAppSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var api: API
    var body: some View {
        Form {
            Section {
                Toggle("打开 App 时要验证（触控 ID 或电脑密码）", isOn: Binding(get: { settings.lockEnabled }, set: { settings.setLock($0) }))
                if settings.lockEnabled {
                    Picker("离开多久后重新验证", selection: Binding(get: { Int(settings.lockAfterSeconds) }, set: { settings.setLockAfter($0) })) {
                        Text("1 分钟").tag(60); Text("15 分钟").tag(900); Text("1 小时").tag(3600); Text("8 小时").tag(28800)
                    }
                }
            } header: { Text("解锁保护") } footer: { Text("关掉后打开就直接进入，不用再输电脑密码。登录状态一直保存，30 天内不用重新登录。") }
            Section("服务器") { Text(api.host).foregroundStyle(.secondary) }
        }
        .navigationTitle("App 设置")
    }
}
