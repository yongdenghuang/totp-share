import SwiftUI

func daysUntil(_ iso: String) -> Int? {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
    guard iso.count == 10, let d = f.date(from: iso) else { return nil }
    let today = Calendar.current.startOfDay(for: Date())
    return Calendar.current.dateComponents([.day], from: today, to: d).day
}

func relText(_ d: Int) -> String { d < 0 ? "过期 \(-d) 天" : d == 0 ? "今天" : d == 1 ? "明天" : "\(d) 天后" }

struct HomeView: View {
    @Binding var tab: MainTabView.Tab
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var notes: NotesStore
    @State private var dest: LedgerRoute = .vps
    @State private var showDest = false
    @State private var showAllDue = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profitCard
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(ledger.sheetInfo) { s in
                        tile(s.name, s.mode == "resale" ? "\(s.rows) 个项目" : "\(s.rows) 个号", s.grouped ? "person.2.fill" : s.mode == "resale" ? "bolt.fill" : "play.rectangle.fill", Color(red: 0.43, green: 0.36, blue: 0.96)) {
                            go(.sheet(s.id))
                        }
                    }
                    tile("验证码", "\(codes.accounts.count) 个", "key.horizontal.fill", Color(red: 0.05, green: 0.58, blue: 0.53)) { tab = .codes }
                    tile("密码本", "\(vault.items.count) 条", "lock.fill", Color(red: 0.86, green: 0.36, blue: 0.19)) { tab = .vault }
                    tile("备忘录", "\(notes.notes.count) 条", "note.text", Color(red: 0.85, green: 0.6, blue: 0.1)) { tab = .notes }
                    tile("VPS", "\(ledger.vps.count) 台", "server.rack", Color(red: 0.15, green: 0.45, blue: 0.85)) { go(.vps) }
                    tile("支付卡", "\(ledger.cards.count) 张", "creditcard.fill", Color(red: 0.4, green: 0.42, blue: 0.47)) { go(.cards) }
                }
                dueSection
                if let e = ledger.error { ErrorBanner(message: e) { Task { await ledger.load() } } }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("合租管理")
        .refreshable { await reloadAll() }
        .task {
            ledger.api = api; codes.api = api; vault.api = api; notes.api = api
            if !ledger.loaded { await reloadAll() }
        }
        .navigationDestination(isPresented: $showDest) { LedgerDestination(route: dest) }
    }

    private func reloadAll() async {
        async let a: Void = ledger.load()
        async let b: Void = codes.loaded ? () : codes.load()
        async let c: Void = vault.load()
        async let d: Void = notes.load()
        _ = await (a, b, c, d)
    }

    private var total: Calc.Stats { ledger.monthTotal }
    private func go(_ r: LedgerRoute) { dest = r; showDest = true }

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

    private func tile(_ title: String, _ sub: String, _ icon: String, _ color: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 42, height: 42).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 6)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
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
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section("合租账本") {
                ForEach(ledger.sheetInfo) { s in
                    NavigationLink { LedgerDestination(route: .sheet(s.id)) } label: { Label(s.name, systemImage: s.grouped ? "person.2" : s.mode == "resale" ? "bolt" : "play.rectangle") }
                }
                NavigationLink { LedgerDestination(route: .cards) } label: { Label("支付卡", systemImage: "creditcard") }
                NavigationLink { LedgerDestination(route: .vps) } label: { Label("VPS", systemImage: "server.rack") }
                NavigationLink { SheetsManager() } label: { Label("表设置（新建、改名、排序）", systemImage: "tablecells") }
                NavigationLink { LedgerDataView() } label: { Label("导入导出、备份、历史版本", systemImage: "arrow.up.arrow.down.square") }
            }
            Section("后台") {
                NavigationLink { LogsView() } label: { Label("访问记录", systemImage: "list.bullet.rectangle") }
                NavigationLink { GroupsManager() } label: { Label("分组管理", systemImage: "folder") }
                NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
            }
            Section {
                Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                    Label("App 设置（服务器地址、面容 ID）", systemImage: "iphone")
                }
                Button(role: .destructive) { confirmLogout = true } label: { Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right") }
            } footer: {
                if case .loggedIn(let u) = api.status { Text("已登录：\(u) · \(api.host)") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("更多")
        .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await api.logout() } }
        } message: { Text("下次打开 App 要重新输入用户名和密码。") }
    }

    private func webLink(_ title: String, _ icon: String, _ path: String) -> some View {
        NavigationLink {
            EmbeddedWeb(path: path).ignoresSafeArea(edges: .bottom).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        } label: { Label(title, systemImage: icon) }
    }
}
