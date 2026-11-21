import SwiftUI

/// 首页 / 更多 进来的账本页面
struct LedgerDestination: View {
    let route: LedgerRoute
    var body: some View {
        switch route {
        case .sheet(let id): LedgerSheetView(sheetID: id)
        case .cards: CardsView()
        case .vps: VPSView()
        }
    }
}

/// 一张表（AI 合租、Netflix、代充……）某个月的全部账号
struct LedgerSheetView: View {
    let sheetID: String
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var toast: Toast
    @State private var ym = ""
    @State private var unlocked: Set<String> = []
    @State private var query = ""
    @State private var groupFilter: String?          // nil = 全部，"" = 未分组
    @State private var editing: RowRef?
    @State private var confirmArchive = false
    @State private var deleting: JSON?
    @State private var sheetSettings = false
    @Environment(\.dismiss) private var dismissView

    private var sheet: JSON { ledger.sheet(sheetID) ?? [:] }
    private var mode: String { sheet.str("mode") }
    private var grouped: Bool { sheet.bool("grouped") }
    private var month: String { ym.isEmpty ? ledger.latestMonth : ym }
    private var editable: Bool { !ledger.isArchived(month) || unlocked.contains(month) }
    private var allRows: [JSON] { ledger.rows(month, sheetID) }
    /// 和首页方块同一个颜色
    private var sheetTint: Color { tileColors("sheet:" + sheetID, ledger)[1] }

    var body: some View {
        List {
            if mode != "accounts" { Section { summary }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if ledger.isArchived(month) {
                Section {
                    HStack {
                        Image(systemName: unlocked.contains(month) ? "lock.open" : "archivebox").foregroundStyle(Color.warn)
                        Text(unlocked.contains(month) ? "存档已临时解锁，可以修改" : "\(ymLabel(month)) 是存档，只能看").font(.subheadline)
                        Spacer()
                        Button(unlocked.contains(month) ? "重新锁定" : "解锁修改") {
                            if unlocked.contains(month) { unlocked.remove(month) } else { unlocked.insert(month) }
                        }.font(.subheadline.weight(.semibold))
                    }
                }
            }
            if grouped { Section { groupChips }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            ForEach(sections, id: \.key) { sec in
                Section {
                    ForEach(sec.rows, id: \.idKey) { r in
                        LedgerRowView(row: r, mode: mode, editable: editable, month: month, sheetID: sheetID)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = RowRef(id: r.str("id"), preset: "") }
                            .swipeActions(edge: .trailing) {
                                if editable {
                                    Button(role: .destructive) { deleting = r } label: { Label("删除", systemImage: "trash") }
                                    if mode != "resale" && parseISO(r.str("renew")) != nil {
                                        Button { renewed(r) } label: { Label("已续费", systemImage: "calendar.badge.plus") }.tint(.good)
                                    }
                                }
                            }
                            .contextMenu { rowMenu(r) }
                            .tintedRow(r.bool("stopped") ? .gray : (sec.color ?? sheetTint))
                    }
                    if editable {
                        Button { editing = RowRef(id: "", preset: sec.groupID ?? "") } label: {
                            Label(mode == "resale" ? "添加项目" : "添加账号", systemImage: "plus.circle")
                        }
                        .tintedRow(sec.color ?? sheetTint, bar: false)
                    }
                } header: { sectionHeader(sec) }
            }
            if sections.isEmpty && ledger.loaded {
                Section {
                    Text(query.isEmpty ? (mode == "resale" ? "这个月还没有代充项目。" : "这个月还没有账号。") : "没有找到「\(query)」").foregroundStyle(.secondary)
                    if editable && query.isEmpty {
                        Button { editing = RowRef(id: "", preset: "") } label: { Label(mode == "resale" ? "添加项目" : "添加账号", systemImage: "plus.circle") }
                    }
                }
            }
            if let e = ledger.error { ErrorBanner(message: e) { Task { await ledger.load() } } }
        }
        .listStyle(.insetGrouped)
        .moduleBackground(sheetTint)
        .navigationTitle(sheet.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索账号、备注、卡种")
        .refreshable { await ledger.load(); await codes.refreshCodes() }
        .toolbar {
            ToolbarItem(placement: .principal) { monthMenu }
            ToolbarItemGroup(placement: .primaryAction) {
                if editable { Button { editing = RowRef(id: "", preset: groupFilter ?? "") } label: { Image(systemName: "plus") } }
                Menu {
                    if month == ledger.latestMonth && !ledger.isArchived(month) {
                        Button { confirmArchive = true } label: { Label("归档并开始 \(ymLabel(nextYM(month)))", systemImage: "archivebox") }
                    }
                    if mode == "members" && editable {
                        Button { markAllPaid() } label: { Label("本页全部标记已收", systemImage: "checkmark.circle") }
                    }
                    Divider()
                    Button { sheetSettings = true } label: { Label("表设置（改名、收费方式）", systemImage: "slider.horizontal.3") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editing) { ref in
            RowEditor(sheetID: sheetID, ym: month, rowID: ref.id, presetGroup: ref.preset, editable: editable)
        }
        .sheet(isPresented: $sheetSettings) { SheetForm(sheetID: sheetID, onDeleted: { dismissView() }) }
        .alert("归档并开始 \(ymLabel(nextYM(month)))？", isPresented: $confirmArchive) {
            Button("取消", role: .cancel) {}
            Button("归档并开始") { ledger.edit { $0.startNextMonth() }; ym = ""; toast.show("已开始 \(ymLabel(nextYM(month)))") }
        } message: {
            Text("账号、收费、成本和续费卡会复制到新月份；续费日期早于新月份的顺延；收款状态重置为未收，代充单数清零；标记停止的不带过去。\(ymLabel(month)) 变成只读存档。")
        }
        .confirmationDialog("删除「\(deleting?.str("account").isEmpty == false ? deleting!.str("account") : "这一行")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let r = deleting { delete(r) } }
        } message: { Text("只影响 \(ymLabel(month))，其他月份不变。") }
        .task {
            ledger.api = api; codes.api = api
            if !ledger.loaded { await ledger.load() }
            if !codes.loaded { await codes.load() }
        }
    }

    // MARK: 顶部
    private var monthMenu: some View {
        Menu {
            ForEach(ledger.monthKeys.reversed(), id: \.self) { k in
                Button { ym = k == ledger.latestMonth ? "" : k } label: {
                    if k == month { Label(ymLabel(k) + (ledger.isArchived(k) ? "（存档）" : ""), systemImage: "checkmark") }
                    else { Text(ymLabel(k) + (ledger.isArchived(k) ? "（存档）" : "")) }
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text(sheet.str("name")).font(.headline)
                HStack(spacing: 3) { Text(ymLabel(month)); Image(systemName: "chevron.down").imageScale(.small) }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    private var summary: some View {
        let s = Calc.stats(mode, allRows)
        return HStack(spacing: 10) {
            statBox("收费", money(s.income), nil)
            statBox(mode == "resale" ? "成本" : "续费成本", money(s.cost), nil)
            statBox("利润", money(s.profit), s.profit >= 0 ? Color.good : Color.bad,
                    sub: s.income > 0 ? "利润率 \(Int((s.profit / s.income * 100).rounded()))%" : nil)
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    private func statBox(_ k: String, _ v: String, _ c: Color?, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.caption).foregroundStyle(c ?? .secondary)
            Text(v).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(c ?? .primary).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub ?? " ").font(.caption2).foregroundStyle(c ?? .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background((c ?? Color(.secondarySystemGroupedBackground)).opacity(c == nil ? 1 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部 \(allRows.count)", nil, groupFilter == nil) { groupFilter = nil }
                ForEach(ledger.visibleGroups) { g in
                    let n = allRows.filter { $0.str("group") == g.id }.count
                    chip(n > 0 ? "\(g.name) \(n)" : g.name, Color(hex: g.color), groupFilter == g.id) { groupFilter = groupFilter == g.id ? nil : g.id }
                }
                let loose = allRows.filter { r in !ledger.groups.contains { $0.id == r.str("group") } }.count
                if loose > 0 { chip("未分组 \(loose)", .gray, groupFilter == "") { groupFilter = groupFilter == "" ? nil : "" } }
            }.padding(.horizontal, 16).padding(.vertical, 4)
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

    // MARK: 分组
    struct Sec { let key: String; let title: String; let color: Color?; let groupID: String?; let rows: [JSON] }

    private var sections: [Sec] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = allRows.filter { r in
            q.isEmpty || [r.str("account"), r.str("note"), ledger.issuer(r.str("issuerId"))?.str("name") ?? "", r.list("members").map { $0.str("name") }.joined(separator: " ")]
                .joined(separator: " ").lowercased().contains(q)
        }
        guard grouped else { return list.isEmpty ? [] : [Sec(key: "all", title: sheet.str("name"), color: nil, groupID: nil, rows: list)] }
        var out: [Sec] = []
        for g in ledger.visibleGroups where groupFilter == nil || groupFilter == g.id {
            let l = list.filter { $0.str("group") == g.id }
            if !l.isEmpty || groupFilter == g.id { out.append(Sec(key: g.id, title: g.name, color: Color(hex: g.color), groupID: g.id, rows: l)) }
        }
        if groupFilter == nil || groupFilter == "" {
            let ids = Set(ledger.groups.map(\.id))
            let l = list.filter { !ids.contains($0.str("group")) }
            if !l.isEmpty { out.append(Sec(key: "loose", title: "未分组", color: .gray, groupID: "", rows: l)) }
        }
        return out
    }

    private func sectionHeader(_ sec: Sec) -> some View {
        let s = Calc.stats(mode, sec.rows)
        return HStack(spacing: 6) {
            if let c = sec.color { Circle().fill(c).frame(width: 8, height: 8) }
            Text(sec.title)
            Text(mode == "accounts" ? "\(sec.rows.count) 个账号" : mode == "resale" ? "\(sec.rows.count) 项 · \(plainNum(s.heads)) 单" : "\(sec.rows.count) 个 · \(plainNum(s.heads)) 人").foregroundStyle(.tertiary)
            Spacer()
            if mode != "accounts" { Text(money(s.profit)).foregroundStyle(s.profit >= 0 ? Color.good : Color.bad).fontWeight(.semibold) }
        }
        .textCase(nil)
    }

    // MARK: 操作
    @ViewBuilder
    private func rowMenu(_ r: JSON) -> some View {
        let id = r.str("id")
        if !r.str("account").isEmpty { Button { toast.copy(r.str("account"), "已复制账号") } label: { Label("复制账号", systemImage: "doc.on.doc") } }
        if let a = ledger.totpAccount(r.int("totpId")) {
            if let c = codes.codes[a.id] { Button { toast.copy(c, "已复制验证码") } label: { Label("复制验证码", systemImage: "number") } }
            if a.hasPassword { Button { copyTotpPassword(a.id) } label: { Label("复制账号密码", systemImage: "key") } }
            Button { copyShare(a.id) } label: { Label("复制分享信息", systemImage: "text.bubble") }
        } else if !r.str("password").isEmpty {
            Button { toast.copy(r.str("password"), "已复制密码") } label: { Label("复制账号密码", systemImage: "key") }
        }
        if editable {
            Divider()
            Button { editing = RowRef(id: id, preset: "") } label: { Label("编辑", systemImage: "pencil") }
            if grouped {
                Menu {
                    ForEach(ledger.groups) { g in Button(g.name) { move(r, to: g.id) } }
                    Button("未分组") { move(r, to: "") }
                } label: { Label("移到分组", systemImage: "folder") }
            }
            if mode != "resale" && parseISO(r.str("renew")) != nil { Button { renewed(r) } label: { Label("续费日期顺延一个月", systemImage: "calendar.badge.plus") } }
            if mode == "members" && r.list("members").contains(where: { !$0.bool("paid") }) {
                Button { ledger.edit { $0.updateRow(month, sheetID, id) { $0["members"] = $0.list("members").map { var m = $0; m["paid"] = true; return m } } } } label: { Label("全部标记已收", systemImage: "checkmark.circle") }
            }
            Button { let v = !r.bool("stopped"); ledger.edit { $0.updateRow(month, sheetID, id) { $0["stopped"] = v } } } label: {
                Label(r.bool("stopped") ? "恢复使用" : "标记为停止（下月不带入）", systemImage: r.bool("stopped") ? "play.circle" : "pause.circle")
            }
            Divider()
            Button(role: .destructive) { deleting = r } label: { Label("删除这一行", systemImage: "trash") }
        }
    }

    private func renewed(_ r: JSON) {
        let id = r.str("id")
        ledger.edit { s in s.updateRow(month, sheetID, id) { row in row["renew"] = shiftMonth(row.str("renew"), 1) } }
        toast.show("续费日期已顺延到 \(shiftMonth(r.str("renew"), 1))")
    }

    private func delete(_ r: JSON) {
        let id = r.str("id"), tid = r.int("totpId"), latest = month == ledger.latestMonth
        ledger.edit { s in s.removeRow(month, sheetID, id); if tid > 0 && latest { s.skipTotp(tid) } }
        toast.show("已删除")
    }

    private func move(_ r: JSON, to gid: String) {
        let id = r.str("id")
        ledger.edit { $0.updateRow(month, sheetID, id) { $0["group"] = gid } }
        if let a = ledger.totpAccount(r.int("totpId")), !ledger.isArchived(month) {
            let name = ledger.group(gid)?.name ?? ""
            Task { _ = try? await api.post("/admin/accounts/\(a.id)/field", ["field": "group_name", "value": name]); await codes.load() }
        }
    }

    private func markAllPaid() {
        let ids = sections.flatMap { $0.rows.map { $0.str("id") } }
        ledger.edit { s in for id in ids { s.updateRow(month, sheetID, id) { $0["members"] = $0.list("members").map { var m = $0; m["paid"] = true; return m } } } }
        toast.show("已全部标记已收")
    }

    private func copyTotpPassword(_ id: Int) {
        Task { do { toast.copy(try await api.post("/admin/accounts/\(id)/password/reveal").str("password"), "已复制密码") } catch { toast.show(error.localizedDescription) } }
    }
    private func copyShare(_ id: Int) {
        Task { do { toast.copy(try await api.post("/admin/accounts/\(id)/share-text").str("text"), "已复制分享信息") } catch { toast.show(error.localizedDescription) } }
    }
}

struct RowRef: Identifiable { var id: String; var preset: String; var key: String { id.isEmpty ? "new-\(preset)" : id } }
extension RowRef { var identity: String { key } }

extension Dictionary where Key == String, Value == Any {
    var idKey: String { str("id") }
}

/// 列表里的一行
struct LedgerRowView: View {
    let row: JSON
    let mode: String
    let editable: Bool
    let month: String
    let sheetID: String
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var toast: Toast

    var body: some View {
        let inc = Calc.income(mode, row), cost = Calc.cost(mode, row), profit = inc - cost
        let stopped = row.bool("stopped")
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.str("account").isEmpty ? (mode == "resale" ? "未命名项目" : "未填账号") : row.str("account"))
                    .font(.body.weight(.semibold)).lineLimit(1).strikethrough(stopped).foregroundStyle(stopped ? .secondary : .primary)
                if let a = ledger.totpAccount(row.int("totpId")), let c = codes.codes[a.id] {
                    Button { toast.copy(c, "已复制验证码") } label: {
                        Text(c.prefix(3) + " " + c.dropFirst(3)).font(.system(.caption, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.brand.opacity(0.1), in: Capsule()).foregroundStyle(Color.brand)
                    }.buttonStyle(.borderless)
                }
                Spacer(minLength: 4)
                if mode != "accounts" {
                    Text(money(profit)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background((profit >= 0 ? Color.good : Color.bad).opacity(0.12), in: Capsule())
                        .foregroundStyle(profit >= 0 ? Color.good : Color.bad)
                }
            }
            if mode == "accounts" { accountChips }
            HStack(spacing: 8) {
                if mode != "resale", let d = daysUntil(row.str("renew")) {
                    let soon = d <= 3 && !stopped && !ledger.isArchived(month)
                    Label(relText(d), systemImage: "calendar").labelStyle(.titleAndIcon)
                        .foregroundStyle(d < 0 && soon ? Color.bad : soon ? Color.warn : .secondary)
                }
                if let it = ledger.issuer(row.str("issuerId")) {
                    let c = ledger.card(row.str("cardId"))
                    Label(it.str("name") + (c != nil ? " " + Calc.cardLabel(c) : ""), systemImage: "creditcard").lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if stopped { Text("已停止").foregroundStyle(Color.warn) }
            }
            .font(.caption)
            if mode != "accounts" { charge(inc: inc, cost: cost) }
            if !row.str("note").isEmpty { Text(row.str("note")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func charge(inc: Double, cost: Double) -> some View {
        switch mode {
        case "members":
            let ms = row.list("members")
            if ms.isEmpty {
                Text("还没填收费 · 成本 \(money(cost))").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(ms.enumerated()), id: \.offset) { i, m in
                            Button { togglePaid(i) } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: m.bool("paid") ? "checkmark.circle.fill" : "circle").imageScale(.small)
                                    if !m.str("name").isEmpty { Text(m.str("name")).foregroundStyle(.secondary) }
                                    Text(plainNum(num(m["amount"]))).fontWeight(.semibold)
                                }
                                .font(.caption)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(m.bool("paid") ? Color.good.opacity(0.13) : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(m.bool("paid") ? Color.good : .primary)
                            }.buttonStyle(.borderless).disabled(!editable)
                        }
                        Text("= \(money(inc)) · 成本 \(money(cost))").font(.caption).foregroundStyle(.secondary).padding(.leading, 2)
                    }
                }
            }
        case "resale":
            HStack(spacing: 10) {
                Text("售 \(money(num(row["unitPrice"]))) · 本 \(money(num(row["unitCost"])))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if editable {
                    Button { step(-1) } label: { Image(systemName: "minus.circle.fill").font(.title3) }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                Text("\(plainNum(num(row["count"]))) 单").font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth: 40)
                if editable {
                    Button { step(1) } label: { Image(systemName: "plus.circle.fill").font(.title3) }.buttonStyle(.borderless).foregroundStyle(Color.brand)
                }
            }
        default:
            Text("\(money(num(row["unitPrice"]))) × \(plainNum(num(row["count"]))) 人 = \(money(inc)) · 成本 \(money(cost))").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 「只存账号」表：复制账号、复制密码
    @ViewBuilder private var accountChips: some View {
        let totp = codes.accounts.first { $0.id == row.int("totpId") }
        HStack(spacing: 6) {
            chip("person.fill", "账号") { toast.copy(row.str("account"), "已复制账号") }
            if !row.str("password").isEmpty {
                chip("key.fill", "密码") { toast.copy(row.str("password"), "已复制密码") }
            } else if let totp, totp.hasPassword {
                chip("key.fill", "密码") { Task { do { toast.copy(try await codes.password(totp), "已复制密码") } catch { toast.show(error.localizedDescription) } } }
            }
        }
    }
    private func chip(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 3) { Image(systemName: icon).imageScale(.small); Text(title) }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.brand.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.brand)
        }.buttonStyle(.borderless)
    }

    private func togglePaid(_ i: Int) {
        let id = row.str("id")
        ledger.edit { $0.updateRow(month, sheetID, id) { r in
            var ms = r.list("members"); guard i < ms.count else { return }
            ms[i]["paid"] = !ms[i].bool("paid"); r["members"] = ms
        } }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func step(_ d: Double) {
        let id = row.str("id")
        ledger.edit { $0.updateRow(month, sheetID, id) { r in r["count"] = max(0, num(r["count"]) + d) } }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
