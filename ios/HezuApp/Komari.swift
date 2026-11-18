import SwiftUI

/// VPS 实时监控：数据来自用户自己的 Komari 探针（合租管理服务器转发 Komari 的公开接口）。
/// 每台节点的在线、CPU、内存、硬盘、流量、网速、延迟丢包；VPS 列表里按名字（或手动关联）对上节点。
@MainActor
final class KomariStore: ObservableObject {
    var api: API!
    @Published var nodes: [JSON] = []
    @Published var configured: Bool?
    @Published var url = ""
    @Published var error: String?

    func load() async {
        do {
            let d = try await api.get("/api/app/komari")
            configured = d.bool("configured"); url = d.str("url"); nodes = d.list("nodes"); error = nil
        } catch { self.error = error.localizedDescription }
    }

    func save(url: String) async throws {
        let d = try await api.post("/api/app/komari/config", ["url": url])
        configured = d.bool("configured"); self.url = d.str("url"); nodes = d.list("nodes"); error = nil
    }

    /// 这台 VPS 对应的节点：手动关联的优先，否则名字一样（或互相包含）且只对上一台
    func node(for v: JSON) -> JSON? {
        let manual = v.str("komari")
        if !manual.isEmpty { return nodes.first { $0.str("uuid") == manual } }
        let a = Self.norm(v.str("host")); guard a.count >= 3 else { return nil }
        let hits = nodes.filter { let b = Self.norm($0.str("name")); return b.count >= 3 && (a == b || a.contains(b) || b.contains(a)) }
        return hits.count == 1 ? hits[0] : nil
    }
    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    var online: Int { nodes.filter { $0.bool("online") }.count }
}

// MARK: 格式化
func fmtBytes(_ b: Double) -> String {
    var v = max(0, b); let u = ["B", "KB", "MB", "GB", "TB"]; var i = 0
    while v >= 1024 && i < u.count - 1 { v /= 1024; i += 1 }
    let s = i == 0 || v >= 100 ? String(format: "%.0f", v) : v >= 10 ? String(format: "%.1f", v) : String(format: "%.2f", v)
    return s + " " + u[i]
}
private func pct(_ a: Double, _ b: Double) -> Double { b > 0 ? min(100, a / b * 100) : 0 }
private func cycleText(_ c: Int) -> String {
    [30: "月", 31: "月", 90: "季", 92: "季", 180: "半年", 183: "半年", 365: "年", 730: "两年", 1095: "三年"][c] ?? (c > 0 ? "\(c) 天" : "")
}
extension JSON { func dbl(_ k: String) -> Double { num(self[k]) } }

/// 节点的底色：离线灰、CPU 很高或丢包严重红、正常青绿
func komariTint(_ n: JSON) -> Color {
    if !n.bool("online") { return .gray }
    if n.dbl("cpu") >= 90 || n.dict("ping").dbl("loss") >= 10 { return .bad }
    return Theme.codes
}

// MARK: 视图
/// 一条小进度条
struct KomariMeter: View {
    let label: String, percent: Double, main: String, sub: String
    var warnAt: Double = 90
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(main).monospacedDigit().fontWeight(.semibold) }.font(.caption)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(percent >= warnAt ? Color.bad : percent >= warnAt - 20 ? Color.orange : Color.good)
                        .frame(width: g.size.width * CGFloat(percent / 100))
                }
            }.frame(height: 5)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
        }
    }
}

/// 一台节点的卡片（和 Komari 首页的卡片同样的内容）
struct KomariCard: View {
    let n: JSON
    var body: some View {
        let online = n.bool("online"), ping = n.dict("ping")
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(online ? Color.good : Color.gray).frame(width: 8, height: 8)
                Text(n.str("name")).font(.body.weight(.semibold)).lineLimit(1)
                Text(n.str("region"))
                Spacer()
                if n.dbl("price") > 0 {
                    Text(n.str("currency") + plainNum(n.dbl("price")) + (cycleText(n.int("billingCycle")).isEmpty ? "" : " / " + cycleText(n.int("billingCycle"))))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Text(online ? "在线 \(Int(n.dbl("uptime") / 86400)) 天" : "离线")
                let exp = n.str("expiredAt")
                if !exp.hasPrefix("0001"), let d = daysUntil(String(exp.prefix(10))) {
                    Text(relText(d) + "到期").foregroundStyle(d < 0 ? Color.bad : d <= 30 ? Color.warn : .secondary)
                }
            }.font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 9) {
                KomariMeter(label: "CPU", percent: n.dbl("cpu"), main: String(format: "%.1f%%", n.dbl("cpu")),
                            sub: (n["load"] as? [Any] ?? []).map { String(format: "%.2f", num($0)) }.joined(separator: ", "))
                let ram = pct(n.dbl("ram"), n.dbl("ramTotal"))
                KomariMeter(label: "内存", percent: ram, main: String(format: "%.1f%%", ram), sub: fmtBytes(n.dbl("ram")) + " / " + fmtBytes(n.dbl("ramTotal")))
                let disk = pct(n.dbl("disk"), n.dbl("diskTotal"))
                KomariMeter(label: "硬盘", percent: disk, main: String(format: "%.1f%%", disk), sub: fmtBytes(n.dbl("disk")) + " / " + fmtBytes(n.dbl("diskTotal")))
                if n.dbl("trafficLimit") > 0 {
                    let t = pct(n.dbl("trafficUsed"), n.dbl("trafficLimit"))
                    KomariMeter(label: "流量", percent: t, main: String(format: "%.1f%%", t), sub: fmtBytes(n.dbl("trafficUsed")) + " / " + fmtBytes(n.dbl("trafficLimit")), warnAt: 80)
                } else {
                    KomariMeter(label: "流量", percent: 0, main: fmtBytes(n.dbl("totalUp") + n.dbl("totalDown")), sub: "没设上限")
                }
            }
            HStack(spacing: 10) {
                Text("↑ " + fmtBytes(n.dbl("netOut")) + "/s").foregroundStyle(Color.good)
                Text("↓ " + fmtBytes(n.dbl("netIn")) + "/s").foregroundStyle(.blue)
                Spacer()
                if !ping.isEmpty {
                    Text("\(Int(ping.dbl("latest"))) ms")
                    Text(String(format: "丢包 %.1f%%", ping.dbl("loss"))).foregroundStyle(ping.dbl("loss") >= 10 ? Color.bad : ping.dbl("loss") >= 3 ? Color.warn : Color.good)
                }
            }.font(.caption.monospacedDigit())
        }
        .padding(.vertical, 4)
        .opacity(online ? 1 : 0.7)
    }
}

/// VPS 列表里每台机器下面的一行小字：在线点 + CPU / 内存
struct KomariBadge: View {
    let n: JSON
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(n.bool("online") ? Color.good : Color.gray).frame(width: 6, height: 6)
            Text(n.bool("online") ? String(format: "CPU %.0f%% · 内存 %.0f%%", n.dbl("cpu"), pct(n.dbl("ram"), n.dbl("ramTotal"))) : "离线")
        }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
}

/// 「实时监控」页：顶部汇总 + 每台节点一张卡片；没接 Komari 时显示填网址
struct KomariSection: View {
    @EnvironmentObject var komari: KomariStore
    @EnvironmentObject var toast: Toast
    @State private var url = ""
    @State private var saving = false

    var body: some View {
        if komari.configured == false {
            Section {
                TextField("https://k.example.com", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(saving ? "正在连接…" : "连接 Komari") {
                    saving = true
                    Task { do { try await komari.save(url: url); toast.show("已连接") } catch { toast.show(error.localizedDescription) }; saving = false }
                }.disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            } header: { Text("接入 Komari 探针") } footer: { Text("只用 Komari 首页公开的数据，不需要账号密码。") }
        } else if komari.configured == nil {
            Section { HStack { ProgressView(); Text("正在读取 Komari…").foregroundStyle(.secondary) } }
        } else {
            let ns = komari.nodes
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(komari.online) / \(ns.count) 在线").font(.headline).foregroundStyle(komari.online == ns.count ? Color.good : Color.warn)
                        Text("累计流量 " + fmtBytes(ns.reduce(0) { $0 + $1.dbl("totalUp") + $1.dbl("totalDown") })).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("↑ " + fmtBytes(ns.reduce(0) { $0 + $1.dbl("netOut") }) + "/s").foregroundStyle(Color.good)
                        Text("↓ " + fmtBytes(ns.reduce(0) { $0 + $1.dbl("netIn") }) + "/s").foregroundStyle(.blue)
                    }.font(.subheadline.monospacedDigit())
                }
                .tintedRow(Theme.vps, bar: false)
                if let e = komari.error { Text(e).font(.caption).foregroundStyle(Color.bad) }
            } footer: { if let u = URL(string: komari.url), !komari.url.isEmpty { Link("打开 Komari：" + (u.host ?? komari.url), destination: u).font(.caption) } }
            Section {
                ForEach(ns.indices, id: \.self) { i in KomariCard(n: ns[i]).tintedRow(komariTint(ns[i])) }
            } footer: { Text("每 10 秒刷新一次。VPS 名字和 Komari 节点名字对得上的会自动关联，对不上的在 VPS 详情里手动选。") }
        }
    }
}
