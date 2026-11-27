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
    @Published var adsDetails: [String: [JSON]] = [:] // 邮箱 → 每台设备 {name, ip, region, time}
    @Published var adsUpdated: Double = 0
    @Published private(set) var nav: JSON = [:]       // 左栏板块的顺序和名字（和网页共用，见 LedgerNav）
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
        if let n = d["navOrder"] as? JSON { nav = n }
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
        var det: [String: [JSON]] = [:]
        for (k, v) in d.dict("devices") { det[k] = (v as? [JSON]) ?? [] }
        adsDetails = det
        adsUpdated = (d["updated"] as? Double) ?? (d["updated"] as? NSNumber)?.doubleValue ?? 0
    }
    func adsDeviceList(_ account: String) -> [JSON] { adsDetails[account.trimmingCharacters(in: .whitespaces).lowercased()] ?? [] }
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
    mutating func unskipTotp(_ id: Int) {
        let list = (self["totpSkip"] as? [Any])?.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue } ?? []
        self["totpSkip"] = list.filter { $0 != id }
    }
    /// 分组表（AI 合租）自己的分组整体换掉；删掉的分组里、进行中月份的账号放到未分组
    mutating func setSheetGroups(id: String, groups: [JSON]) {
        var gone = Set<String>()
        editList("sheets") { l in
            guard let i = l.firstIndex(where: { $0.str("id") == id }) else { return }
            let keep = Set(groups.map { $0.str("id") })
            gone = Set(l[i].list("groups").map { $0.str("id") }).subtracting(keep)
            l[i]["groups"] = groups
        }
        guard !gone.isEmpty else { return }
        var months = dict("months")
        for (ym, mv) in months {
            guard var M = mv as? JSON, !M.bool("archived") else { continue }
            var rows = M.dict("rows")
            rows[id] = rows.list(id).map { r in var r = r; if gone.contains(r.str("group")) { r["group"] = "" }; return r }
            M["rows"] = rows; months[ym] = M
        }
        self["months"] = months
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
struct DueItem: Identifiable {
    let id: String; let days: Int; let title: String
    let meta: String                 // 类型：分组 / 表 / VPS（首页上做成带颜色的标签）
    var color: String = "#64748b"
    var detail: String = ""          // 续费卡、卡号 / VPS 标签
    let route: LedgerRoute
}
/// 普通表的标签颜色（和网页 SHEET_TINTS 一样，按表的顺序取）
let sheetTints = ["#7c3aed", "#dc2626", "#4f46e5", "#c026d3", "#0891b2", "#65a30d", "#d97706", "#e11d48", "#0f766e", "#475569"]

extension LedgerStore {
    var monthTotal: Calc.Stats {
        var t = Calc.Stats()
        for sh in sheets where sh.str("mode") != "accounts" {
            let s = Calc.stats(sh.str("mode"), rows(latestMonth, sh.str("id")))
            t.n += s.n; t.heads += s.heads; t.income += s.income; t.cost += s.cost
        }
        return t
    }
    /// 分组表（AI 合租）自己的分组（sheet.groups），和账号验证码的分组互不影响
    func sheetGroups(_ sheet: JSON) -> [LGroup] { sheet.list("groups").map { LGroup(id: $0.str("id"), name: $0.str("name"), color: $0.str("color")) } }
    func sheetGroup(_ sheet: JSON, _ id: String) -> LGroup? { sheetGroups(sheet).first { $0.id == id } }
    var sheetInfo: [SheetInfo] {
        sheets.map { SheetInfo(id: $0.str("id"), name: $0.str("name"), mode: $0.str("mode"), grouped: $0.bool("grouped"), rows: rows(latestMonth, $0.str("id")).count) }
    }
    /// 待续费：账号 7 天内、VPS 30 天内（和网页总览一样）
    var due: [DueItem] {
        var out: [DueItem] = []
        let ym = latestMonth
        for (si, sh) in sheets.enumerated() {
            let sid = sh.str("id")
            for r in rows(ym, sid) where !r.bool("stopped") {
                guard let d = daysUntil(r.str("renew")), d <= 7 else { continue }
                let g = sh.bool("grouped") ? sheetGroup(sh, r.str("group")) : nil
                let label = g?.name ?? (sh.bool("grouped") ? sh.str("name") + " · 未分组" : sh.str("name"))
                let color = g?.color ?? (sh.bool("grouped") ? "#8891a5" : sheetTints[si % sheetTints.count])
                let detail = [issuer(r.str("issuerId"))?.str("name") ?? "", card(r.str("cardId")).map { Calc.cardLabel($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                out.append(DueItem(id: r.str("id"), days: d, title: r.str("account").isEmpty ? "未填账号" : r.str("account"), meta: label, color: color, detail: detail, route: .sheet(sid)))
            }
        }
        for v in vps {
            guard let d = daysUntil(v.str("renew")), d <= 30 else { continue }
            let tags = (v["tags"] as? [Any] ?? []).compactMap { t -> String? in (t as? String) ?? ((t as? JSON)?.str("name")) }.filter { !$0.isEmpty }
            out.append(DueItem(id: v.str("id"), days: d, title: v.str("host").isEmpty ? "未命名 VPS" : v.str("host"), meta: "VPS", color: "#0f766e", detail: tags.joined(separator: "、"), route: .vps))
        }
        return out.sorted { $0.days < $1.days }
    }
}

// MARK: - 左栏板块（和网页左侧导航是同一份，存在服务器 nav_order 里）
/// 网页上的小项 id：表的 id、cards、vps、gpt、vault、notes、dashboard、logs、settings。App 里对应的模块 id：
/// 表是 sheet:<id>，dashboard 是 codes，其余一样。规则和 hezu.py 的 _resolve 一样：
/// 先按保存的位置放，剩下的固定页面回默认板块，剩下的表接在「账号」后面。
struct NavSection: Identifiable, Equatable { let id: String; let label: String; let items: [String] }

extension LedgerStore {
    static let navDefaults: [(id: String, label: String, items: [String])] = [
        ("accounts", "账号", []), ("backend", "后台", ["cards", "vps", "gpt"]),
        ("backup", "备份", ["vault", "notes"]), ("totp", "验证码", ["dashboard", "logs", "settings"])]
    private static let fixedWeb: Set<String> = ["cards", "vps", "gpt", "vault", "notes", "dashboard", "logs", "settings"]
    static func appID(_ web: String) -> String { web == "dashboard" ? "codes" : fixedWeb.contains(web) ? web : "sheet:" + web }
    static func webID(_ app: String) -> String { app == "codes" ? "dashboard" : app.hasPrefix("sheet:") ? String(app.dropFirst(6)) : app }

    var navSections: [NavSection] {
        var secs = ((nav["sections"] as? [String]) ?? []).filter { s in Self.navDefaults.contains { $0.id == s } }
        for d in Self.navDefaults where !secs.contains(d.id) { secs.append(d.id) }
        let items = nav.dict("items"), labels = nav.dict("labels")
        let sheetIDs = sheetInfo.map(\.id), sheetSet = Set(sheetIDs)
        var used = Set<String>(), place: [String: [String]] = [:]
        for s in secs {
            var lst: [String] = []
            for x in (items[s] as? [String]) ?? [] where (Self.fixedWeb.contains(x) || sheetSet.contains(x)) && !used.contains(x) { used.insert(x); lst.append(x) }
            place[s] = lst
        }
        for d in Self.navDefaults { for x in d.items where !used.contains(x) { used.insert(x); place[d.id, default: []].append(x) } }
        for x in sheetIDs where !used.contains(x) { place["accounts", default: []].append(x) }
        return secs.map { s in
            let custom = (labels[s] as? String) ?? ""
            return NavSection(id: s, label: custom.isEmpty ? Self.navDefaults.first { $0.id == s }!.label : custom,
                              items: (place[s] ?? []).map(Self.appID))
        }
    }
    func navSection(of appID: String) -> NavSection? { navSections.first { $0.items.contains(appID) } }

    /// 先在本地改（界面立刻变），再存到服务器；服务器回来的为准
    private func saveNav(_ body: JSON) async {
        var n = nav
        if let it = body["items"] as? [String: [String]] {
            var cur = n.dict("items")
            let moved = Set(it.values.flatMap { $0 })
            for (k, v) in cur where it[k] == nil { cur[k] = ((v as? [String]) ?? []).filter { !moved.contains($0) } }
            for (k, v) in it { cur[k] = v }
            n["items"] = cur
        }
        if let lb = body["labels"] as? [String: String] {
            var cur = n.dict("labels"); for (k, v) in lb { cur[k] = v }; n["labels"] = cur
        }
        if let c = body["collapsed"] as? [String] { n["collapsed"] = c }
        if let cl = body["colors"] as? [String: String] {
            var cur = n.dict("colors"); for (k, v) in cl { cur[k] = v }; n["colors"] = cur
        }
        if let nm = body["names"] as? [String: String] {
            var cur = n.dict("names"); for (k, v) in nm { cur[k] = v }; n["names"] = cur
        }
        nav = n
        do {
            let d = try await api.post("/admin/hezu/api/nav-order", body)
            if let o = d["navOrder"] as? JSON { nav = o }
        } catch {
            self.error = "左栏没保存上：" + error.localizedDescription
            await load()
        }
    }
    /// 某个板块里的新顺序（App 模块 id）
    func navSetOrder(_ sec: String, _ appIDs: [String]) async { await saveNav(["items": [sec: appIDs.map(Self.webID)]]) }
    /// 只动了能看见的那几项（放进「常用」的不在下面显示）：其余的留在原来的位置
    func navSetVisibleOrder(_ sec: String, visible: [String]) async {
        guard let full = navSections.first(where: { $0.id == sec })?.items else { return }
        var it = visible.makeIterator()
        let set = Set(visible)
        await navSetOrder(sec, full.map { set.contains($0) ? (it.next() ?? $0) : $0 })
    }
    /// 移到另一个板块的最后
    func navMove(_ appID: String, to sec: String) async {
        guard let t = navSections.first(where: { $0.id == sec }), !t.items.contains(appID) else { return }
        await navSetOrder(sec, t.items + [appID])
    }
    func navShift(_ appID: String, by delta: Int) async {
        guard let s = navSection(of: appID), let i = s.items.firstIndex(of: appID) else { return }
        let j = max(0, min(s.items.count - 1, i + delta)); guard j != i else { return }
        var o = s.items; o.swapAt(i, j)
        await navSetOrder(s.id, o)
    }
    /// 改名；留空恢复默认名字
    func navRename(_ sec: String, _ name: String) async {
        await saveNav(["labels": [sec: name.split(whereSeparator: \.isWhitespace).joined(separator: " ")]])
    }
    /// 板块颜色（和网页一样的几种），左栏的板块名用它
    static let navColorList: [(key: String, name: String, color: Color)] = [
        ("purple", "紫", Color(red: 0.55, green: 0.42, blue: 0.98)), ("blue", "蓝", Color(red: 0.23, green: 0.55, blue: 0.96)),
        ("teal", "青", Color(red: 0.05, green: 0.65, blue: 0.56)), ("amber", "橙", Color(red: 0.93, green: 0.6, blue: 0.05)),
        ("pink", "粉", Color(red: 0.91, green: 0.33, blue: 0.62)), ("green", "绿", Color(red: 0.33, green: 0.68, blue: 0.2)),
        ("red", "红", Color(red: 0.92, green: 0.33, blue: 0.33)), ("gray", "灰", Color(red: 0.5, green: 0.54, blue: 0.62))]
    private static let navDefaultColors = ["accounts": "purple", "backend": "blue", "backup": "amber", "totp": "teal"]
    func navColorKey(_ sec: String) -> String { (nav.dict("colors")[sec] as? String) ?? Self.navDefaultColors[sec] ?? "gray" }
    func navColor(_ sec: String) -> Color { Self.navColorList.first { $0.key == navColorKey(sec) }?.color ?? .secondary }
    func navSetColor(_ sec: String, _ key: String) async { await saveNav(["colors": [sec: key]]) }

    /// 折叠起来的板块（只显示板块名和数量，当前打开的那一项照样显示）。网页和 App 一起记住
    var navCollapsed: Set<String> { Set((nav["collapsed"] as? [String]) ?? []) }
    func navToggle(_ sec: String) async {
        var c = (nav["collapsed"] as? [String]) ?? []
        if let i = c.firstIndex(of: sec) { c.remove(at: i) } else { c.append(sec) }
        await saveNav(["collapsed": c])
    }
    /// 固定页面（支付卡、VPS…）改过的名字；没改过是 nil
    func navName(_ appID: String) -> String? {
        let v = (nav.dict("names")[Self.webID(appID)] as? String) ?? ""
        return v.isEmpty ? nil : v
    }
    /// 给左栏某一项改名：表改的是账本里表的名字；固定页面的名字存到服务器，留空恢复默认
    func navRenameItem(_ appID: String, _ name: String) async {
        let v = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if appID.hasPrefix("sheet:") {
            let sid = String(appID.dropFirst(6))
            guard !v.isEmpty, let mode = sheet(sid)?.str("mode") else { return }
            edit { $0.updateSheet(id: sid, name: String(v.prefix(40)), mode: mode) }
        } else {
            await saveNav(["names": [Self.webID(appID): String(v.prefix(20))]])
        }
    }
    /// 「表设置」里调整了表的顺序：每个板块里的表按新顺序排，别的小项不动
    func navApplySheetOrder(_ order: [String]) async {
        var items: [String: [String]] = [:]
        for s in navSections {
            let mine = order.map { "sheet:" + $0 }.filter { s.items.contains($0) }
            var it = mine.makeIterator()
            let o = s.items.map { $0.hasPrefix("sheet:") ? (it.next() ?? $0) : $0 }
            if o != s.items { items[s.id] = o.map(Self.webID) }
        }
        if !items.isEmpty { await saveNav(["items": items]) }
    }
}
