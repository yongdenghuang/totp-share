import SwiftUI

struct TotpAccount: Identifiable, Hashable {
    let id: Int
    var name: String
    var group: String
    var hasPassword: Bool
    var shareUrl: String
    var lastSeen: String
    var duplicate: Bool
}

struct TotpGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let color: String
}

@MainActor
final class CodesStore: ObservableObject {
    var api: API!
    @Published var accounts: [TotpAccount] = []
    @Published var groups: [TotpGroup] = []
    @Published var codes: [Int: String] = [:]
    @Published var period = 30
    @Published var expiresAt = Date.distantPast
    @Published var error: String?
    @Published var loaded = false
    private var fetchingCodes = false

    func load() async {
        do {
            let d = try await api.get("/api/app/accounts")
            accounts = d.list("accounts").map {
                TotpAccount(id: $0.int("id"), name: $0.str("name"), group: $0.str("group"), hasPassword: $0.bool("hasPassword"),
                            shareUrl: $0.str("shareUrl"), lastSeen: $0.str("lastSeen"), duplicate: $0.bool("duplicate"))
            }
            groups = d.list("groups").map { TotpGroup(name: $0.str("name"), color: $0.str("color")) }
            error = nil
            loaded = true
            await refreshCodes()
        } catch { self.error = error.localizedDescription; loaded = true }
    }

    func refreshCodes() async {
        guard !fetchingCodes else { return }
        fetchingCodes = true
        defer { fetchingCodes = false }
        guard let d = try? await api.get("/admin/codes") else { return }
        var out: [Int: String] = [:]
        for (k, v) in d.dict("codes") { if let id = Int(k), let c = v as? String { out[id] = c } }
        codes = out
        period = max(1, d.int("period"))
        expiresAt = Date().addingTimeInterval(Double(max(1, d.int("remaining"))))
    }

    /// 按分组的顺序排好；没有分组的放最后
    var sections: [(group: TotpGroup?, items: [TotpAccount])] {
        var out: [(TotpGroup?, [TotpAccount])] = groups.compactMap { g in
            let items = accounts.filter { $0.group == g.name }
            return items.isEmpty ? nil : (g, items)
        }
        let known = Set(groups.map(\.name))
        let loose = accounts.filter { !known.contains($0.group) }
        if !loose.isEmpty { out.append((nil, loose)) }
        return out
    }

    func color(of group: String) -> Color {
        groups.first { $0.name == group }.map { Color(hex: $0.color) } ?? .gray
    }

    // MARK: 操作
    func password(_ a: TotpAccount) async throws -> String {
        try await api.post("/admin/accounts/\(a.id)/password/reveal").str("password")
    }
    func shareText(_ a: TotpAccount) async throws -> String {
        try await api.post("/admin/accounts/\(a.id)/share-text").str("text")
    }
    func setPassword(_ a: TotpAccount, _ pw: String) async throws {
        _ = try await api.post("/admin/accounts/\(a.id)/password", ["password": pw])
        update(a.id) { $0.hasPassword = true }
    }
    func rename(_ a: TotpAccount, _ name: String) async throws {
        let d = try await api.post("/admin/accounts/\(a.id)/field", ["field": "name", "value": name])
        update(a.id) { $0.name = d.str("raw_value") }
    }
    func move(_ a: TotpAccount, to group: String) async throws {
        let d = try await api.post("/admin/accounts/\(a.id)/field", ["field": "group_name", "value": group])
        update(a.id) { $0.group = d.str("raw_value") }
    }
    func regen(_ a: TotpAccount) async throws -> String {
        let url = try await api.post("/admin/accounts/\(a.id)/regen").str("url")
        update(a.id) { $0.shareUrl = url }
        return url
    }
    func remove(_ a: TotpAccount) async throws {
        _ = try await api.delete("/api/app/accounts/\(a.id)")
        accounts.removeAll { $0.id == a.id }
    }
    /// 新建验证码账号（和网页上「添加账号」同一个接口）；同名时 duplicate = true，需要确认后带 confirm 再发一次
    func add(name: String, secret: String, password: String, group: String, confirmDuplicate: Bool) async throws {
        _ = try await api.post("/admin/hezu/api/accounts", ["name": name, "secret": secret, "password": password,
                                                             "group": group, "confirmDuplicate": confirmDuplicate])
        await load()
    }
    private func update(_ id: Int, _ f: (inout TotpAccount) -> Void) {
        if let i = accounts.firstIndex(where: { $0.id == id }) { f(&accounts[i]) }
    }
}

struct CodesView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var store: CodesStore
    @EnvironmentObject var toast: Toast
    @State private var query = ""
    @State private var groupFilter = ""
    @State private var adding = false
    @State private var editing: EditAction?
    @State private var confirmDelete: TotpAccount?
    @State private var webPage: WebPage?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(ceil(store.expiresAt.timeIntervalSince(ctx.date))))
            List {
                if !store.groups.isEmpty {
                    Section { groupChips }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                ForEach(filteredSections, id: \.title) { sec in
                    Section {
                        ForEach(sec.items) { a in row(a, left: left).tintedRow(sec.color) }
                    } header: {
                        HStack(spacing: 6) {
                            Circle().fill(sec.color).frame(width: 8, height: 8)
                            Text(sec.title)
                            Text("\(sec.items.count)").foregroundStyle(.tertiary)
                        }
                    }
                }
                if store.loaded && store.accounts.isEmpty && store.error == nil {
                    Text("还没有验证码账号，点右上角 ＋ 添加。").foregroundStyle(.secondary)
                }
                if let e = store.error { ErrorBanner(message: e) { Task { await store.load() } } }
            }
            .listStyle(.insetGrouped)
            .moduleBackground(Theme.codes)
            .onChange(of: left) { if $0 == 0 { Task { await store.refreshCodes() } } }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { CountdownRing(left: left, period: store.period) }
            }
        }
        .navigationTitle("验证码")
        .searchable(text: $query, prompt: "搜索账号或分组")
        .refreshable { await store.load() }
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .task { store.api = api; if !store.loaded { await store.load() } else { await store.refreshCodes() } }
        .sheet(isPresented: $adding) { AddTotpSheet() }
        .sheet(item: $editing) { EditTextSheet(action: $0) }
        .sheet(item: $webPage) { p in NavigationStack { EmbeddedWeb(path: p.path).navigationTitle(p.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { webPage = nil; Task { await store.load() } } } } } }
        .confirmationDialog("删除「\(confirmDelete?.name ?? "")」？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let a = confirmDelete { Task { do { try await store.remove(a); toast.show("已删除") } catch { toast.show(error.localizedDescription) } } }
            }
        } message: { Text("验证码密钥和分享链接会一起删除，合租人的链接立即失效，不能恢复。") }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", nil, groupFilter.isEmpty) { groupFilter = "" }
                ForEach(store.groups) { g in chip(g.name, Color(hex: g.color), groupFilter == g.name) { groupFilter = groupFilter == g.name ? "" : g.name } }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
        }
    }

    private func chip(_ t: String, _ c: Color?, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let c { Circle().fill(on ? .white : c).frame(width: 7, height: 7) }
                Text(t).font(.subheadline.weight(on ? .semibold : .regular))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? Color.brand : Color(.secondarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(on ? .white : .primary)
        }.buttonStyle(.plain)
    }

    private var filteredSections: [(title: String, color: Color, items: [TotpAccount])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.sections.compactMap { s in
            let name = s.group?.name ?? "未分组"
            if !groupFilter.isEmpty && name != groupFilter { return nil }
            let items = s.items.filter { q.isEmpty || $0.name.lowercased().contains(q) || name.lowercased().contains(q) }
            return items.isEmpty ? nil : (name, s.group.map { Color(hex: $0.color) } ?? .gray, items)
        }
    }

    @ViewBuilder
    private func row(_ a: TotpAccount, left: Int) -> some View {
        let code = store.codes[a.id]
        Button {
            if let code { toast.copy(code, "已复制验证码") }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(a.name).font(.body.weight(.medium)).lineLimit(1)
                        if a.duplicate { Tag(text: "重名", color: .warn) }
                    }
                    HStack(spacing: 8) {
                        if a.hasPassword { HStack(spacing: 3) { Image(systemName: "key.fill").imageScale(.small); Text("有密码") } }
                        if !a.lastSeen.isEmpty { Text("访问 \(a.lastSeen)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(code.map { String($0.prefix(3)) + " " + String($0.dropFirst(3)) } ?? "··· ···")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(left <= 5 ? Color.bad : Color.brand)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if a.hasPassword {
                Button { copyPassword(a) } label: { Label("复制密码", systemImage: "key") }.tint(.brand)
            }
            Button { copyShare(a) } label: { Label("分享信息", systemImage: "square.and.arrow.up") }.tint(.good)
        }
        .contextMenu { menu(a) }
    }

    @ViewBuilder
    private func menu(_ a: TotpAccount) -> some View {
        if let code = store.codes[a.id] { Button { toast.copy(code, "已复制验证码") } label: { Label("复制验证码", systemImage: "number") } }
        if a.hasPassword { Button { copyPassword(a) } label: { Label("复制账号密码", systemImage: "key") } }
        Button { toast.copy(a.name, "已复制账号") } label: { Label("复制账号名", systemImage: "person") }
        Button { copyShare(a) } label: { Label("复制分享信息", systemImage: "text.bubble") }
        Button { toast.copy(a.shareUrl, "已复制分享链接") } label: { Label("复制分享链接", systemImage: "link") }
        Divider()
        Button { editing = .password(a) } label: { Label(a.hasPassword ? "改密码" : "设置密码", systemImage: "key.viewfinder") }
        Button { editing = .rename(a) } label: { Label("重命名", systemImage: "pencil") }
        Menu {
            Button("未分组") { move(a, "") }
            ForEach(store.groups) { g in Button(g.name) { move(a, g.name) } }
        } label: { Label("移到分组", systemImage: "folder") }
        Button { Task { do { let u = try await store.regen(a); toast.copy(u, "已换新链接并复制") } catch { toast.show(error.localizedDescription) } } } label: {
            Label("换一个分享链接", systemImage: "arrow.triangle.2.circlepath")
        }
        Button { webPage = WebPage(title: "编辑 \(a.name)", path: "/admin/accounts/\(a.id)/edit") } label: { Label("编辑密钥 / 分享密码…", systemImage: "slider.horizontal.3") }
        Divider()
        Button(role: .destructive) { confirmDelete = a } label: { Label("删除", systemImage: "trash") }
    }

    private func copyPassword(_ a: TotpAccount) {
        Task { do { toast.copy(try await store.password(a), "已复制密码") } catch { toast.show(error.localizedDescription) } }
    }
    private func copyShare(_ a: TotpAccount) {
        Task { do { toast.copy(try await store.shareText(a), "已复制分享信息") } catch { toast.show(error.localizedDescription) } }
    }
    private func move(_ a: TotpAccount, _ g: String) {
        Task { do { try await store.move(a, to: g); toast.show("已移到「\(g.isEmpty ? "未分组" : g)」") } catch { toast.show(error.localizedDescription) } }
    }
}

/// 左上角的倒计时圆环
struct CountdownRing: View {
    let left: Int
    let period: Int
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat(left) / CGFloat(max(period, 1)))
                .stroke(left <= 5 ? Color.bad : Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: left)
            Text("\(left)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - 改密码 / 重命名
enum EditAction: Identifiable {
    case password(TotpAccount), rename(TotpAccount)
    var id: String { switch self { case .password(let a): return "p\(a.id)"; case .rename(let a): return "r\(a.id)" } }
}

struct EditTextSheet: View {
    let action: EditAction
    @EnvironmentObject var store: CodesStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var previous = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                switch action {
                case .password(let a):
                    Section {
                        TextField("新密码", text: $text).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("生成随机密码") { text = randomPassword(16) }
                    } header: { Text(a.name) } footer: {
                        Text("和合租账本里的是同一个密码，改了两边一起变；原来的密码会留作「上一个密码」。")
                    }
                    if !previous.isEmpty {
                        Section("当前密码") {
                            Button { toast.copy(previous, "已复制当前密码") } label: { Text(previous).font(.body.monospaced()) }
                        }
                    }
                case .rename(let a):
                    Section { TextField("账号名称", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled() } header: { Text(a.name) }
                }
                if let error { Text(error).foregroundStyle(Color.bad) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .task {
                switch action {
                case .password(let a): if a.hasPassword { previous = (try? await store.password(a)) ?? "" }
                case .rename(let a): text = a.name
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String { if case .password = action { return "账号密码" }; return "重命名" }

    private func save() {
        busy = true
        Task {
            do {
                switch action {
                case .password(let a): try await store.setPassword(a, text.trimmingCharacters(in: .whitespaces))
                case .rename(let a): try await store.rename(a, text.trimmingCharacters(in: .whitespaces))
                }
                toast.show("已保存"); dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - 添加验证码账号
struct AddTotpSheet: View {
    @EnvironmentObject var store: CodesStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var secret = ""
    @State private var password = ""
    @State private var group = ""
    @State private var error: String?
    @State private var busy = false
    @State private var askDuplicate: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("账号名称（比如邮箱）", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    Picker("分组", selection: $group) {
                        Text("未分组").tag("")
                        ForEach(store.groups) { Text($0.name).tag($0.name) }
                    }
                }
                Section {
                    TextField("TOTP 密钥", text: $secret).font(.body.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("从剪贴板粘贴") { secret = UIPasteboard.general.string ?? secret }
                } footer: { Text("网站「两步验证」里给的那串字母数字（Base32），空格可以不管。") }
                Section {
                    TextField("账号登录密码（可不填）", text: $password).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: { Text("加密保存，合租账本里会自动出现这个账号，收费等在账本里填。") }
                if let error { Text(error).foregroundStyle(Color.bad) }
            }
            .navigationTitle("添加验证码账号").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("添加") { save(false) }.disabled(busy || name.isEmpty || secret.isEmpty) }
            }
            .alert("已有同名账号", isPresented: Binding(get: { askDuplicate != nil }, set: { if !$0 { askDuplicate = nil } })) {
                Button("取消", role: .cancel) {}
                Button("仍然添加") { save(true) }
            } message: { Text(askDuplicate ?? "") }
        }
    }

    private func save(_ confirm: Bool) {
        busy = true; error = nil
        Task {
            do {
                try await store.add(name: name.trimmingCharacters(in: .whitespaces), secret: secret, password: password, group: group, confirmDuplicate: confirm)
                toast.show("已添加"); dismiss()
            } catch let e as APIError where e.payload["duplicate"] as? Bool == true {
                askDuplicate = e.localizedDescription + "\n确认不是重复添加的话，可以继续。"
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

func randomPassword(_ n: Int) -> String {
    let sets = ["ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnopqrstuvwxyz", "23456789", "!@#$%&*?-_"].map(Array.init)
    let all = sets.flatMap { $0 }
    var out = sets.map { $0.randomElement()! }
    while out.count < n { out.append(all.randomElement()!) }
    return String(out.shuffled())
}
