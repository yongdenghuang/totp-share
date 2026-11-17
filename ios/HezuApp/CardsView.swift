import SwiftUI

/// 支付卡：卡种（Wise、Maya……）下面挂卡号。点卡号复制完整卡号，有效期、CVC 点一下复制。
/// 本月每种卡、每张卡要花多少钱和网页一样算。
struct CardsView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @State private var country: String?
    @State private var issuerForm: IssuerForm?
    @State private var cardForm: CardForm?
    @State private var usage: Usage?
    @State private var confirm: Confirm?

    struct IssuerForm: Identifiable { var id: String; var name: String; var country: String }
    struct CardForm: Identifiable { var id: String; var issuerID: String; var number: String; var expiry: String; var cvc: String; var note: String }
    struct Usage: Identifiable { let id = UUID(); let title: String; let items: [(String, String, Double)] }
    struct Confirm: Identifiable { let id = UUID(); let title: String; let message: String; let run: () -> Void }

    private var ym: String { ledger.latestMonth }

    var body: some View {
        let st = stats
        List {
            Section {
                HStack(spacing: 10) {
                    box("本月续费", money(st.total))
                    box("卡种", "\(ledger.issuers.count)")
                    box("卡号", "\(ledger.cards.count)")
                }
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if countries.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("全部", country == nil) { country = nil }
                            ForEach(countries, id: \.self) { c in chip(c, country == c) { country = country == c ? nil : c } }
                        }.padding(.horizontal, 16).padding(.vertical, 4)
                    }
                }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            ForEach(shownIssuers, id: \.idKey) { it in issuerSection(it, st) }
            if st.noneCost > 0 {
                Section { HStack { Text("没选卡的账号 \(st.noneN) 个").foregroundStyle(.secondary); Spacer(); Text(money(st.noneCost)).foregroundStyle(.secondary) } }
            }
            if let e = ledger.error { ErrorBanner(message: e) { Task { await ledger.load() } } }
        }
        .listStyle(.insetGrouped)
        .tint(.primary)
        .navigationTitle("支付卡")
        .refreshable { await ledger.load() }
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { issuerForm = IssuerForm(id: "", name: "", country: country ?? "") } label: { Image(systemName: "plus") } } }
        .sheet(item: $issuerForm) { f in IssuerEditor(form: f) }
        .sheet(item: $cardForm) { f in CardEditor(form: f) }
        .sheet(item: $usage) { u in
            NavigationStack {
                List(Array(u.items.enumerated()), id: \.offset) { _, x in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(x.0).font(.body.weight(.medium)); Spacer(); Text(money(x.2)).monospacedDigit() }
                        Text(x.1).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .overlay { if u.items.isEmpty { Text("这个月没有账号在用").foregroundStyle(.secondary) } }
                .navigationTitle(u.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { usage = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirm?.run() }
        } message: { Text(confirm?.message ?? "") }
        .task { ledger.api = api; if !ledger.loaded { await ledger.load() } }
    }

    // MARK: 统计（本月）
    struct Stats { var byIssuer: [String: (n: Int, cost: Double)] = [:]; var byCard: [String: (n: Int, cost: Double)] = [:]; var noneN = 0; var noneCost = 0.0; var total = 0.0 }
    private var stats: Stats {
        var s = Stats()
        for sh in ledger.sheets {
            for r in ledger.rows(ym, sh.str("id")) {
                let c = Calc.cost(sh.str("mode"), r)
                let iid = r.str("issuerId")
                if iid.isEmpty { if c != 0 { s.noneN += 1; s.noneCost += c }; continue }
                var a = s.byIssuer[iid] ?? (0, 0); a.n += 1; a.cost += c; s.byIssuer[iid] = a; s.total += c
                let cid = r.str("cardId")
                if !cid.isEmpty { var b = s.byCard[cid] ?? (0, 0); b.n += 1; b.cost += c; s.byCard[cid] = b }
            }
        }
        return s
    }

    private var countries: [String] {
        var out: [String] = []
        for i in ledger.issuers { let c = i.str("country").isEmpty ? "未填国家" : i.str("country"); if !out.contains(c) { out.append(c) } }
        return out
    }
    private var shownIssuers: [JSON] {
        ledger.issuers.filter { country == nil || ($0.str("country").isEmpty ? "未填国家" : $0.str("country")) == country }
    }

    // MARK: 一个卡种
    @ViewBuilder
    private func issuerSection(_ it: JSON, _ st: Stats) -> some View {
        let iid = it.str("id"), s = st.byIssuer[iid] ?? (0, 0), own = ledger.cards(of: iid)
        Section {
            ForEach(own, id: \.idKey) { c in cardRow(c, st.byCard[c.str("id")] ?? (0, 0), issuerName: it.str("name")) }
            Button { cardForm = CardForm(id: "", issuerID: iid, number: "", expiry: "", cvc: "", note: "") } label: { Label("添加卡号", systemImage: "plus.circle") }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(it.str("name")).font(.headline).foregroundStyle(.primary)
                    if !it.str("country").isEmpty { Tag(text: it.str("country"), color: .brand) }
                    Spacer()
                    Menu {
                        Button { issuerForm = IssuerForm(id: iid, name: it.str("name"), country: it.str("country")) } label: { Label("改名 / 国家", systemImage: "pencil") }
                        Button { usage = Usage(title: it.str("name"), items: using { $0.str("issuerId") == iid }) } label: { Label("查看在用的账号", systemImage: "list.bullet") }
                        Button(role: .destructive) { deleteIssuer(it) } label: { Label("删除卡种", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle").font(.body) }
                }
                Text("本月 \(money(s.cost)) · \(s.n) 个账号在用 · \(own.count) 张卡").font(.caption).foregroundStyle(.secondary)
            }
            .textCase(nil).padding(.bottom, 2)
        }
    }

    private func cardRow(_ c: JSON, _ s: (n: Int, cost: Double), issuerName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { toast.copy(c.str("number").replacingOccurrences(of: " ", with: ""), "已复制卡号") } label: {
                    Text(formatCard(c.str("number"), masked: true)).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(.primary)
                }.buttonStyle(.borderless)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(money(s.cost)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Button("\(s.n) 个账号 ›") { usage = Usage(title: issuerName + " " + Calc.cardLabel(c), items: using { $0.str("cardId") == c.str("id") }) }
                        .font(.caption).buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                pill("有效期", c.str("expiry"), secret: false)
                pill("CVC", c.str("cvc"), secret: true)
                if !c.str("note").isEmpty { Text(c.str("note")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleteCard(c, issuerName) } label: { Label("删除", systemImage: "trash") }
            Button { edit(c) } label: { Label("编辑", systemImage: "pencil") }.tint(.brand)
        }
        .contextMenu {
            Button { toast.copy(c.str("number").replacingOccurrences(of: " ", with: ""), "已复制卡号") } label: { Label("复制卡号", systemImage: "creditcard") }
            if !c.str("expiry").isEmpty { Button { toast.copy(c.str("expiry"), "已复制有效期") } label: { Label("复制有效期", systemImage: "calendar") } }
            if !c.str("cvc").isEmpty { Button { toast.copy(c.str("cvc"), "已复制 CVC") } label: { Label("复制 CVC", systemImage: "lock") } }
            Button { toast.copy([c.str("number").replacingOccurrences(of: " ", with: ""), c.str("expiry"), c.str("cvc")].filter { !$0.isEmpty }.joined(separator: " "), "已复制卡号、有效期、CVC") } label: { Label("复制全部", systemImage: "doc.on.doc") }
            Button { edit(c) } label: { Label("编辑", systemImage: "pencil") }
            Button(role: .destructive) { deleteCard(c, issuerName) } label: { Label("删除", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func pill(_ label: String, _ value: String, secret: Bool) -> some View {
        if value.isEmpty {
            Text("\(label) 未填").font(.caption).foregroundStyle(.tertiary)
        } else {
            Button { toast.copy(value, "已复制\(label)") } label: {
                HStack(spacing: 4) {
                    Text(label).foregroundStyle(.secondary)
                    Text(secret ? String(repeating: "•", count: max(3, value.count)) : value).font(.caption.monospaced().weight(.semibold))
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(.primary)
            }.buttonStyle(.borderless)
        }
    }

    /// 卡号四位一组；masked 时只露前 4 位和后 4 位（点一下复制的仍是完整卡号）
    private func formatCard(_ n: String, masked: Bool = false) -> String {
        let d = n.replacingOccurrences(of: " ", with: "")
        guard d.count >= 12, d.allSatisfy(\.isNumber) else { return n.isEmpty ? "未填卡号" : n }
        if masked { return String(d.prefix(4)) + " •••• •••• " + String(d.suffix(4)) }
        return stride(from: 0, to: d.count, by: 4).map { i -> String in
            let s = d.index(d.startIndex, offsetBy: i), e = d.index(s, offsetBy: min(4, d.count - i))
            return String(d[s..<e])
        }.joined(separator: " ")
    }

    private func using(_ test: (JSON) -> Bool) -> [(String, String, Double)] {
        var out: [(String, String, Double)] = []
        for sh in ledger.sheets {
            for r in ledger.rows(ym, sh.str("id")) where test(r) {
                let g = sh.bool("grouped") ? (ledger.group(r.str("group"))?.name ?? "未分组") : nil
                out.append((r.str("account").isEmpty ? "未填账号" : r.str("account"), sh.str("name") + (g.map { " · " + $0 } ?? ""), Calc.cost(sh.str("mode"), r)))
            }
        }
        return out
    }

    private func edit(_ c: JSON) {
        cardForm = CardForm(id: c.str("id"), issuerID: c.str("issuerId"), number: c.str("number"), expiry: c.str("expiry"), cvc: c.str("cvc"), note: c.str("note"))
    }

    private func usedCount(_ test: (JSON) -> Bool) -> Int {
        ledger.monthKeys.reduce(0) { n, ym in n + ledger.sheets.reduce(0) { $0 + ledger.rows(ym, $1.str("id")).filter(test).count } }
    }

    private func deleteIssuer(_ it: JSON) {
        let iid = it.str("id"), used = usedCount { $0.str("issuerId") == iid }
        confirm = Confirm(title: "删除「\(it.str("name"))」？", message: "它下面的卡号会一起删除。" + (used > 0 ? "有 \(used) 个账号（含历史月份）选了它，删除后会变成「不指定」。" : "")) {
            ledger.edit { s in s.editList("issuers") { $0.removeAll { $0.str("id") == iid } }; s.clearCardRefs() }
            toast.show("已删除")
        }
    }

    private func deleteCard(_ c: JSON, _ issuerName: String) {
        let cid = c.str("id"), used = usedCount { $0.str("cardId") == cid }
        confirm = Confirm(title: "删除 \(issuerName) \(Calc.cardLabel(c))？", message: used > 0 ? "有 \(used) 个账号（含历史月份）选了它，删除后会变成「不指定卡号」。" : "删除后不能恢复。") {
            ledger.edit { s in s.editList("cards") { $0.removeAll { $0.str("id") == cid } }; s.clearCardRefs() }
            toast.show("已删除")
        }
    }

    private func box(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(v).font(.system(.title3, design: .rounded).weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 0)
    }

    private func chip(_ t: String, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(t).font(.subheadline.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Color.brand : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }.buttonStyle(.plain)
    }
}

struct IssuerEditor: View {
    @State var form: CardsView.IssuerForm
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    private let presets = ["美国", "菲律宾", "尼日利亚", "中国", "香港", "新加坡", "英国", "欧洲"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("卡种名称，如 Wise、Maya Bank", text: $form.name)
                Section {
                    TextField("国家 / 地区", text: $form.country)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(presets, id: \.self) { p in Button(p) { form.country = p }.buttonStyle(.bordered).controlSize(.small) } }
                    }
                }
            }
            .navigationTitle(form.id.isEmpty ? "新卡种" : "编辑卡种").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let f = form, name = f.name.trimmingCharacters(in: .whitespaces), country = f.country.trimmingCharacters(in: .whitespaces)
                        if f.id.isEmpty {
                            let item: JSON = ["id": "i_" + uid(), "name": name, "country": country]
                            ledger.edit { s in s.editList("issuers") { $0.append(item) } }
                        } else {
                            ledger.edit { s in s.editList("issuers") { l in if let i = l.firstIndex(where: { $0.str("id") == f.id }) { l[i]["name"] = name; l[i]["country"] = country } } }
                        }
                        toast.show("已保存"); dismiss()
                    }.disabled(form.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.presentationDetents([.medium])
    }
}

struct CardEditor: View {
    @State var form: CardsView.CardForm
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("卡号", text: $form.number).keyboardType(.numberPad).font(.body.monospaced())
                    HStack {
                        TextField("有效期 MM/YY", text: $form.expiry).keyboardType(.numbersAndPunctuation)
                            .onChange(of: form.expiry) { form.expiry = formatExpiry($0) }
                        TextField("CVC", text: $form.cvc).keyboardType(.numberPad).font(.body.monospaced()).frame(width: 90)
                    }
                    TextField("备注（如 2号卡、主卡）", text: $form.note)
                } header: { Text(ledger.issuer(form.issuerID)?.str("name") ?? "") } footer: {
                    Text("卡号、有效期和 CVC 都加密保存在你的服务器上。列表里 CVC 显示成圆点，点一下才复制。")
                }
            }
            .navigationTitle(form.id.isEmpty ? "添加卡号" : "编辑卡号").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let f = form
                        let fields: JSON = ["number": f.number.trimmingCharacters(in: .whitespaces), "expiry": f.expiry.trimmingCharacters(in: .whitespaces),
                                            "cvc": f.cvc.trimmingCharacters(in: .whitespaces), "note": f.note.trimmingCharacters(in: .whitespaces)]
                        if f.id.isEmpty {
                            var item: JSON = ["id": "c_" + uid(), "issuerId": f.issuerID]
                            for (k, v) in fields { item[k] = v }
                            let it = item
                            ledger.edit { s in s.editList("cards") { $0.append(it) } }
                        } else {
                            ledger.edit { s in s.editList("cards") { l in if let i = l.firstIndex(where: { $0.str("id") == f.id }) { for (k, v) in fields { l[i][k] = v } } } }
                        }
                        toast.show("已保存"); dismiss()
                    }
                }
            }
        }.presentationDetents([.medium, .large])
    }
}

/// 「1228」→「12/28」
func formatExpiry(_ s: String) -> String {
    let d = s.filter(\.isNumber)
    if s.contains("/") || d.count < 3 { return String(s.prefix(7)) }
    return String(d.prefix(2)) + "/" + String(d.dropFirst(2).prefix(4))
}
