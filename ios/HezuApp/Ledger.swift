import SwiftUI

/// 合租账本（原生）。数据结构和网页 app.js 完全一样：整份 JSON 存在服务器上，带版本号。
///
/// 保存方式：每次改动都是一个「对账本做什么」的函数。先在本地执行（界面立刻变），再整份 PUT 上去；
/// 服务器说版本过期了（别的设备刚改过）就重新取最新的一份，把同一个改动再做一遍再存——
/// 这样手机和网页同时在改也不会互相覆盖。不认识的字段原样保留。
typealias JSON = [String: Any]

struct LGroup: Identifiable, Hashable { let id: String; let name: String; let color: String }
struct LTotp: Hashable { let id: Int; let name: String; let group: String; let hasPassword: Bool }

@MainActor
final class LedgerStore: ObservableObject {
    var api: API!
    @Published private(set) var S: JSON = [:]
    @Published private(set) var groups: [LGroup] = []
    @Published private(set) var totp: [LTotp] = []
    @Published var error: String?
    @Published var loaded = false
    @Published var saving = false
    @Published var rates: Double?            // 1 美元 = 多少人民币
    @Published var adsDevices: [String: Int] = [:]   // AdsPower 成员邮箱（小写）→ 登录设备数量
    private var rev = 0
    private var queue: Task<Void, Never>?

    // MARK: 读取
    func load() async {
        do {
            let d = try await api.get("/admin/hezu/api/state")
            adopt(d)
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func adopt(_ d: JSON) {
        S = d.dict("state"); rev = d.int("rev")
        groups = d.list("groups").map { LGroup(id: $0.str("id"), name: $0.str("name"), color: $0.str("color")) }
        totp = d.list("accounts").map { LTotp(id: $0.int("id"), name: $0.str("name"), group: $0.str("group"), hasPassword: $0.bool("hasPassword")) }
    }

    func loadRates() async {
        guard rates == nil, let d = try? await api.get("/admin/hezu/api/rates") else { return }
        rates = (d.dict("rates")["CNY"] as? Double) ?? (d.dict("rates")["CNY"] as? NSNumber)?.doubleValue
    }

    /// AdsPower 各成员的登录设备数量（只存账号的表上显示「N 台」）
    func loadAdsDevices() async {
        guard let d = try? await api.get("/api/app/adspower/devices") else { return }
        var m: [String: Int] = [:]
        for (k, v) in d.dict("counts") { if let n = (v as? Int) ?? (v as? NSNumber)?.intValue { m[k] = n } }
        adsDevices = m
    }
    func adsDeviceCount(_ account: String) -> Int? { adsDevices[account.trimmingCharacters(in: .whitespaces).lowercased()] }

    // MARK: 保存
    private var pending: [(inout JSON) -> Void] = []
    private var flushing = false

    /// 做一个改动并保存。改动要能在「别人刚改过的最新版」上重复执行。
    func edit(_ change: @escaping (inout JSON) -> Void) {
        var local = S
        change(&local)
        S = local
        pending.append(change)
        if !flushing { Task { await flush() } }
    }

    /// 把还没存上的改动依次存上去。版本冲突时取最新版，把所有还没存上的改动按顺序重做一遍再存。
    private func flush() async {
        flushing = true; saving = true
        defer { flushing = false; saving = false }
        var conflicts = 0
        while !pending.isEmpty {
            let included = pending.count
            do {
                let d = try await api.put("/admin/hezu/api/state", ["rev": rev, "state": S])
                rev = d.int("rev")
                pending.removeFirst(included)
                error = nil
                conflicts = 0
            } catch let e as APIError where e.code == 409 && conflicts < 4 {
                conflicts += 1
                guard let d = try? await api.get("/admin/hezu/api/state") else { break }
                adopt(d)
                var fresh = S
                for c in pending { c(&fresh) }
                S = fresh
            } catch {
                self.error = "没保存上：\(error.localizedDescription)"
                pending.removeAll()
                await load()
                return
            }
        }
    }

    // MARK: 常用读取
    var sheets: [JSON] { S.list("sheets") }
    var monthKeys: [String] { S.dict("months").keys.sorted() }
    var latestMonth: String { monthKeys.last ?? "" }
    func month(_ ym: String) -> JSON { S.dict("months").dict(ym) }
    func isArchived(_ ym: String) -> Bool { month(ym).bool("archived") }
    func rows(_ ym: String, _ sheet: String) -> [JSON] { month(ym).dict("rows").list(sheet) }
    func sheet(_ id: String) -> JSON? { sheets.first { $0.str("id") == id } }
    var issuers: [JSON] { S.list("issuers") }
    var cards: [JSON] { S.list("cards") }
    var vps: [JSON] { S.list("vps") }
    func issuer(_ id: String) -> JSON? { issuers.first { $0.str("id") == id } }
    func card(_ id: String) -> JSON? { cards.first { $0.str("id") == id } }
    func cards(of issuer: String) -> [JSON] { cards.filter { $0.str("issuerId") == issuer } }
    func group(_ id: String) -> LGroup? { groups.first { $0.id == id } }
    func totpAccount(_ id: Int) -> LTotp? { id > 0 ? totp.first { $0.id == id } : nil }
}

// MARK: - 计算（和网页 app.js 一致）
enum Calc {
    // accounts = 只存账号（账号、密码、验证码），不算钱
    static func income(_ mode: String, _ r: JSON) -> Double {
        if mode == "accounts" { return 0 }
        return mode == "members" ? r.list("members").reduce(0) { $0 + num($1["amount"]) } : num(r["unitPrice"]) * num(r["count"])
    }
    static func cost(_ mode: String, _ r: JSON) -> Double {
        if mode == "accounts" { return 0 }
        return mode == "resale" ? num(r["unitCost"]) * num(r["count"]) : num(r["cost"])
    }
    static func heads(_ mode: String, _ r: JSON) -> Double {
        if mode == "accounts" { return 0 }
        return mode == "members" ? Double(r.list("members").count) : num(r["count"])
    }
    struct Stats { var n = 0; var heads = 0.0; var income = 0.0; var cost = 0.0; var profit: Double { income - cost } }
    static func stats(_ mode: String, _ rows: [JSON]) -> Stats {
        var s = Stats()
        for r in rows { if !r.bool("stopped") { s.n += 1 }; s.heads += heads(mode, r); s.income += income(mode, r); s.cost += cost(mode, r) }
        return s
    }
    static func cardLabel(_ c: JSON?, full: Bool = false) -> String {
        guard let c else { return "" }
        let d = c.str("number").replacingOccurrences(of: " ", with: "")
        let base = !full && d.count >= 8 && d.allSatisfy(\.isNumber) ? "•••• " + d.suffix(4) : c.str("number")
        let s = [base, c.str("note")].filter { !$0.isEmpty }.joined(separator: " · ")
        return s.isEmpty ? "未填卡号" : s
    }
    static func priceUsd(_ t: String) -> Double? {
        let s = t.replacingOccurrences(of: ",", with: "")
        guard let r = s.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(s[r])
    }
}

func uid() -> String {
    String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String((0..<6).map { _ in "0123456789abcdefghijklmnopqrstuvwxyz".randomElement()! })
}

func isoDate(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f.string(from: d)
}
func parseISO(_ s: String) -> Date? {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return s.count == 10 ? f.date(from: s) : nil
}
/// 日期往后挪 n 个月（月底不存在的日子取当月最后一天），和网页 shiftMonth 一样
func shiftMonth(_ iso: String, _ n: Int) -> String {
    let p = iso.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return iso }
    var y = p[0], m = p[1] + n
    y += Int(floor(Double(m - 1) / 12)); m = ((m - 1) % 12 + 12) % 12 + 1
    let days = Calendar.current.range(of: .day, in: .month, for: Calendar.current.date(from: DateComponents(year: y, month: m, day: 1))!)!.count
    return String(format: "%04d-%02d-%02d", y, m, min(p[2], days))
}
func nextYM(_ ym: String) -> String {
    let p = ym.split(separator: "-").compactMap { Int($0) }
    guard p.count == 2 else { return ym }
    return p[1] == 12 ? String(format: "%04d-01", p[0] + 1) : String(format: "%04d-%02d", p[0], p[1] + 1)
}
func ymLabel(_ ym: String) -> String {
    let p = ym.split(separator: "-")
    return p.count == 2 ? "\(p[0]) 年 \(Int(p[1]) ?? 0) 月" : ym
}
func plainNum(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }

// MARK: - 账本上的改动（都要能在最新版本上重放）
extension Dictionary where Key == String, Value == Any {
    /// 改某个月某张表里的一行
    mutating func updateRow(_ ym: String, _ sheet: String, _ id: String, _ f: (inout JSON) -> Void) {
        var months = dict("months"), M = months.dict(ym), rows = M.dict("rows"), list = rows.list(sheet)
        guard let i = list.firstIndex(where: { $0.str("id") == id }) else { return }
        f(&list[i]); rows[sheet] = list; M["rows"] = rows; months[ym] = M; self["months"] = months
    }
    mutating func addRow(_ ym: String, _ sheet: String, _ row: JSON) {
        var months = dict("months"), M = months.dict(ym), rows = M.dict("rows"), list = rows.list(sheet)
        guard !list.contains(where: { $0.str("id") == row.str("id") }) else { return }
        list.append(row); rows[sheet] = list; M["rows"] = rows; months[ym] = M; self["months"] = months
    }
    mutating func removeRow(_ ym: String, _ sheet: String, _ id: String) {
        var months = dict("months"), M = months.dict(ym), rows = M.dict("rows")
        rows[sheet] = rows.list(sheet).filter { $0.str("id") != id }; M["rows"] = rows; months[ym] = M; self["months"] = months
    }
    mutating func skipTotp(_ id: Int) {
        var list = (self["totpSkip"] as? [Any])?.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue } ?? []
        if !list.contains(id) { list.append(id) }
        self["totpSkip"] = list
    }
    /// 归档最新的月份并开始下个月（和网页 startNextMonth 一样）：
    /// 停止的不带过去；续费日期早于新月份的顺延；收款状态清零；代充单数清零。
    mutating func startNextMonth() {
        var months = dict("months")
        guard let last = months.keys.sorted().last else { return }
        let next = nextYM(last), floor = next + "-01"
        guard months[next] == nil else { return }
        var src = months.dict(last)
        var rows: JSON = [:]
        for sh in list("sheets") {
            let sid = sh.str("id"), mode = sh.str("mode")
            rows[sid] = src.dict("rows").list(sid).filter { !$0.bool("stopped") }.map { r -> JSON in
                var c = r
                c["id"] = uid()
                var renew = c.str("renew"), i = 0
                while i < 36 && parseISO(renew) != nil && renew < floor { renew = shiftMonth(renew, 1); i += 1 }
                c["renew"] = renew
                c["members"] = c.list("members").map { m -> JSON in var m = m; m["paid"] = false; return m }
                if mode == "resale" { c["count"] = 0 }
                return c
            }
        }
        src["archived"] = true
        months[last] = src
        months[next] = ["archived": false, "rows": rows]
        self["months"] = months
    }
    mutating func editList(_ key: String, _ f: (inout [JSON]) -> Void) {
        var l = list(key); f(&l); self[key] = l
    }
    /// 删除卡种 / 卡号后，所有月份里引用它的行改成「不指定」（和网页 normalize 一样）
    mutating func clearCardRefs() {
        let issuerIds = Set(list("issuers").map { $0.str("id") })
        editList("cards") { $0 = $0.filter { issuerIds.contains($0.str("issuerId")) } }
        let cardIssuer: [String: String] = [String: String](list("cards").map { ($0.str("id"), $0.str("issuerId")) }, uniquingKeysWith: { a, _ in a })
        var months = dict("months")
        for (ym, mv) in months {
            guard var M = mv as? JSON else { continue }
            var rows = M.dict("rows")
            for (sid, lv) in rows {
                guard let l = lv as? [JSON] else { continue }
                rows[sid] = l.map { r -> JSON in
                    var r = r
                    if !r.str("issuerId").isEmpty && !issuerIds.contains(r.str("issuerId")) { r["issuerId"] = ""; r["cardId"] = "" }
                    if !r.str("cardId").isEmpty && cardIssuer[r.str("cardId")] != r.str("issuerId") { r["cardId"] = "" }
                    return r
                }
            }
            M["rows"] = rows; months[ym] = M
        }
        self["months"] = months
    }
}

/// 新的一行（字段和网页 fixRow 一样齐全）
func newRow(account: String = "", group: String = "") -> JSON {
    ["id": uid(), "group": group, "account": account, "renew": "", "issuerId": "", "cardId": "", "totpId": 0,
     "members": [JSON](), "unitPrice": 0.0, "unitCost": 0.0, "count": 0.0, "cost": 0.0, "note": "", "stopped": false, "password": ""]
}

func newVps() -> JSON {
    ["id": uid(), "host": "", "site": "", "ip": "", "port": "", "password": "", "tags": [JSON](), "traffic": "", "renew": "",
     "price": "", "email": "", "loginPassword": ""]
}

// MARK: - 首页要用的汇总
enum LedgerRoute: Hashable { case sheet(String), cards, vps }

struct SheetInfo: Identifiable { let id: String; let name: String; let mode: String; let grouped: Bool; let rows: Int }
struct DueItem: Identifiable { let id: String; let days: Int; let title: String; let meta: String; let route: LedgerRoute }

extension LedgerStore {
    var monthTotal: Calc.Stats {
        var t = Calc.Stats()
        for sh in sheets where sh.str("mode") != "accounts" {
            let s = Calc.stats(sh.str("mode"), rows(latestMonth, sh.str("id")))
            t.n += s.n; t.heads += s.heads; t.income += s.income; t.cost += s.cost
        }
        return t
    }
    /// 被「只存账号」表认领的验证码分组：不再在 AI 合租里显示
    var visibleGroups: [LGroup] {
        let own = Set(sheets.filter { $0.str("mode") == "accounts" }.map { $0.str("totpGroup") }.filter { !$0.isEmpty })
        return groups.filter { !own.contains($0.name) }
    }
    var sheetInfo: [SheetInfo] {
        sheets.map { SheetInfo(id: $0.str("id"), name: $0.str("name"), mode: $0.str("mode"), grouped: $0.bool("grouped"), rows: rows(latestMonth, $0.str("id")).count) }
    }
    /// 待续费：账号 7 天内、VPS 30 天内（和网页总览一样）
    var due: [DueItem] {
        var out: [DueItem] = []
        let ym = latestMonth
        for sh in sheets {
            let sid = sh.str("id")
            for r in rows(ym, sid) where !r.bool("stopped") {
                guard let d = daysUntil(r.str("renew")), d <= 7 else { continue }
                let label = sh.bool("grouped") ? (group(r.str("group"))?.name ?? sh.str("name")) : sh.str("name")
                out.append(DueItem(id: r.str("id"), days: d, title: r.str("account").isEmpty ? "未填账号" : r.str("account"), meta: label, route: .sheet(sid)))
            }
        }
        for v in vps {
            guard let d = daysUntil(v.str("renew")), d <= 30 else { continue }
            out.append(DueItem(id: v.str("id"), days: d, title: v.str("host").isEmpty ? "未命名 VPS" : v.str("host"), meta: "VPS", route: .vps))
        }
        return out.sorted { $0.days < $1.days }
    }
}
