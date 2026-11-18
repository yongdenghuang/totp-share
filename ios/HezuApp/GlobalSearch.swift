import SwiftUI

/// 首页顶上的「搜索全部」：一次搜验证码、密码本、备忘录、合租账号、支付卡、VPS、GPT 账号。
/// 结果里能直接复制（验证码、密码、卡号、IP），点进去就是对应的详情页。
struct GlobalSearchResults: View {
    let query: String
    @EnvironmentObject var codes: CodesStore
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var ledger: LedgerStore
    @EnvironmentObject var gpt: GPTStore
    @EnvironmentObject var toast: Toast

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private func hit(_ fields: String...) -> Bool { fields.contains { $0.lowercased().contains(q) } }

    var body: some View {
        let c = codeHits, v = vaultHits, n = noteHits, r = rowHits, k = cardHits, s = vpsHits, g = gptHits
        List {
            if !c.isEmpty {
                Section("验证码 · 点一下复制") {
                    ForEach(c) { a in
                        Button { copyCode(a) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.name).foregroundStyle(.primary).lineLimit(1)
                                    if !a.group.isEmpty { Text(a.group).font(.caption).foregroundStyle(codes.color(of: a.group)) }
                                }
                                Spacer()
                                Text(spaced(codes.codes[a.id] ?? "······")).font(.system(.title3, design: .monospaced).weight(.semibold)).foregroundStyle(Color.brand)
                            }
                        }
                    }
                }
            }
            if !v.isEmpty {
                Section("密码本") {
                    ForEach(v) { it in
                        NavigationLink { VaultDetailView(itemID: it.id) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(vault.color(it.type)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.title.isEmpty ? (it.account.isEmpty ? "未命名" : it.account) : it.title).lineLimit(1)
                                    if !it.account.isEmpty || !it.phone.isEmpty { Text(it.account.isEmpty ? it.phone : it.account).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                if !it.account.isEmpty { copyButton("person", "复制账号") { toast.copy(it.account, "已复制账号") } }
                                if it.hasPassword { copyButton("key", "复制密码") { copyPassword(it) } }
                            }
                        }
                    }
                }
            }
            if !r.isEmpty {
                Section("合租账号") {
                    ForEach(r, id: \.row.id) { x in
                        NavigationLink { LedgerSheetView(sheetID: x.sheetID) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(x.row.account).lineLimit(1)
                                    Text(x.meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                copyButton("doc.on.doc", "复制账号") { toast.copy(x.row.account, "已复制账号") }
                            }
                        }
                    }
                }
            }
            if !n.isEmpty {
                Section("备忘录") {
                    ForEach(n) { note in
                        NavigationLink { NoteEditor(initial: note) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).lineLimit(1)
                                Text(snippet(note.text)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            if !k.isEmpty {
                Section("支付卡 · 点一下复制卡号") {
                    ForEach(k, id: \.id) { x in
                        Button { toast.copy(x.number.replacingOccurrences(of: " ", with: ""), "已复制卡号") } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(x.issuer).foregroundStyle(.primary)
                                    Text("•••• " + String(x.number.replacingOccurrences(of: " ", with: "").suffix(4)) + (x.expiry.isEmpty ? "" : "  ·  " + x.expiry) + (x.note.isEmpty ? "" : "  ·  " + x.note))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !x.cvc.isEmpty { copyButton("number", "复制 CVC") { toast.copy(x.cvc, "已复制 CVC") } }
                            }
                        }
                    }
                }
            }
            if !s.isEmpty {
                Section("VPS") {
                    ForEach(s, id: \.self) { id in
                        let x = ledger.vps.first { $0.str("id") == id } ?? [:]
                        NavigationLink { VPSDetail(id: id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(x.str("host").isEmpty ? "未命名 VPS" : x.str("host")).lineLimit(1)
                                    if !x.str("ip").isEmpty { Text(x.str("ip")).font(.caption.monospaced()).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if !x.str("ip").isEmpty { copyButton("network", "复制 IP") { toast.copy(x.str("ip"), "已复制 IP") } }
                                if !x.str("password").isEmpty { copyButton("key", "复制密码") { toast.copy(x.str("password"), "已复制密码") } }
                            }
                        }
                    }
                }
            }
            if !g.isEmpty {
                Section("GPT 账号") {
                    ForEach(g, id: \.self) { id in
                        let a = gpt.accounts.first { $0.int("id") == id } ?? [:]
                        NavigationLink { GPTDetail(id: id) } label: { GPTRow(a: a) }
                    }
                }
            }
            if c.isEmpty && v.isEmpty && n.isEmpty && r.isEmpty && k.isEmpty && s.isEmpty && g.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text("没有找到「\(query)」").font(.headline)
                    Text("会搜验证码、密码本、备忘录、合租账号、支付卡、VPS 和 GPT 账号").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .tint(.primary)
        .task {
            if Date() >= codes.expiresAt { await codes.refreshCodes() }
            if !gpt.loaded { await gpt.load() }
        }
        .task(id: codes.expiresAt) {
            // 验证码到期就换新的
            let wait = codes.expiresAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64((wait + 0.3) * 1_000_000_000)) }
            if !Task.isCancelled { await codes.refreshCodes() }
        }
    }

    // MARK: 匹配
    private var codeHits: [TotpAccount] { codes.accounts.filter { hit($0.name, $0.group) } }
    private var vaultHits: [VaultItem] {
        vault.items.filter { hit($0.title, $0.account, $0.phone, $0.site, $0.note, vault.type($0.type)?.name ?? "") }
    }
    private var noteHits: [Note] { notes.sorted.filter { hit($0.text) } }

    struct RowHit { let row: (id: String, account: String); let sheetID: String; let meta: String }
    private var rowHits: [RowHit] {
        var out: [RowHit] = []
        let ym = ledger.latestMonth
        for sh in ledger.sheets {
            let sid = sh.str("id")
            for r in ledger.rows(ym, sid) where !r.str("account").isEmpty {
                let members = r.list("members").map { $0.str("name") }.joined(separator: " ")
                guard hit(r.str("account"), r.str("note"), members) else { continue }
                var meta = sh.str("name")
                if let d = daysUntil(r.str("renew")) { meta += " · " + relText(d) + "续费" }
                if r.bool("stopped") { meta += " · 已停" }
                out.append(RowHit(row: (sid + ":" + r.str("id"), r.str("account")), sheetID: sid, meta: meta))
            }
        }
        return out
    }

    struct CardHit { let id: String; let issuer: String; let number: String; let expiry: String; let cvc: String; let note: String }
    private var cardHits: [CardHit] {
        ledger.cards.compactMap { c in
            let issuer = ledger.issuer(c.str("issuerId"))?.str("name") ?? ""
            let digits = c.str("number").replacingOccurrences(of: " ", with: "")
            guard hit(issuer, digits, c.str("note")) else { return nil }
            return CardHit(id: c.str("id"), issuer: issuer.isEmpty ? "未命名卡种" : issuer, number: c.str("number"), expiry: c.str("expiry"), cvc: c.str("cvc"), note: c.str("note"))
        }
    }
    private var vpsHits: [String] {
        ledger.vps.filter { hit($0.str("host"), $0.str("ip"), $0.str("note"), $0.str("provider")) }.map { $0.str("id") }
    }
    private var gptHits: [Int] {
        gpt.accounts.filter { hit($0.str("name"), $0.str("email"), $0.str("plan")) }.map { $0.int("id") }
    }

    // MARK: 小工具
    private func copyButton(_ icon: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                .frame(width: 34, height: 34).background(Color.brand.opacity(0.1), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
    private func copyCode(_ a: TotpAccount) {
        if let c = codes.codes[a.id] { toast.copy(c, "已复制 \(a.name) 的验证码") }
        else { Task { await codes.refreshCodes(); if let c = codes.codes[a.id] { toast.copy(c, "已复制验证码") } else { toast.show("验证码还没加载出来") } } }
    }
    private func copyPassword(_ it: VaultItem) {
        Task { do { toast.copy(try await vault.reveal(it).password, "已复制密码") } catch { toast.show(error.localizedDescription) } }
    }
    private func spaced(_ c: String) -> String { c.count == 6 ? String(c.prefix(3)) + " " + String(c.suffix(3)) : c }
    /// 备忘录里搜到的那一行
    private func snippet(_ text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.lowercased().contains(q) }.map { String($0.prefix(100)) } ?? ""
    }
}
