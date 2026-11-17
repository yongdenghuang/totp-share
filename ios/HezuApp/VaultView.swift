import SwiftUI

struct VaultType: Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var site: String
}

struct VaultExtra: Hashable {
    var label: String
    var value: String
    var secret: Bool
    var hasValue: Bool = false
}

struct VaultItem: Identifiable, Hashable {
    var id: Int
    var rev: Int
    var type: String
    var title: String
    var account: String
    var password: String          // 列表里没有，取完整内容后才有
    var hasPassword: Bool
    var phone: String
    var site: String
    var note: String
    var extras: [VaultExtra]
    var updated: String
    var deleted: String

    init(_ d: [String: Any]) {
        id = d.int("id"); rev = d.int("rev"); type = d.str("type"); title = d.str("title"); account = d.str("account")
        password = d.str("password"); hasPassword = d.bool("hasPassword") || !d.str("password").isEmpty
        phone = d.str("phone"); site = d.str("site"); note = d.str("note")
        extras = d.list("extras").map { VaultExtra(label: $0.str("label"), value: $0.str("value"), secret: $0.bool("secret"), hasValue: $0.bool("hasValue") || !$0.str("value").isEmpty) }
        updated = d.str("updated"); deleted = d.str("deleted")
    }

    init(type: String) {
        id = 0; rev = 0; self.type = type; title = ""; account = ""; password = ""; hasPassword = false
        phone = ""; site = ""; note = ""; extras = []; updated = ""; deleted = ""
    }

    var payload: [String: Any] {
        ["type": type, "title": title, "account": account, "password": password, "phone": phone, "site": site, "note": note,
         "extras": extras.filter { !$0.label.isEmpty || !$0.value.isEmpty }.map { ["label": $0.label, "value": $0.value, "secret": $0.secret] }]
    }
}

@MainActor
final class VaultStore: ObservableObject {
    var api: API!
    @Published var types: [VaultType] = []
    @Published var items: [VaultItem] = []
    @Published var trashCount = 0
    @Published var error: String?
    @Published var loaded = false
    private var full: [Int: (rev: Int, item: VaultItem, at: Date)] = [:]

    func load() async {
        do {
            let d = try await api.get("/admin/vault/api/items")
            types = d.list("types").map { VaultType(id: $0.str("id"), name: $0.str("name"), color: $0.str("color"), site: $0.str("site")) }
            items = d.list("entries").map(VaultItem.init)
            trashCount = d.int("trashCount")
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    func type(_ id: String) -> VaultType? { types.first { $0.id == id } }
    func color(_ id: String) -> Color { type(id).map { Color(hex: $0.color) } ?? .gray }

    /// 完整内容（含密码、保密的附加信息）。一分钟内取过的直接用，不再请求
    func reveal(_ it: VaultItem) async throws -> VaultItem {
        if let c = full[it.id], c.rev == it.rev, Date().timeIntervalSince(c.at) < 60 { return c.item }
        let d = try await api.post("/admin/vault/api/items/\(it.id)/reveal")
        let v = VaultItem(d.dict("entry"))
        full[it.id] = (v.rev, v, Date())
        return v
    }

    func save(_ it: VaultItem, force: Bool = false) async throws -> VaultItem {
        let d: [String: Any]
        if it.id == 0 {
            d = try await api.post("/admin/vault/api/items", ["data": it.payload])
        } else {
            d = try await api.put("/admin/vault/api/items/\(it.id)", ["rev": it.rev, "data": it.payload, "force": force])
        }
        let saved = VaultItem(d.dict("entry"))
        full[saved.id] = nil
        if let i = items.firstIndex(where: { $0.id == saved.id }) { items[i] = saved } else { items.append(saved) }
        return saved
    }

    func remove(_ it: VaultItem) async throws {
        _ = try await api.delete("/admin/vault/api/items/\(it.id)")
        items.removeAll { $0.id == it.id }
        trashCount += 1
    }

    func trash() async throws -> [VaultItem] {
        try await api.get("/admin/vault/api/items?trash=1").list("entries").map(VaultItem.init)
    }
    func restore(_ it: VaultItem) async throws {
        let d = try await api.post("/admin/vault/api/items/\(it.id)/restore")
        items.append(VaultItem(d.dict("entry"))); trashCount = max(0, trashCount - 1)
    }
    func purge(_ it: VaultItem) async throws {
        _ = try await api.delete("/admin/vault/api/items/\(it.id)?purge=1")
        trashCount = max(0, trashCount - 1)
    }

    func siteURL(_ it: VaultItem) -> URL? {
        var s = it.site.isEmpty ? (type(it.type)?.site ?? "") : it.site
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        return URL(string: s)
    }
}

// MARK: - 列表
struct VaultView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var toast: Toast
    @State private var query = ""
    @State private var typeFilter = ""
    @State private var editing: VaultItem?
    @State private var deleting: VaultItem?

    var body: some View {
        List {
            if !store.types.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("全部 \(store.items.count)", nil, typeFilter.isEmpty) { typeFilter = "" }
                            ForEach(store.types) { t in
                                let n = store.items.filter { $0.type == t.id }.count
                                chip(n > 0 ? "\(t.name) \(n)" : t.name, Color(hex: t.color), typeFilter == t.id) { typeFilter = typeFilter == t.id ? "" : t.id }
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 4)
                    }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            ForEach(sections, id: \.0) { (tid, list) in
                Section {
                    ForEach(list) { it in
                        NavigationLink(value: it) { VaultRow(item: it) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleting = it } label: { Label("删除", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                if it.hasPassword {
                                    Button { copyPassword(it) } label: { Label("复制密码", systemImage: "key") }.tint(.brand)
                                }
                            }
                            .contextMenu {
                                if !it.account.isEmpty { Button { toast.copy(it.account, "已复制账号") } label: { Label("复制账号", systemImage: "person") } }
                                if it.hasPassword { Button { copyPassword(it) } label: { Label("复制密码", systemImage: "key") } }
                                if !it.phone.isEmpty { Button { toast.copy(it.phone, "已复制手机号") } label: { Label("复制手机号", systemImage: "phone") } }
                                Button { editing = it } label: { Label("编辑", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = it } label: { Label("删除", systemImage: "trash") }
                            }
                    }
                } header: {
                    let t = store.type(tid)
                    HStack(spacing: 6) {
                        Circle().fill(store.color(tid)).frame(width: 8, height: 8)
                        Text(t?.name ?? "未分类"); Text("\(list.count)").foregroundStyle(.tertiary)
                    }
                }
            }
            if store.loaded && store.items.isEmpty && store.error == nil {
                VStack(spacing: 8) {
                    Image(systemName: "lock.rectangle.stack").font(.largeTitle).foregroundStyle(.secondary)
                    Text("还没有保存任何账号").font(.headline)
                    Text("Apple、Google、邮箱、电话卡、银行卡……都可以存在这里。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            if store.trashCount > 0 {
                Section { NavigationLink { VaultTrashView() } label: { Label("最近删除  \(store.trashCount)", systemImage: "trash") } }
            }
            if let e = store.error { ErrorBanner(message: e) { Task { await store.load() } } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("密码本")
        .navigationDestination(for: VaultItem.self) { VaultDetailView(itemID: $0.id) }
        .searchable(text: $query, prompt: "搜索账号、名称、备注")
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { editing = VaultItem(type: typeFilter.isEmpty ? (store.types.first?.id ?? "other") : typeFilter) } label: { Image(systemName: "plus") } }
            ToolbarItem(placement: .navigationBarLeading) { NavigationLink { VaultTypesView() } label: { Image(systemName: "tag") } }
        }
        .task { store.api = api; if !store.loaded { await store.load() } }
        .sheet(item: $editing) { VaultEditView(original: $0) }
        .confirmationDialog("删除「\(deleting?.title.isEmpty == false ? deleting!.title : deleting?.account ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let it = deleting { Task { do { try await store.remove(it); toast.show("已移到「最近删除」") } catch { toast.show(error.localizedDescription) } } } }
        } message: { Text("会移到「最近删除」，30 天内可以恢复。") }
    }

    private var sections: [(String, [VaultItem])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.items.filter { it in
            (typeFilter.isEmpty || it.type == typeFilter) && (q.isEmpty || [it.title, it.account, it.phone, it.note, it.site, store.type(it.type)?.name ?? ""]
                .joined(separator: "\n").lowercased().contains(q) || it.extras.contains { $0.label.lowercased().contains(q) || (!$0.secret && $0.value.lowercased().contains(q)) })
        }
        var order = store.types.map(\.id)
        let known = Set(order)
        if list.contains(where: { !known.contains($0.type) }) { order.append("") }
        return order.compactMap { tid in
            let l = list.filter { tid.isEmpty ? !known.contains($0.type) : $0.type == tid }
                .sorted { ($0.title, $0.account) < ($1.title, $1.account) }
            return l.isEmpty ? nil : (tid, l)
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

    private func copyPassword(_ it: VaultItem) {
        Task { do { toast.copy(try await store.reveal(it).password, "已复制密码") } catch { toast.show(error.localizedDescription) } }
    }
}

struct VaultRow: View {
    let item: VaultItem
    @EnvironmentObject var store: VaultStore
    var body: some View {
        HStack(spacing: 12) {
            let c = store.color(item.type)
            RoundedRectangle(cornerRadius: 9).fill(c.opacity(0.15)).frame(width: 36, height: 36)
                .overlay(Text(String((store.type(item.type)?.name ?? "·").prefix(1))).font(.headline).foregroundStyle(c))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? (item.account.isEmpty ? "未命名" : item.account) : item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(item.title.isEmpty ? (item.phone.isEmpty ? item.note : item.phone) : item.account)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 详情：每一行点一下复制
struct VaultDetailView: View {
    let itemID: Int
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var toast: Toast
    @Environment(\.openURL) private var openURL
    @State private var full: VaultItem?
    @State private var showPassword = false
    @State private var editing: VaultItem?
    @State private var error: String?

    private var item: VaultItem? { store.items.first { $0.id == itemID } }

    var body: some View {
        List {
            if let it = full ?? item {
                Section {
                    HStack(spacing: 14) {
                        let c = store.color(it.type)
                        RoundedRectangle(cornerRadius: 14).fill(c.opacity(0.15)).frame(width: 56, height: 56)
                            .overlay(Text(String((store.type(it.type)?.name ?? "·").prefix(1))).font(.title2.weight(.semibold)).foregroundStyle(c))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(it.title.isEmpty ? "未命名" : it.title).font(.title3.weight(.semibold))
                            Tag(text: store.type(it.type)?.name ?? "未分类", color: c)
                        }
                    }.padding(.vertical, 4)
                }
                Section {
                    copyRow("账号", it.account, mono: false)
                    if it.hasPassword {
                        Button { if let p = full?.password { toast.copy(p, "已复制密码") } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("密码").font(.caption).foregroundStyle(.secondary)
                                    Text(showPassword ? (full?.password ?? "") : "••••••••••").font(.body.monospaced()).foregroundStyle(.primary)
                                }
                                Spacer()
                                Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Color.brand) }.buttonStyle(.borderless)
                            }
                        }
                    }
                    copyRow("绑定手机", it.phone, mono: true)
                    if let url = store.siteURL(it) {
                        Button { openURL(url) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("官网").font(.caption).foregroundStyle(.secondary)
                                    Text(url.host ?? url.absoluteString).foregroundStyle(Color.brand)
                                }
                                Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(Color.brand)
                            }
                        }
                    }
                } footer: { Text("点一下复制") }
                let ex = (full ?? it).extras
                if !ex.isEmpty {
                    Section("附加信息") {
                        ForEach(Array(ex.enumerated()), id: \.offset) { _, x in
                            copyRow(x.label.isEmpty ? "附加信息" : x.label, x.value, mono: false, secret: x.secret && full == nil)
                        }
                    }
                }
                if !it.note.isEmpty {
                    Section("备注") {
                        Text(it.note).textSelection(.enabled)
                            .onTapGesture { toast.copy(it.note, "已复制备注") }
                    }
                }
                Section { Text("修改于 \(it.updated)").font(.footnote).foregroundStyle(.secondary) }
                    .tint(.brand)
            }
            if let error { ErrorBanner(message: error) }
        }
        .listStyle(.insetGrouped)
        .tint(.primary)                      // 列表里的按钮默认会染成主题色；这里的值要像系统「密码」App 一样是黑字
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("编辑") { if let it = full ?? item { editing = it } } } }
        .sheet(item: $editing, onDismiss: { Task { await loadFull() } }) { VaultEditView(original: $0) }
        .task { await loadFull() }
    }

    private func loadFull() async {
        guard let it = item else { return }
        do { full = try await store.reveal(it) } catch { self.error = error.localizedDescription }
    }

    @ViewBuilder
    private func copyRow(_ label: String, _ value: String, mono: Bool, secret: Bool = false) -> some View {
        if !value.isEmpty || secret {
            Button { if !secret { toast.copy(value, "已复制\(label)") } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(secret ? "••••" : value).font(mono ? .body.monospaced() : .body).foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - 添加 / 编辑
struct VaultEditView: View {
    let original: VaultItem
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @State private var it = VaultItem(type: "other")
    @State private var ready = false
    @State private var error: String?
    @State private var busy = false
    @State private var conflict = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $it.type) { ForEach(store.types) { Text($0.name).tag($0.id) } }
                    TextField("名称（比如：土区、主力号、移动主卡）", text: $it.title)
                }
                Section {
                    TextField("账号", text: $it.account).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    HStack {
                        TextField("密码（没有可以不填）", text: $it.password).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { it.password = randomPassword(16) } label: { Image(systemName: "dice") }.buttonStyle(.borderless)
                    }
                    TextField("绑定手机", text: $it.phone).keyboardType(.phonePad)
                    TextField(store.type(it.type)?.site.isEmpty == false ? "官网（不填用类型的官网）" : "官网网址", text: $it.site)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                Section {
                    ForEach($it.extras.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            TextField("名称（密保问题、生日、PIN…）", text: $it.extras[i].label).font(.subheadline)
                            TextField("内容", text: $it.extras[i].value)
                            Toggle("保密", isOn: $it.extras[i].secret).font(.subheadline)
                        }
                    }
                    .onDelete { it.extras.remove(atOffsets: $0) }
                    Button { it.extras.append(VaultExtra(label: "", value: "", secret: false)) } label: { Label("添加一项", systemImage: "plus.circle") }
                } header: { Text("附加信息") } footer: { Text("标了保密的，在列表和详情里显示成 ••••。左滑删除一项。") }
                Section("备注") { TextEditor(text: $it.note).frame(minHeight: 80) }
                if let error { Text(error).foregroundStyle(Color.bad) }
            }
            .navigationTitle(original.id == 0 ? "添加" : "编辑").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(force: false) }.disabled(busy || !ready) }
            }
            .alert("这一条刚在别处改过", isPresented: $conflict) {
                Button("取消", role: .cancel) {}
                Button("用我的覆盖", role: .destructive) { save(force: true) }
            } message: { Text("在别的设备上，这一条刚被修改过。要用你现在填的内容覆盖吗？") }
            .task {
                if original.id == 0 { it = original; ready = true; return }
                do { it = try await store.reveal(original); ready = true } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save(force: Bool) {
        busy = true; error = nil
        Task {
            do { _ = try await store.save(it, force: force); toast.show(original.id == 0 ? "已添加" : "已保存"); dismiss() }
            catch let e as APIError where e.code == 409 { conflict = true }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - 最近删除
struct VaultTrashView: View {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var toast: Toast
    @State private var list: [VaultItem] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                ForEach(list) { it in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.title.isEmpty ? (it.account.isEmpty ? "未命名" : it.account) : it.title).font(.body.weight(.medium))
                        Text("删除于 \(it.deleted)").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button { act { try await store.restore(it); toast.show("已恢复") } } label: { Label("恢复", systemImage: "arrow.uturn.backward") }.tint(.good)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { act { try await store.purge(it); toast.show("已彻底删除") } } label: { Label("彻底删除", systemImage: "trash") }
                    }
                }
            } footer: { Text(list.isEmpty && loaded ? "「最近删除」是空的。" : "右滑恢复，左滑彻底删除。删除的记录保留 30 天。") }
        }
        .navigationTitle("最近删除")
        .task { await reload() }
    }

    private func reload() async { list = (try? await store.trash()) ?? []; loaded = true }
    private func act(_ f: @escaping () async throws -> Void) {
        Task { do { try await f(); await reload() } catch { toast.show(error.localizedDescription) } }
    }
}

// MARK: - 类型管理
struct VaultTypesView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var toast: Toast
    @State private var types: [VaultType] = []
    @State private var rev = 0
    @State private var dirty = false

    var body: some View {
        List {
            Section {
                ForEach($types) { $t in
                    HStack {
                        ColorPicker("", selection: Binding(get: { Color(hex: t.color) }, set: { t.color = $0.hex; dirty = true }), supportsOpacity: false).labelsHidden()
                        VStack(alignment: .leading) {
                            TextField("类型名称", text: $t.name).onChange(of: t.name) { _ in dirty = true }
                            TextField("官网（可不填）", text: $t.site).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .onChange(of: t.site) { _ in dirty = true }
                        }
                    }
                }
                .onMove { types.move(fromOffsets: $0, toOffset: $1); dirty = true }
                .onDelete { idx in
                    let used = idx.contains { i in store.items.contains { $0.type == types[i].id } }
                    if used { toast.show("这个类型下还有记录，不能删") } else { types.remove(atOffsets: idx); dirty = true }
                }
                Button { types.append(VaultType(id: "t" + String(Int(Date().timeIntervalSince1970), radix: 36), name: "新类型", color: "#4f46e5", site: "")); dirty = true } label: { Label("新类型", systemImage: "plus.circle") }
            } footer: { Text("拖动调整顺序，左滑删除。类型的官网会给没单独填官网的记录用。") }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("类型管理")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!dirty) } }
        .task { types = store.types; rev = (try? await api.get("/admin/vault/api/items").int("typesRev")) ?? 0 }
    }

    private func save() {
        Task {
            do {
                let d = try await api.put("/admin/vault/api/types", ["rev": rev, "types": types.map { ["id": $0.id, "name": $0.name, "color": $0.color, "site": $0.site] }])
                rev = d.int("typesRev"); dirty = false
                await store.load(); toast.show("类型已保存")
            } catch { toast.show(error.localizedDescription) }
        }
    }
}

extension Color {
    var hex: String {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
