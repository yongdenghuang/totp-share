import SwiftUI

/// 添加 / 编辑账本里的一行
struct RowEditor: View {
    let sheetID: String
    let ym: String
    let rowID: String              // "" = 新建
    let presetGroup: String
    let editable: Bool
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss

    struct Member: Identifiable { let id = UUID(); var name: String; var amount: String; var paid: Bool }

    @State private var account = ""
    @State private var group = ""
    @State private var hasRenew = false
    @State private var renew = Date()
    @State private var issuerID = ""
    @State private var cardID = ""
    @State private var members: [Member] = []
    @State private var quickAdd = ""
    @State private var unitPrice = ""
    @State private var unitCost = ""
    @State private var count = ""
    @State private var cost = ""
    @State private var note = ""
    @State private var password = ""
    @State private var stopped = false
    @State private var original: JSON = [:]
    @State private var ready = false

    private var sheet: JSON { ledger.sheet(sheetID) ?? [:] }
    private var mode: String { sheet.str("mode") }
    private var isNew: Bool { rowID.isEmpty }
    private var linked: LTotp? { ledger.totpAccount(original.int("totpId")) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(mode == "resale" ? "项目名，比如 Plus代充" : "账号（邮箱或名称）", text: $account)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(mode == "resale" ? .default : .emailAddress)
                    if sheet.bool("grouped") {
                        Picker("分组", selection: $group) {
                            Text("未分组").tag("")
                            ForEach(ledger.groups) { g in Text(g.name).tag(g.id) }
                        }
                    }
                    if let a = linked {
                        HStack {
                            Label("已关联验证码账号", systemImage: "link").foregroundStyle(.secondary)
                            Spacer()
                            if let c = codes.codes[a.id] { Text(c).font(.body.monospaced()).foregroundStyle(Color.brand) }
                        }.font(.subheadline)
                    } else if mode != "resale" {
                        TextField("账号密码（可不填，加密保存）", text: $password).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } footer: {
                    if linked != nil { Text("名称和分组会和验证码账号保持一致，改了两边一起变。") }
                }

                if mode == "accounts" {
                    // 只存账号：没有续费、收费
                } else if mode != "resale" {
                    Section("续费") {
                        Toggle("续费日期", isOn: $hasRenew.animation())
                        if hasRenew {
                            DatePicker("日期", selection: $renew, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                            Button("顺延一个月") { renew = parseISO(shiftMonth(isoDate(renew), 1)) ?? renew }
                        }
                        cardPickers
                    }
                } else {
                    Section("付款渠道") { cardPickers }
                }

                switch mode {
                case "accounts": EmptyView()
                case "members": membersSection
                case "resale":
                    Section {
                        numField("售价", $unitPrice)
                        numField("成本/份", $unitCost)
                        Stepper(value: Binding(get: { Int(num(count)) }, set: { count = String($0) }), in: 0...9999) {
                            HStack { Text("本月单数"); Spacer(); Text(count.isEmpty ? "0" : count).monospacedDigit() }
                        }
                    } header: { Text("代充") } footer: { Text("售价和成本以后每个月自动带过去，每月只用记单数。") }
                default:
                    Section("收费") {
                        numField("单价（每人每月）", $unitPrice)
                        numField("人数", $count)
                    }
                }

                if mode != "resale" && mode != "accounts" {
                    Section { numField("续费成本", $cost) }
                }

                if mode != "accounts" { Section {
                    let inc = income, c = costValue
                    HStack { Text("收费"); Spacer(); Text(money(inc)).monospacedDigit() }
                    HStack { Text("成本"); Spacer(); Text(money(c)).monospacedDigit() }
                    HStack { Text("利润").fontWeight(.semibold); Spacer(); Text(money(inc - c)).fontWeight(.semibold).foregroundStyle(inc - c >= 0 ? Color.good : Color.bad).monospacedDigit() }
                } }

                Section {
                    TextField("备注", text: $note, axis: .vertical).lineLimit(1...4)
                    Toggle("标记为停止（下个月不带入）", isOn: $stopped)
                }
            }
            .disabled(!editable)
            .navigationTitle(isNew ? (mode == "resale" ? "添加代充项目" : "添加账号") : (account.isEmpty ? "编辑" : account))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if editable { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!ready) } }
            }
            .onAppear(perform: loadRow)
        }
    }

    private var cardPickers: some View {
        Group {
            Picker(mode == "resale" ? "渠道" : "续费卡", selection: $issuerID) {
                Text("不指定").tag("")
                ForEach(ledger.issuers, id: \.idKey) { i in
                    Text(i.str("name") + (i.str("country").isEmpty ? "" : " · " + i.str("country"))).tag(i.str("id"))
                }
            }
            .onChange(of: issuerID) { new in if ledger.card(cardID)?.str("issuerId") != new { cardID = "" } }
            if !issuerID.isEmpty {
                Picker("卡号", selection: $cardID) {
                    Text("不指定").tag("")
                    ForEach(ledger.cards(of: issuerID), id: \.idKey) { c in Text(Calc.cardLabel(c)).tag(c.str("id")) }
                }
            }
        }
    }

    private var membersSection: some View {
        Section {
            ForEach($members) { $m in
                HStack(spacing: 10) {
                    Button { m.paid.toggle() } label: {
                        Image(systemName: m.paid ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(m.paid ? Color.good : .secondary)
                    }.buttonStyle(.borderless)
                    TextField("名字（可不填）", text: $m.name)
                    TextField("金额", text: $m.amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
            }
            .onDelete { members.remove(atOffsets: $0) }
            HStack {
                TextField("加人：300 或 张三280 或 35x4", text: $quickAdd).onSubmit(addQuick)
                Button("添加", action: addQuick).disabled(quickAdd.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            HStack { Text("每人收费"); Spacer(); if !members.isEmpty { Text("\(members.filter(\.paid).count)/\(members.count) 已收") } }
        } footer: { Text("点圆圈切换已收 / 未收，左滑删除一个人。可以一次填多个，用空格隔开。") }
    }

    private func numField(_ label: String, _ v: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField("0", text: v).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private var income: Double {
        mode == "members" ? members.reduce(0) { $0 + num($1.amount) } : num(unitPrice) * num(count)
    }
    private var costValue: Double { mode == "resale" ? num(unitCost) * num(count) : num(cost) }

    private func addQuick() {
        members.append(contentsOf: parseMembers(quickAdd).map { Member(name: $0.0, amount: plainNum($0.1), paid: false) })
        quickAdd = ""
    }

    private func loadRow() {
        guard !ready else { return }
        if isNew {
            group = presetGroup
            if mode != "resale", let s = ledger.rows(ym, sheetID).first(where: { !$0.str("renew").isEmpty }) { _ = s }
        } else if let r = ledger.rows(ym, sheetID).first(where: { $0.str("id") == rowID }) {
            original = r
            account = r.str("account"); group = r.str("group")
            if let d = parseISO(r.str("renew")) { hasRenew = true; renew = d }
            issuerID = r.str("issuerId"); cardID = r.str("cardId")
            members = r.list("members").map { Member(name: $0.str("name"), amount: plainNum(num($0["amount"])), paid: $0.bool("paid")) }
            let z: (Any?) -> String = { num($0) == 0 ? "" : plainNum(num($0)) }
            unitPrice = z(r["unitPrice"]); unitCost = z(r["unitCost"]); count = z(r["count"]); cost = z(r["cost"])
            note = r.str("note"); password = r.str("password"); stopped = r.bool("stopped")
        }
        ready = true
    }

    private func save() {
        let acct = account.trimmingCharacters(in: .whitespaces)
        if acct.isEmpty && isNew { toast.show(mode == "resale" ? "请填写项目名" : "请填写账号"); return }
        var fields: JSON = [
            "account": acct, "group": sheet.bool("grouped") ? group : original.str("group"),
            "renew": mode != "resale" && hasRenew ? isoDate(renew) : (mode == "resale" ? original.str("renew") : ""),
            "issuerId": issuerID, "cardId": cardID,
            "members": members.map { ["name": $0.name.trimmingCharacters(in: .whitespaces), "amount": num($0.amount), "paid": $0.paid] as JSON },
            "unitPrice": num(unitPrice), "unitCost": num(unitCost), "count": num(count), "cost": num(cost),
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines), "stopped": stopped,
        ]
        if linked == nil { fields["password"] = password }
        let ym = ym, sid = sheetID
        if isNew {
            var row = newRow()
            for (k, v) in fields { row[k] = v }
            // 和网页一样：账号和某个验证码账号同名（只有一个）时自动关联
            let key = normName(acct)
            let same = ledger.totp.filter { normName($0.name) == key }
            if same.count == 1 && mode != "resale" {
                row["totpId"] = same[0].id
                if sheet.bool("grouped") && group.isEmpty, let g = ledger.groups.first(where: { $0.name == same[0].group }) { row["group"] = g.id }
            }
            let r = row
            ledger.edit { $0.addRow(ym, sid, r) }
            toast.show("已添加")
        } else {
            let id = rowID
            ledger.edit { s in s.updateRow(ym, sid, id) { row in for (k, v) in fields { row[k] = v } } }
            syncTotp(name: acct)
            toast.show("已保存")
        }
        dismiss()
    }

    /// 关联了验证码账号的行：改了名字或分组，验证码账号那边也跟着改（存档月份不动）
    private func syncTotp(name: String) {
        guard let a = linked, !ledger.isArchived(ym) else { return }
        let newGroup = ledger.group(group)?.name ?? ""
        Task {
            if !name.isEmpty && name != a.name { _ = try? await api.post("/admin/accounts/\(a.id)/field", ["field": "name", "value": name]) }
            if sheet.bool("grouped") && newGroup != a.group { _ = try? await api.post("/admin/accounts/\(a.id)/field", ["field": "group_name", "value": newGroup]) }
            await codes.load(); await ledger.load()
        }
    }
}

func normName(_ s: String) -> String {
    s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
}

/// 「300 350 张三280 35x4」→ [(名字, 金额)]，和网页 parseMembers 一样
func parseMembers(_ text: String) -> [(String, Double)] {
    var out: [(String, Double)] = []
    var pending = ""
    let toks = text.trimmingCharacters(in: .whitespaces).components(separatedBy: CharacterSet(charactersIn: " ,，、+＋\t"))
    for tok in toks where !tok.isEmpty {
        if let m = tok.firstMatch(#"^(\d+(?:\.\d+)?)[xX×*](\d+)$"#) {
            for _ in 0..<min(Int(m[2]) ?? 0, 50) { out.append(("", Double(m[1]) ?? 0)) }
            pending = ""; continue
        }
        if let m = tok.firstMatch(#"^(.*?)[:：¥]?(\d+(?:\.\d+)?)$"#) {
            out.append(((pending + m[1]).trimmingCharacters(in: .whitespaces), Double(m[2]) ?? 0)); pending = ""
        } else { pending += tok }
    }
    if !pending.isEmpty { out.append((pending, 0)) }
    return out
}

extension String {
    /// 正则匹配，返回各个分组（[0] 是整个匹配）
    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: self).map { String(self[$0]) } ?? "" }
    }
}
