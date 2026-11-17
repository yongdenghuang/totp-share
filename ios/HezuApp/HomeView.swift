import SwiftUI

/// 合租账本（只读）：首页要用的本月收费 / 成本 / 利润、各表账号数、待续费。
/// 算法和网页 app.js 的 stats / dueList 一致。
@MainActor
final class LedgerStore: ObservableObject {
    struct Sheet: Identifiable { let id: String; let name: String; let mode: String; let grouped: Bool; var rows: Int }
    struct Due: Identifiable { let id = UUID(); let days: Int; let title: String; let meta: String; let isVPS: Bool; let sheet: String }

    var api: API!
    @Published var month = ""
    @Published var income = 0.0
    @Published var cost = 0.0
    @Published var heads = 0.0
    @Published var accounts = 0
    @Published var sheets: [Sheet] = []
    @Published var cards = 0
    @Published var vps = 0
    @Published var due: [Due] = []
    @Published var error: String?
    @Published var loaded = false

    var profit: Double { income - cost }

    func load() async {
        do {
            let d = try await api.get("/admin/hezu/api/state")
            compute(d.dict("state"), groups: d.list("groups"))
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func compute(_ S: [String: Any], groups: [[String: Any]]) {
        let months = S.dict("months")
        month = months.keys.sorted().last ?? ""
        let rowsBySheet = (months[month] as? [String: Any])?.dict("rows") ?? [:]
        let groupName = Dictionary(uniqueKeysWithValues: groups.map { ($0.str("id"), $0.str("name")) })
        var inc = 0.0, cst = 0.0, hd = 0.0, n = 0
        var shs: [Sheet] = [], dues: [Due] = []
        for sh in S.list("sheets") {
            let id = sh.str("id"), mode = sh.str("mode")
            let rows = (rowsBySheet[id] as? [[String: Any]]) ?? []
            for r in rows {
                let members = r.list("members")
                if !r.bool("stopped") { n += 1 }
                hd += mode == "members" ? Double(members.count) : num(r["count"])
                inc += mode == "members" ? members.reduce(0) { $0 + num($1["amount"]) } : num(r["unitPrice"]) * num(r["count"])
                cst += mode == "resale" ? num(r["unitCost"]) * num(r["count"]) : num(r["cost"])
                if !r.bool("stopped"), let d = daysUntil(r.str("renew")), d <= 7 {
                    let label = sh.bool("grouped") ? (groupName[r.str("group")] ?? sh.str("name")) : sh.str("name")
                    dues.append(Due(days: d, title: r.str("account").isEmpty ? "未填账号" : r.str("account"), meta: label, isVPS: false, sheet: id))
                }
            }
            shs.append(Sheet(id: id, name: sh.str("name"), mode: mode, grouped: sh.bool("grouped"), rows: rows.count))
        }
        for v in S.list("vps") {
            if let d = daysUntil(v.str("renew")), d <= 30 {
                dues.append(Due(days: d, title: v.str("host").isEmpty ? "未命名 VPS" : v.str("host"), meta: "VPS", isVPS: true, sheet: "vps"))
            }
        }
        income = inc; cost = cst; heads = hd; accounts = n
        sheets = shs; cards = S.list("cards").count; vps = S.list("vps").count
        due = dues.sorted { $0.days < $1.days }
    }
}

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
    @State private var web: WebPage?
    @State private var showAllDue = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profitCard
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(ledger.sheets) { s in
                        tile(s.name, "\(s.rows) 个号", s.grouped ? "person.2.fill" : s.mode == "resale" ? "bolt.fill" : "play.rectangle.fill", Color(red: 0.43, green: 0.36, blue: 0.96)) {
                            web = WebPage(title: s.name, path: "/admin/hezu#\(s.id)")
                        }
                    }
                    tile("验证码", "\(codes.accounts.count) 个", "key.horizontal.fill", Color(red: 0.05, green: 0.58, blue: 0.53)) { tab = .codes }
                    tile("密码本", "\(vault.items.count) 条", "lock.fill", Color(red: 0.86, green: 0.36, blue: 0.19)) { tab = .vault }
                    tile("备忘录", "\(notes.notes.count) 条", "note.text", Color(red: 0.85, green: 0.6, blue: 0.1)) { tab = .notes }
                    tile("VPS", "\(ledger.vps) 台", "server.rack", Color(red: 0.15, green: 0.45, blue: 0.85)) { web = WebPage(title: "VPS", path: "/admin/hezu#vps") }
                    tile("支付卡", "\(ledger.cards) 张", "creditcard.fill", Color(red: 0.4, green: 0.42, blue: 0.47)) { web = WebPage(title: "支付卡", path: "/admin/hezu#cards") }
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
        .fullScreenCover(item: $web, onDismiss: { Task { await ledger.load() } }) { p in
            NavigationStack {
                EmbeddedWeb(path: p.path).ignoresSafeArea(edges: .bottom)
                    .navigationTitle(p.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button { web = nil } label: { Image(systemName: "chevron.down") } } }
            }
        }
    }

    private func reloadAll() async {
        async let a: Void = ledger.load()
        async let b: Void = codes.loaded ? () : codes.load()
        async let c: Void = vault.load()
        async let d: Void = notes.load()
        _ = await (a, b, c, d)
    }

    private var profitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(monthLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(ledger.accounts) 个号 · \(Int(ledger.heads)) 人付费").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Text("本月利润").font(.caption).foregroundStyle(.white.opacity(0.75))
            Text(money(ledger.profit)).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 0) {
                stat("收费", money(ledger.income))
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                stat("续费成本", money(ledger.cost))
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                stat("利润率", ledger.income > 0 ? "\(Int((ledger.profit / ledger.income * 100).rounded()))%" : "—")
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.33, blue: 0.93), Color(red: 0.6, green: 0.33, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .redacted(reason: ledger.loaded ? [] : .placeholder)
    }

    private var monthLabel: String {
        let p = ledger.month.split(separator: "-")
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
                    Button { web = WebPage(title: d.isVPS ? "VPS" : d.meta, path: "/admin/hezu#\(d.sheet)") } label: {
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
                ForEach(ledger.sheets) { s in webLink(s.name, s.grouped ? "person.2" : s.mode == "resale" ? "bolt" : "play.rectangle", "/admin/hezu#\(s.id)") }
                webLink("支付卡", "creditcard", "/admin/hezu#cards")
                webLink("VPS", "server.rack", "/admin/hezu#vps")
            }
            Section("后台") {
                webLink("访问记录", "list.bullet.rectangle", "/admin/logs")
                webLink("分组管理", "folder", "/admin/groups")
                webLink("设置", "gearshape", "/admin/settings")
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
