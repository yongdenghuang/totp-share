import SwiftUI

/// VPS：主机、官网、IP、端口、密码、部署项目（带链接）、流量、续费、价格（美元，换算人民币）、邮箱、登录密码
struct VPSView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @State private var editing: JSON?
    @State private var deleting: JSON?
    @EnvironmentObject var komari: KomariStore
    @AppStorage("vps_page") private var page = "hosts"

    var body: some View {
        List {
            Section { header }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                Picker("", selection: $page) { Text("主机").tag("hosts"); Text("实时监控").tag("monitor") }
                    .pickerStyle(.segmented).padding(.horizontal, 16)
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if page == "monitor" { KomariSection() } else { hostsSection }
            if let e = ledger.error { ErrorBanner(message: e) { Task { await ledger.load() } } }
        }
        .listStyle(.insetGrouped)
        .moduleBackground(Theme.vps)
        .navigationTitle("VPS")
        .refreshable { await ledger.load(); await komari.load() }
        .task {
            // 停在这一页时每 10 秒刷新一次监控数据
            while !Task.isCancelled {
                await komari.load()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .modifier(VPSSheets(editing: $editing, deleting: $deleting))
        .task { ledger.api = api; if !ledger.loaded { await ledger.load() }; await ledger.loadRates() }
    }

    @ViewBuilder private var hostsSection: some View {
            Section {
                ForEach(sorted, id: \.idKey) { v in
                    NavigationLink { VPSDetail(id: v.str("id")) } label: { VPSRow(v: v) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleting = v } label: { Label("删除", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            if !v.str("ip").isEmpty { Button { toast.copy(v.str("ip"), "已复制 IP") } label: { Label("IP", systemImage: "network") }.tint(.brand) }
                            if !v.str("password").isEmpty { Button { toast.copy(v.str("password"), "已复制密码") } label: { Label("密码", systemImage: "key") }.tint(.good) }
                        }
                        .contextMenu {
                            if !v.str("ip").isEmpty { Button { toast.copy(v.str("ip"), "已复制 IP") } label: { Label("复制 IP", systemImage: "network") } }
                            if !v.str("password").isEmpty { Button { toast.copy(v.str("password"), "已复制密码") } label: { Label("复制密码", systemImage: "key") } }
                            if !v.str("loginPassword").isEmpty { Button { toast.copy(v.str("loginPassword"), "已复制登录密码") } label: { Label("复制登录密码", systemImage: "person.badge.key") } }
                            Button { editing = v } label: { Label("编辑", systemImage: "pencil") }
                            Button(role: .destructive) { deleting = v } label: { Label("删除", systemImage: "trash") }
                        }
                        .tintedRow(vpsTint(v))
                }
            } footer: { Text("左滑删除，右滑复制 IP、密码；30 天内要续费的会标出来。") }
    }

}

/// 新建 / 编辑 / 删除 VPS 的弹窗
private struct VPSSheets: ViewModifier {
    @Binding var editing: JSON?
    @Binding var deleting: JSON?
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    func body(content: Content) -> some View {
        content
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { editing = newVps() } label: { Image(systemName: "plus") } } }
        .sheet(item: Binding(get: { editing.map(VPSRef.init) }, set: { if $0 == nil { editing = nil } })) { ref in VPSEditor(original: ref.v) }
        .confirmationDialog("删除「\(deleting?.str("host") ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = deleting?.str("id") { ledger.edit { s in s.editList("vps") { $0.removeAll { $0.str("id") == id } } }; toast.show("已删除") }
            }
        } message: { Text("这台 VPS 的全部信息会删除，不能恢复。") }
    }
}

extension VPSView {
    var sorted: [JSON] {
        ledger.vps.sorted { a, b in (daysUntil(a.str("renew")) ?? 99999) < (daysUntil(b.str("renew")) ?? 99999) }
    }

    var header: some View {
        let priced = ledger.vps.compactMap { Calc.priceUsd($0.str("price")) }
        let usd = priced.reduce(0, +)
        let soon = ledger.vps.filter { (daysUntil($0.str("renew")) ?? 999) <= 30 }.count
        return HStack(spacing: 10) {
            box("主机", "\(ledger.vps.count) 台", soon > 0 ? "\(soon) 台 30 天内续费" : "近期没有续费")
            box("价格合计", "$" + plainNum((usd * 100).rounded() / 100), ledger.rates.map { "≈ " + money(usd * $0) } ?? "正在取汇率…")
        }.padding(.horizontal, 16).padding(.top, 4)
    }

    func box(_ k: String, _ v: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.system(.title3, design: .rounded).weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VPSRef: Identifiable { let v: JSON; var id: String { v.str("id") } }

/// VPS 行的底色：过期红、30 天内续费橙，其余按服务商（没有就按主机名）固定一个颜色
func vpsTint(_ v: JSON) -> Color {
    if let d = daysUntil(v.str("renew")) { if d < 0 { return .bad }; if d <= 30 { return .warn } }
    return Theme.pick(v.str("provider").isEmpty ? v.str("host") : v.str("provider"))
}

struct VPSRow: View {
    let v: JSON
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var komari: KomariStore
    var body: some View {
        HStack(spacing: 12) {
            let host = v.str("host").isEmpty ? "?" : v.str("host")
            Text(String(host.prefix(1)).uppercased()).font(.headline).foregroundStyle(Color.brand)
                .frame(width: 38, height: 38).background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(v.str("host").isEmpty ? "未命名" : v.str("host")).font(.body.weight(.semibold)).lineLimit(1)
                Text([v.str("ip"), v.str("port").isEmpty ? "" : ":" + v.str("port")].joined()).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                let tags = v.list("tags").map { $0.str("name") }.filter { !$0.isEmpty }
                if !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let n = komari.node(for: v) { KomariBadge(n: n) }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(v.str("price").isEmpty ? "—" : v.str("price")).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let u = Calc.priceUsd(v.str("price")), let r = ledger.rates { Text("≈ " + money(u * r)).font(.caption2).foregroundStyle(.secondary) }
                if let d = daysUntil(v.str("renew")) {
                    Text(relText(d)).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((d < 0 ? Color.bad : d <= 30 ? Color.warn : Color.gray).opacity(0.13), in: Capsule())
                        .foregroundStyle(d < 0 ? Color.bad : d <= 30 ? Color.warn : .secondary)
                }
            }
        }.padding(.vertical, 2)
    }
}

/// 一台 VPS 的详情：每一行点一下复制
struct VPSDetail: View {
    let id: String
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @Environment(\.openURL) private var openURL
    @State private var showPw = false
    @State private var editing = false
    @EnvironmentObject var komari: KomariStore

    private var v: JSON { ledger.vps.first { $0.str("id") == id } ?? [:] }

    var body: some View {
        List {
            if komari.configured == true {
                let n = komari.node(for: v)
                Section {
                    if let n { KomariCard(n: n).tintedRow(komariTint(n)) }
                    Picker("关联节点", selection: Binding(get: { v.str("komari") }, set: { setKomari($0) })) {
                        Text(n != nil && v.str("komari").isEmpty ? "按名字自动（\(n!.str("name"))）" : "按名字自动匹配").tag("")
                        ForEach(komari.nodes.indices, id: \.self) { i in Text(komari.nodes[i].str("name") + " " + komari.nodes[i].str("region")).tag(komari.nodes[i].str("uuid")) }
                    }
                } header: { Text("实时监控") } footer: { if n == nil { Text("名字对不上 Komari 里的节点，在上面选一台关联。") } }
            }
            Section {
                row("IP", v.str("ip"), mono: true)
                row("端口", v.str("port"), mono: true)
                secretRow("密码", v.str("password"))
                if let u = url(v.str("site")) {
                    Button { openURL(u) } label: { HStack { field("官网", u.host ?? u.absoluteString, mono: false, color: .brand); Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(Color.brand) } }
                }
            }
            let tags = v.list("tags").filter { !$0.str("name").isEmpty }
            if !tags.isEmpty {
                Section("部署") {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, t in
                        if let u = url(t.str("url")) {
                            Button { openURL(u) } label: { HStack { Text(t.str("name")).foregroundStyle(.primary); Spacer(); Text(u.host ?? "").font(.caption).foregroundStyle(.secondary); Image(systemName: "arrow.up.right").foregroundStyle(Color.brand) } }
                        } else { Text(t.str("name")) }
                    }
                }
            }
            Section("续费") {
                row("续费日期", v.str("renew") + (daysUntil(v.str("renew")).map { "（\(relText($0))）" } ?? ""), mono: false)
                row("价格", v.str("price") + ((Calc.priceUsd(v.str("price")).flatMap { u in ledger.rates.map { " ≈ " + money(u * $0) } }) ?? ""), mono: false)
                row("流量及重置", v.str("traffic"), mono: false)
            }
            Section("账号") {
                row("注册邮箱", v.str("email"), mono: false)
                secretRow("登录密码", v.str("loginPassword"))
            }
        }
        .listStyle(.insetGrouped)
        .tint(.primary)
        .navigationTitle(v.str("host").isEmpty ? "VPS" : v.str("host"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("编辑") { editing = true }.tint(.brand) } }
        .sheet(isPresented: $editing) { VPSEditor(original: v) }
    }

    private func setKomari(_ uuid: String) {
        ledger.edit { s in s.editList("vps") { l in if let i = l.firstIndex(where: { $0.str("id") == id }) { if uuid.isEmpty { l[i].removeValue(forKey: "komari") } else { l[i]["komari"] = uuid } } } }
    }

    private func url(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespaces); if t.isEmpty { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        return URL(string: t)
    }

    private func field(_ k: String, _ value: String, mono: Bool, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(value).font(mono ? .body.monospaced() : .body).foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func row(_ k: String, _ value: String, mono: Bool) -> some View {
        if !value.isEmpty { Button { toast.copy(value, "已复制\(k)") } label: { field(k, value, mono: mono) } }
    }

    @ViewBuilder
    private func secretRow(_ k: String, _ value: String) -> some View {
        if !value.isEmpty {
            Button { toast.copy(value, "已复制\(k)") } label: {
                HStack {
                    field(k, showPw ? value : "••••••••••", mono: true)
                    Spacer()
                    Button { showPw.toggle() } label: { Image(systemName: showPw ? "eye.slash" : "eye").foregroundStyle(Color.brand) }.buttonStyle(.borderless)
                }
            }
        }
    }
}

struct VPSEditor: View {
    let original: JSON
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    struct TagItem: Identifiable { let id = UUID(); var name: String; var url: String }
    @State private var f: [String: String] = [:]
    @State private var tags: [TagItem] = []
    @State private var hasRenew = false
    @State private var renew = Date()
    @State private var ready = false
    private let keys = ["host", "site", "ip", "port", "password", "traffic", "price", "email", "loginPassword"]

    var body: some View {
        NavigationStack {
            Form {
                Section("主机") {
                    tf("主机名，如 GreenCloud-JP", "host")
                    tf("官网网址", "site", url: true)
                }
                Section("连接") {
                    tf("IP", "ip", mono: true)
                    tf("端口", "port", mono: true)
                    tf("root 密码", "password", mono: true)
                }
                Section {
                    ForEach($tags) { $t in
                        VStack(spacing: 6) {
                            TextField("项目名，如 xui面板", text: $t.name)
                            TextField("网址（点标签时打开，可不填）", text: $t.url).font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        }
                    }.onDelete { tags.remove(atOffsets: $0) }
                    Button { tags.append(TagItem(name: "", url: "")) } label: { Label("添加部署项目", systemImage: "plus.circle") }
                } header: { Text("部署") } footer: { Text("左滑删除一个项目。") }
                Section("续费") {
                    Toggle("续费日期", isOn: $hasRenew.animation())
                    if hasRenew { DatePicker("日期", selection: $renew, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN")) }
                    tf("价格，如 $45.68/年（按第一个数字算美元）", "price")
                    tf("流量及重置", "traffic")
                }
                Section("账号") {
                    tf("注册邮箱", "email", url: true)
                    tf("登录密码", "loginPassword", mono: true)
                }
            }
            .navigationTitle(original.str("host").isEmpty ? "添加 VPS" : "编辑 VPS").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!ready) }
            }
            .onAppear {
                guard !ready else { return }
                for k in keys { f[k] = original.str(k) }
                tags = original.list("tags").map { TagItem(name: $0.str("name"), url: $0.str("url")) }
                if let d = parseISO(original.str("renew")) { hasRenew = true; renew = d }
                ready = true
            }
        }
    }

    private func tf(_ ph: String, _ key: String, mono: Bool = false, url: Bool = false) -> some View {
        TextField(ph, text: Binding(get: { f[key] ?? "" }, set: { f[key] = $0 }))
            .font(mono ? .body.monospaced() : .body)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .keyboardType(url ? .URL : .default)
    }

    private func save() {
        var fields: JSON = [:]
        for k in keys { fields[k] = (f[k] ?? "").trimmingCharacters(in: .whitespaces) }
        if var s = fields["site"] as? String, !s.isEmpty, !s.lowercased().hasPrefix("http") { s = "https://" + s; fields["site"] = s }
        fields["tags"] = tags.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { t -> JSON in
            var u = t.url.trimmingCharacters(in: .whitespaces)
            if !u.isEmpty && !u.lowercased().hasPrefix("http") { u = "https://" + u }
            return ["name": t.name.trimmingCharacters(in: .whitespaces), "url": u]
        }
        fields["renew"] = hasRenew ? isoDate(renew) : ""
        let id = original.str("id")
        let exists = ledger.vps.contains { $0.str("id") == id }
        if exists {
            ledger.edit { s in s.editList("vps") { l in if let i = l.firstIndex(where: { $0.str("id") == id }) { for (k, v) in fields { l[i][k] = v } } } }
        } else {
            var item = original
            for (k, v) in fields { item[k] = v }
            let it = item
            ledger.edit { s in s.editList("vps") { $0.append(it) } }
        }
        toast.show("已保存"); dismiss()
    }
}
