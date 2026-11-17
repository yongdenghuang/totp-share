import SwiftUI

// MARK: - 访问记录（谁在什么时候打开了分享链接）
struct LogsView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var toast: Toast
    @State private var logs: [JSON] = []
    @State private var accounts: [JSON] = []
    @State private var account = 0
    @State private var page = 1
    @State private var hasNext = false
    @State private var info = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("账号", selection: $account) {
                    Text("全部账号").tag(0)
                    ForEach(accounts, id: \.idKey) { Text($0.str("name")).tag($0.int("id")) }
                }
            } footer: { Text(info) }
            Section {
                ForEach(logs, id: \.idKey) { l in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l.str("account")).font(.body.weight(.semibold)).lineLimit(1)
                            Tag(text: eventName(l.str("event")), color: l.str("event") == "view" ? .brand : .warn)
                            Spacer()
                            Text(l.str("last")).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Button { toast.copy(l.str("ip"), "已复制 IP") } label: { Text(l.str("ip")).font(.caption.monospaced()) }.buttonStyle(.borderless)
                            if !l.str("country").isEmpty { Text(l.str("country")).font(.caption) }
                            if l.int("hits") > 1 { Text("× \(l.int("hits")) 次").font(.caption) }
                            if l.str("first") != l.str("last") { Text("从 \(l.str("first"))").font(.caption) }
                        }.foregroundStyle(.secondary)
                        if !l.str("userAgent").isEmpty { Text(device(l.str("userAgent"))).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                    }.padding(.vertical, 2)
                }
                if logs.isEmpty && !loading { Text("还没有访问记录").foregroundStyle(.secondary) }
                if hasNext { Button("加载更多") { Task { await load(page + 1) } } }
            }
            if let error { ErrorBanner(message: error) { Task { await load(1) } } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("访问记录")
        .refreshable { await load(1) }
        .onChange(of: account) { _ in Task { await load(1) } }
        .task { if logs.isEmpty { await load(1) } }
    }

    private func load(_ p: Int) async {
        loading = true; defer { loading = false }
        do {
            let d = try await api.get("/api/app/logs?page=\(p)" + (account > 0 ? "&account=\(account)" : ""))
            logs = p == 1 ? d.list("logs") : logs + d.list("logs")
            accounts = d.list("accounts"); page = p; hasNext = d.bool("hasNext")
            info = "保留最近 \(d.int("retentionDays")) 天；同一个人 \(d.int("mergeMinutes")) 分钟内的重复访问合并成一条。"
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func eventName(_ e: String) -> String {
        switch e { case "view": return "看验证码"; case "pw_fail": return "密码输错"; default: return e }
    }
    private func device(_ ua: String) -> String {
        let l = ua.lowercased()
        let os = l.contains("iphone") ? "iPhone" : l.contains("ipad") ? "iPad" : l.contains("android") ? "Android" : l.contains("mac os") ? "Mac" : l.contains("windows") ? "Windows" : ""
        let br = l.contains("micromessenger") ? "微信" : l.contains("edg/") ? "Edge" : l.contains("chrome") ? "Chrome" : l.contains("safari") ? "Safari" : l.contains("firefox") ? "Firefox" : ""
        let s = [os, br].filter { !$0.isEmpty }.joined(separator: " · ")
        return s.isEmpty ? String(ua.prefix(60)) : s
    }
}

// MARK: - 分组管理（验证码账号、合租账本共用）
struct GroupsManager: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var toast: Toast
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var ledger: LedgerStore
    @State private var groups: [JSON] = []
    @State private var editing: GroupEdit?
    @State private var deleting: JSON?

    struct GroupEdit: Identifiable { var id: String { old.isEmpty ? "new" : old }; var old: String; var name: String; var color: Color }

    var body: some View {
        List {
            Section {
                ForEach(groups, id: \.idKeyName) { g in
                    Button { editing = GroupEdit(old: g.str("name"), name: g.str("name"), color: Color(hex: g.str("color"))) } label: {
                        HStack {
                            Circle().fill(Color(hex: g.str("color"))).frame(width: 12, height: 12)
                            Text(g.str("name")).foregroundStyle(.primary)
                            Spacer()
                            Text("\(g.int("count")) 个账号").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button(role: .destructive) { deleting = g } label: { Label("删除", systemImage: "trash") } }
                }
                .onMove(perform: move)
                Button { editing = GroupEdit(old: "", name: "", color: .brand) } label: { Label("新建分组", systemImage: "plus.circle") }
            } footer: { Text("拖动调整顺序，左滑删除，点一下改名或换颜色。验证码账号和合租账本用的是同一套分组。") }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("分组管理")
        .task { await load() }
        .sheet(item: $editing) { e in GroupEditor(edit: e) { groups = $0; refreshOthers() } }
        .alert("删除分组「\(deleting?.str("name") ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let g = deleting { Task { do { groups = try await api.post("/api/app/groups/delete", ["name": g.str("name")]).list("groups"); refreshOthers(); toast.show("已删除") } catch { toast.show(error.localizedDescription) } } }
            }
        } message: { Text("组内 \(deleting?.int("count") ?? 0) 个账号会变成未分组。") }
    }

    private func load() async { groups = (try? await api.get("/api/app/groups").list("groups")) ?? groups }

    private func move(_ from: IndexSet, _ to: Int) {
        groups.move(fromOffsets: from, toOffset: to)
        let order = groups.map { $0.str("name") }
        Task {
            do { _ = try await api.post("/admin/groups/reorder", ["order": order]); refreshOthers() }
            catch { toast.show(error.localizedDescription); await load() }
        }
    }

    private func refreshOthers() { Task { await codes.load(); await ledger.load() } }
}

extension Dictionary where Key == String, Value == Any { var idKeyName: String { str("name") } }

struct GroupEditor: View {
    @State var edit: GroupsManager.GroupEdit
    var done: ([JSON]) -> Void
    @EnvironmentObject var api: API
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $edit.name)
                ColorPicker("标签颜色", selection: $edit.color, supportsOpacity: false)
                HStack { Text("预览"); Spacer(); Tag(text: edit.name.isEmpty ? "分组" : edit.name, color: edit.color) }
                if let error { Text(error).foregroundStyle(Color.bad) }
            }
            .navigationTitle(edit.old.isEmpty ? "新建分组" : "编辑分组").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(edit.name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }.presentationDetents([.medium])
    }

    private func save() {
        Task {
            do {
                var groups: [JSON]
                if edit.old.isEmpty {
                    groups = try await api.post("/api/app/groups", ["name": edit.name]).list("groups")
                    // 新建时选了颜色就顺便设上
                    if let created = groups.last?.str("name") {
                        groups = try await api.post("/api/app/groups/update", ["old": created, "name": created, "color": edit.color.hex]).list("groups")
                    }
                } else {
                    groups = try await api.post("/api/app/groups/update", ["old": edit.old, "name": edit.name, "color": edit.color.hex]).list("groups")
                }
                done(groups); toast.show("已保存"); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - 设置
struct SettingsView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var toast: Toast
    @State private var loaded = false
    @State private var username = ""
    @State private var shareEnabled = false
    @State private var sharePasswordSet = false
    @State private var sharePassword = ""
    @State private var template = ""
    @State private var defaultTemplate = ""
    @State private var oldPw = ""
    @State private var newPw = ""
    @State private var newPw2 = ""
    @State private var newUser = ""
    @State private var userPw = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("分享页需要密码", isOn: $shareEnabled)
                if shareEnabled {
                    SecureField(sharePasswordSet ? "新密码（不改就留空）" : "设置分享密码（至少 4 位）", text: $sharePassword)
                }
                Button("保存") { Task { await post("/api/app/settings/share-password", ["enabled": shareEnabled, "password": sharePassword]) { sharePassword = ""; if shareEnabled { sharePasswordSet = true } } } }
            } header: { Text("分享密码") } footer: { Text("开启后，合租人打开验证码链接要先输这个密码（某个账号单独设了密码的，以账号的为准）。") }

            Section {
                TextEditor(text: $template).frame(minHeight: 110).font(.body.monospaced())
                Button("保存模板") { Task { await post("/api/app/settings/share-template", ["template": template]) {} } }
                Button("恢复默认") { template = defaultTemplate }
            } header: { Text("分享信息模板") } footer: { Text("「复制分享信息」按这个格式生成。可用 {分组} {账号} {密码} {链接}；账号没存密码时，带 {密码} 的那一行会自动去掉。") }

            Section {
                SecureField("原密码", text: $oldPw).textContentType(.password)
                SecureField("新密码（至少 12 位）", text: $newPw).textContentType(.newPassword)
                SecureField("再输一次新密码", text: $newPw2).textContentType(.newPassword)
                Button("修改管理员密码") {
                    guard newPw == newPw2 else { toast.show("两次输入的新密码不一样"); return }
                    Task { await post("/api/app/settings/admin-password", ["old": oldPw, "new": newPw]) { oldPw = ""; newPw = ""; newPw2 = ""; api.rememberCookies() } }
                }.disabled(oldPw.isEmpty || newPw.isEmpty)
            } header: { Text("管理员密码") } footer: { Text("改完后，其他设备上的登录（包括记住的设备）会全部退出，这台手机保持登录。") }

            Section {
                TextField("新用户名", text: $newUser).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("当前密码", text: $userPw)
                Button("修改用户名") { Task { await post("/api/app/settings/username", ["username": newUser, "password": userPw]) { username = newUser; userPw = "" } } }
                    .disabled(newUser.isEmpty || userPw.isEmpty)
            } header: { Text("管理员用户名（现在是 \(username)）") }

            if let error { Section { Text(error).foregroundStyle(Color.bad) } }
        }
        .navigationTitle("设置")
        .task {
            guard !loaded, let d = try? await api.get("/api/app/settings") else { return }
            username = d.str("username"); shareEnabled = d.bool("sharePasswordEnabled"); sharePasswordSet = d.bool("sharePasswordSet")
            template = d.str("shareTemplate"); defaultTemplate = d.str("defaultShareTemplate"); loaded = true
        }
    }

    private func post(_ path: String, _ body: JSON, then: () -> Void) async {
        do { let d = try await api.post(path, body); toast.show(d.str("message").isEmpty ? "已保存" : d.str("message")); error = nil; then() }
        catch { self.error = error.localizedDescription }
    }
}
