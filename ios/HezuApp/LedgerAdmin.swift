import SwiftUI
import UniformTypeIdentifiers

// MARK: - 表的增删改（和网页 sheetForm / convertSheetMode / sheetMenu 一样）
extension Dictionary where Key == String, Value == Any {
    mutating func addSheet(id: String, name: String, mode: String) {
        editList("sheets") { l in if !l.contains(where: { $0.str("id") == id }) { l.append(["id": id, "name": name, "mode": mode]) } }
        var months = dict("months")
        for (ym, mv) in months { guard var M = mv as? JSON else { continue }; var rows = M.dict("rows"); if rows[id] == nil { rows[id] = [JSON]() }; M["rows"] = rows; months[ym] = M }
        self["months"] = months
    }
    /// 改名 / 换收费方式。换方式时把还在进行的月份换算过去（存档月份保持原样）
    mutating func updateSheet(id: String, name: String, mode to: String) {
        var sheets = list("sheets")
        guard let i = sheets.firstIndex(where: { $0.str("id") == id }) else { return }
        let from = sheets[i].str("mode")
        sheets[i]["name"] = name
        if from != to {
            var months = dict("months")
            for (ym, mv) in months {
                guard var M = mv as? JSON, !M.bool("archived") else { continue }
                var rows = M.dict("rows")
                rows[id] = rows.list(id).map { r -> JSON in
                    var r = r
                    if to == "resale" {
                        if from == "members" {
                            let ms = r.list("members")
                            r["unitPrice"] = ms.isEmpty ? 0.0 : ms.reduce(0) { $0 + num($1["amount"]) } / Double(ms.count)
                            r["count"] = Double(ms.count)
                        }
                        r["unitCost"] = num(r["count"]) != 0 ? ((num(r["cost"]) / num(r["count"])) * 100).rounded() / 100 : num(r["cost"])
                    } else if from == "resale" {
                        r["cost"] = ((num(r["unitCost"]) * num(r["count"])) * 100).rounded() / 100
                    }
                    return r
                }
                M["rows"] = rows; months[ym] = M
            }
            self["months"] = months
            sheets[i]["mode"] = to
        }
        self["sheets"] = sheets
    }
    mutating func deleteSheet(id: String) {
        editList("sheets") { $0.removeAll { $0.str("id") == id } }
        var months = dict("months")
        for (ym, mv) in months { guard var M = mv as? JSON else { continue }; var rows = M.dict("rows"); rows[id] = nil; M["rows"] = rows; months[ym] = M }
        self["months"] = months
    }
    mutating func reorderSheets(_ ids: [String]) {
        let pos: [String: Int] = [String: Int](uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        editList("sheets") { l in l.sort { (pos[$0.str("id")] ?? 9999) < (pos[$1.str("id")] ?? 9999) } }
    }
    /// 删除最新的月份，上一个月恢复成进行中（网页 deleteLatestMonth）
    mutating func deleteLatestMonth() {
        var months = dict("months")
        let keys = months.keys.sorted()
        guard keys.count > 1, let last = keys.last else { return }
        months[last] = nil
        var prev = months.dict(keys[keys.count - 2]); prev["archived"] = false; months[keys[keys.count - 2]] = prev
        self["months"] = months
    }
}

let modeNames: [(String, String)] = [("unit", "单价 × 人数（每人价格一样）"), ("members", "每人单独填金额"), ("resale", "代充（售价、成本固定，只填数量）"), ("accounts", "只存账号（账号、密码、验证码，不算钱）")]

/// 新建 / 修改一张表
struct SheetForm: View {
    let sheetID: String          // "" = 新建
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mode = "unit"
    @State private var confirmDelete = false
    @State private var groupsEdit: [EditGroup] = []
    @State private var groupError: String?
    var onDeleted: (() -> Void)?
    private var grouped: Bool { ledger.sheet(sheetID)?.bool("grouped") ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("名称，如 YouTube", text: $name) }
                Section {
                    Picker("收费方式", selection: $mode) { ForEach(modeNames, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.inline).labelsHidden()
                } header: { Text("收费方式") } footer: {
                    if !sheetID.isEmpty && mode != ledger.sheet(sheetID)?.str("mode") {
                        Text("换方式时会把进行中月份的数据换算过去（存档月份不变）：换成代充时成本/份 = 续费成本 ÷ 数量；从代充换回时续费成本 = 成本/份 × 数量。")
                    }
                }
                if grouped {
                    Section {
                        ForEach($groupsEdit) { $g in
                            HStack(spacing: 12) {
                                Menu {
                                    ForEach(groupPalette, id: \.0) { c in Button(c.1) { g.color = c.0 } }
                                } label: { Circle().fill(Color(hex: g.color)).frame(width: 20, height: 20) }
                                TextField("分组名称", text: $g.name)
                            }
                        }
                        .onDelete { groupsEdit.remove(atOffsets: $0) }
                        .onMove { groupsEdit.move(fromOffsets: $0, toOffset: $1) }
                        Button { groupsEdit.append(EditGroup(id: "g_" + uid(), name: "", color: groupPalette[groupsEdit.count % groupPalette.count].0)) } label: { Label("新建分组", systemImage: "plus") }
                    } header: {
                        HStack { Text("分组"); Spacer(); EditButton().font(.caption) }
                    } footer: {
                        Text(groupError ?? "只是这张表自己的分组，账号验证码的分组不受影响。点圆点换颜色，左滑删除，点「编辑」拖动排序。删掉的分组里的账号放到「未分组」，账号不会删。")
                            .foregroundStyle(groupError == nil ? Color.secondary : Color.bad)
                    }
                }
                if !sheetID.isEmpty && !grouped {
                    Section { Button("删除这张表", role: .destructive) { confirmDelete = true } } footer: { Text("它在所有月份里的账号都会一起删除，不能恢复。") }
                }
            }
            .navigationTitle(sheetID.isEmpty ? "新建表" : "表设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sheetID.isEmpty ? "新建" : "保存") {
                        let n = name.trimmingCharacters(in: .whitespaces), m = mode, id = sheetID.isEmpty ? "s_" + uid() : sheetID
                        let g = grouped
                        let gs: [JSON] = groupsEdit.map { ["id": $0.id, "name": $0.name.trimmingCharacters(in: .whitespaces), "color": $0.color, "text": textOn($0.color)] }
                        if g {
                            let names = gs.map { normName($0.str("name")) }
                            if names.contains(where: \.isEmpty) { groupError = "分组名称不能是空的。"; return }
                            if Set(names).count != names.count { groupError = "有两个分组同名了。"; return }
                        }
                        if sheetID.isEmpty { ledger.edit { $0.addSheet(id: id, name: n, mode: m) } } else { ledger.edit { $0.updateSheet(id: id, name: n, mode: m); if g { $0.setSheetGroups(id: id, groups: gs) } } }
                        toast.show("已保存"); dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("删除「\(name)」？", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { let id = sheetID; ledger.edit { $0.deleteSheet(id: id) }; toast.show("已删除"); dismiss(); onDeleted?() }
            } message: { Text("这张表在所有月份里的账号都会一起删除，不能恢复。") }
            .onAppear { if let s = ledger.sheet(sheetID) { name = s.str("name"); mode = s.str("mode"); groupsEdit = ledger.sheetGroups(s).map { EditGroup(id: $0.id, name: $0.name, color: $0.color) } } }
        }
    }
}

/// 表的顺序（拖动）+ 新建
struct SheetsManager: View {
    @EnvironmentObject var ledger: LedgerStore
    @State private var editing: String?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(ledger.sheetInfo) { s in
                    Button { if !s.grouped { editing = s.id } else { editing = s.id } } label: {
                        HStack {
                            Text(s.name).foregroundStyle(.primary)
                            Spacer()
                            Text(modeNames.first { $0.0 == s.mode }.map { String($0.1.prefix(while: { $0 != "（" })) } ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { from, to in
                    var ids = ledger.sheetInfo.map(\.id); ids.move(fromOffsets: from, toOffset: to)
                    let order = ids
                    ledger.edit { $0.reorderSheets(order) }
                    Task { await ledger.navApplySheetOrder(order) }   // 左栏里各板块的表也按这个顺序
                }
                Button { creating = true } label: { Label("新建表", systemImage: "plus.circle") }
            } footer: { Text("拖动右边的三条线调整顺序（网页左侧导航也跟着变），点一下改名或换收费方式。") }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("表设置")
        .sheet(item: Binding(get: { editing.map { IDBox(id: $0) } }, set: { editing = $0?.id })) { SheetForm(sheetID: $0.id) }
        .sheet(isPresented: $creating) { SheetForm(sheetID: "") }
    }
}

struct IDBox: Identifiable { let id: String }

// MARK: - 导入导出、备份、历史版本
struct LedgerDataView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @State private var exportYearly = false
    @State private var exportMonth = ""
    @State private var exportYear = ""
    @State private var busy = false
    @State private var shareFile: ShareFile?
    @State private var importingJSON = false
    @State private var pendingRestore: JSON?
    @State private var history: [(day: String, saved: String)] = []
    @State private var restoreDay: String?
    @State private var confirmDeleteMonth = false
    @State private var webImport = false

    private var years: [String] { Array(Set(ledger.monthKeys.map { String($0.prefix(4)) })).sorted(by: >) }

    var body: some View {
        Form {
            Section {
                Picker("范围", selection: $exportYearly) { Text("按月").tag(false); Text("按年").tag(true) }.pickerStyle(.segmented)
                if exportYearly {
                    Picker("年份", selection: $exportYear) { ForEach(years, id: \.self) { y in Text("\(y) 年（\(ledger.monthKeys.filter { $0.hasPrefix(y) }.count) 个月）").tag(y) } }
                } else {
                    Picker("月份", selection: $exportMonth) { ForEach(ledger.monthKeys.reversed(), id: \.self) { Text(ymLabel($0)).tag($0) } }
                }
                Button { Task { await exportExcel() } } label: { HStack { Label("导出 Excel", systemImage: "tablecells"); Spacer(); if busy { ProgressView() } } }.disabled(busy)
            } header: { Text("导出 Excel") } footer: { Text("按年导出会多一张「年度汇总」。文件里的卡号、有效期、CVC 和 VPS 密码是完整的，注意保管。") }

            Section {
                Button { exportJSON() } label: { Label("导出数据备份（JSON）", systemImage: "square.and.arrow.up") }
                Button { importingJSON = true } label: { Label("从 JSON 备份恢复…", systemImage: "square.and.arrow.down") }
                Button { webImport = true } label: { Label("导入原来的 Excel（网页）…", systemImage: "doc.badge.plus") }
            } header: { Text("备份") } footer: { Text("恢复会整体替换现在的账本；现在的内容会留在「历史版本」里。") }

            Section {
                if history.isEmpty { Text("还没有历史版本").foregroundStyle(.secondary) }
                ForEach(history, id: \.day) { h in
                    Button { restoreDay = h.day } label: {
                        HStack { Text("\(h.day) 开始前的版本").foregroundStyle(.primary); Spacer(); Text("存于 \(h.saved)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } header: { Text("恢复到某天的版本") } footer: { Text("每天第一次保存前，系统会自动把上一版留一份，保留 60 天。") }

            if ledger.monthKeys.count > 1 {
                Section {
                    Button("删除 \(ymLabel(ledger.latestMonth))", role: .destructive) { confirmDeleteMonth = true }
                } footer: { Text("删除最新月份的全部数据，\(ymLabel(ledger.monthKeys[ledger.monthKeys.count - 2])) 会恢复成进行中。") }
            }
        }
        .navigationTitle("导入导出")
        .task {
            exportMonth = ledger.latestMonth; exportYear = years.first ?? ""
            if let d = try? await api.get("/admin/hezu/api/history") { history = d.list("days").map { ($0.str("day"), $0.str("savedAt")) } }
        }
        .sheet(item: $shareFile) { f in ShareSheet(url: f.url) }
        .sheet(isPresented: $webImport, onDismiss: { Task { await ledger.load() } }) {
            NavigationStack {
                EmbeddedWeb(path: "/admin/hezu#home").ignoresSafeArea(edges: .bottom)
                    .navigationTitle("导入 Excel").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { webImport = false } } }
                    .safeAreaInset(edge: .top) { Text("在下面网页的「更多 → 导入 Excel」里选择文件").font(.footnote).foregroundStyle(.secondary).padding(8) }
            }
        }
        .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { r in loadBackup(r) }
        .alert("用这份备份替换现在的账本？", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button("取消", role: .cancel) {}
            Button("替换", role: .destructive) { if let s = pendingRestore { Task { await restore(s) } } }
        } message: { Text("备份里有 \(pendingRestore?.dict("months").count ?? 0) 个月的数据。现在的内容会留在「历史版本」里，保留 60 天。") }
        .alert("恢复到 \(restoreDay ?? "") 开始前的版本？", isPresented: Binding(get: { restoreDay != nil }, set: { if !$0 { restoreDay = nil } })) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { if let d = restoreDay { Task { await restoreHistory(d) } } }
        } message: { Text("会整体替换现在的账本（所有月份、支付卡、VPS）。今天第一次恢复或保存前的状态同样会留一份。") }
        .alert("删除 \(ymLabel(ledger.latestMonth))？", isPresented: $confirmDeleteMonth) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { ledger.edit { $0.deleteLatestMonth() }; toast.show("已删除") }
        } message: { Text("这个月的全部数据会删除，不能恢复。") }
    }

    private func exportExcel() async {
        busy = true; defer { busy = false }
        let q = exportYearly ? "year=\(exportYear)" : "month=\(exportMonth)"
        do {
            var req = URLRequest(url: api.url("/admin/hezu/api/export?\(q)"))
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.server("导出失败，请刷新后再试", 0, [:]) }
            let name = exportYearly ? "合租管理-\(exportYear)年.xlsx" : "合租管理-\(ymLabel(exportMonth).replacingOccurrences(of: " ", with: "")).xlsx"
            shareFile = ShareFile(url: try writeTemp(data, name))
        } catch { toast.show(error.localizedDescription) }
    }

    private func exportJSON() {
        var s = ledger.S
        s["groups"] = ledger.groups.map { ["id": $0.id, "name": $0.name] }
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted]) else { return }
        if let u = try? writeTemp(data, "hezu-backup-\(isoDate(Date())).json") { shareFile = ShareFile(url: u) }
    }

    private func loadBackup(_ r: Result<URL, Error>) {
        guard case .success(let url) = r else { return }
        let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let s = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              s["months"] is JSON, s["sheets"] is [Any] else { toast.show("这不是合租账本的备份文件"); return }
        pendingRestore = s
    }

    private func restore(_ s: JSON) async {
        do { _ = try await api.post("/admin/hezu/api/restore", ["state": s]); await ledger.load(); toast.show("已恢复") }
        catch { toast.show(error.localizedDescription) }
    }

    private func restoreHistory(_ day: String) async {
        do { _ = try await api.post("/admin/hezu/api/history/\(day)/restore"); await ledger.load(); toast.show("已恢复到 \(day) 的版本") }
        catch { toast.show(error.localizedDescription) }
    }
}

struct ShareFile: Identifiable { let id = UUID(); let url: URL }

func writeTemp(_ data: Data, _ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let u = dir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: u)
    try data.write(to: u, options: .completeFileProtection)
    return u
}

/// 系统分享面板（存到「文件」、发给别人……）
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct EditGroup: Identifiable { let id: String; var name: String; var color: String }
let groupPalette: [(String, String)] = [("#3b82f6", "蓝"), ("#22c55e", "绿"), ("#f97316", "橙"), ("#8b5cf6", "紫"), ("#ec4899", "粉"),
                                        ("#14b8a6", "青"), ("#eab308", "黄"), ("#ef4444", "红"), ("#64748b", "灰"), ("#0ea5e9", "天蓝")]
/// 底色上用白字还是深色字（和服务器 text_color_on 一样）
func textOn(_ hex: String) -> String {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 6, let v = Int(h, radix: 16) else { return "#ffffff" }
    let r = Double(v >> 16), g = Double((v >> 8) & 255), b = Double(v & 255)
    return 0.299 * r + 0.587 * g + 0.114 * b > 160 ? "#1f2937" : "#ffffff"
}
