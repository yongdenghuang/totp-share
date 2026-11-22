import SwiftUI

/// GPT 账号：数据来自用户自己的 sub2api（合租管理服务器转发，Key 不在手机上）。
/// 显示每个账号的智商状态（最近一次糖果题）、5 小时 / 7 天额度；可以授权登录新账号、立即测试、定期测试。
@MainActor
final class GPTStore: ObservableObject {
    var api: API!
    @Published var accounts: [JSON] = []
    @Published var configured: Bool?
    @Published var url = ""
    @Published var plan: JSON = [:]
    @Published var error: String?
    @Published var loaded = false
    @Published var runID: Int?
    @Published var run: JSON = [:]

    func load() async {
        do {
            let c = try await api.get("/api/app/gpt/config")
            url = c.str("url")
            configured = !url.isEmpty && c.bool("hasKey")
            guard configured == true else { loaded = true; return }
            async let a = api.get("/api/app/gpt/accounts")
            async let p = api.get("/api/app/gpt/plan")
            accounts = try await a.list("accounts")
            plan = (try? await p.dict("plan")) ?? [:]
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    func testAll(_ ids: [Int] = []) async throws {
        let d = try await api.post("/api/app/gpt/test", ["account_ids": ids])
        runID = d.int("runId"); run = ["status": "running"]
        Task { await pollRun() }
    }

    private func pollRun() async {
        while let id = runID {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let d = try? await api.get("/api/app/gpt/runs/\(id)") else { continue }
            run = d.dict("run")
            if run.str("status") != "running" { runID = nil; await load() }
        }
    }

    var counts: (ok: Int, bad: Int, unknown: Int) {
        var o = 0, b = 0, u = 0
        for a in accounts { switch a.dict("iq").str("label") { case "正常": o += 1; case "降智": b += 1; default: u += 1 } }
        return (o, b, u)
    }
}

func iqColor(_ label: String) -> Color { label == "正常" ? .good : label == "降智" ? .bad : .gray }

/// ISO 时间 → 「3 小时 12 分后」
func untilText(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let f2 = ISO8601DateFormatter()
    guard let d = f.date(from: iso) ?? f2.date(from: iso) else { return "" }
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return "已重置" }
    let h = s / 3600, m = (s % 3600) / 60
    return h >= 24 ? "\(h / 24) 天 \(h % 24) 小时后重置" : h > 0 ? "\(h) 小时 \(m) 分后重置" : "\(max(1, m)) 分钟后重置"
}

func shortTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
    let o = DateFormatter(); o.dateFormat = "MM-dd HH:mm"; o.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return o.string(from: d)
}

struct GPTView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var store: GPTStore
    @EnvironmentObject var toast: Toast
    @State private var adding = false
    @State private var showConfig = false
    @State private var filter = ""
    @State private var minutesText = ""
    @FocusState private var minutesFocused: Bool

    var body: some View {
        Group {
            if store.configured == false { GPTSetupView(done: { Task { await store.load() } }) }
            else { list }
        }
        .navigationTitle("GPT 账号")
        .task { store.api = api; if !store.loaded { await store.load() } }
        .sheet(isPresented: $adding, onDismiss: { Task { await store.load() } }) { GPTAuthSheet() }
        .sheet(isPresented: $showConfig, onDismiss: { Task { await store.load() } }) { NavigationStack { GPTSetupView(done: { showConfig = false }) } }
    }

    private var list: some View {
        List {
            Section { header }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section { planRow.tintedRow(Theme.gpt, bar: false) }
            Section {
                ForEach(shown, id: \.idKey) { a in
                    NavigationLink { GPTDetail(id: a.int("id")) } label: { GPTRow(a: a) }
                        .tintedRow(iqColor(a.dict("iq").str("label")))
                }
                if store.loaded && store.accounts.isEmpty { Text("sub2api 里还没有 GPT 账号，点右上角 ＋ 授权登录。").foregroundStyle(.secondary) }
            } header: { Text("账号") } footer: { Text("智商状态看最近一次糖果题：答对是「正常」，答错是「降智」，请求失败或还没测是「待确认」。连续答错 3 次会被标记。") }
            if let e = store.error { ErrorBanner(message: e) { Task { await store.load() } } }
        }
        .listStyle(.insetGrouped)
        .moduleBackground(Theme.gpt)
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") } }
            ToolbarItem(placement: .navigationBarLeading) { Button { showConfig = true } label: { Image(systemName: "gearshape") } }
        }
    }

    private var shown: [JSON] {
        let order = ["降智": 0, "待确认": 1, "正常": 2]
        return store.accounts.filter { filter.isEmpty || $0.dict("iq").str("label") == filter }
            .sorted { (order[$0.dict("iq").str("label")] ?? 3, $0.str("name")) < (order[$1.dict("iq").str("label")] ?? 3, $1.str("name")) }
    }

    private var header: some View {
        let c = store.counts
        return HStack(spacing: 10) {
            countBox("正常", c.ok, .good)
            countBox("降智", c.bad, .bad)
            countBox("待确认", c.unknown, .gray)
        }.padding(.horizontal, 16).padding(.top, 4)
    }

    private func countBox(_ k: String, _ n: Int, _ color: Color) -> some View {
        Button { filter = filter == k ? "" : k } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(k).font(.caption).foregroundStyle(color)
                Text("\(n)").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(filter == k ? 0.22 : 0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(filter == k ? color : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    private var planRow: some View {
        Group {
            Toggle(isOn: Binding(get: { store.plan.bool("enabled") }, set: { on in savePlan(on, store.plan.int("intervalMinutes")) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("定期智商测试")
                    if store.plan.bool("enabled"), !store.plan.str("nextRunAt").isEmpty {
                        Text("下次 \(shortTime(store.plan.str("nextRunAt")))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.plan.bool("enabled") {
                // 间隔自己填多少分钟，填完点键盘上的完成或「保存」
                HStack {
                    Text("每")
                    TextField("分钟", text: $minutesText)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(maxWidth: 90).textFieldStyle(.roundedBorder)
                        .focused($minutesFocused)
                        .onSubmit(saveMinutes)
                    Text("分钟")
                    Spacer()
                    if minutesText != String(currentMinutes) {
                        Button("保存", action: saveMinutes).buttonStyle(.borderless)
                    }
                }
                .onAppear { minutesText = String(currentMinutes) }
                .onChange(of: store.plan.int("intervalMinutes")) { _ in if !minutesFocused { minutesText = String(currentMinutes) } }
            }
            Button {
                Task { do { try await store.testAll(); toast.show("已开始测试全部账号") } catch { toast.show(error.localizedDescription) } }
            } label: {
                HStack {
                    Label("立即测试全部账号", systemImage: "play.circle")
                    Spacer()
                    if store.runID != nil {
                        ProgressView()
                        Text("\(store.run.int("pass") + store.run.int("quality_fail") + store.run.int("infra_error") + store.run.int("skipped"))/\(store.run.int("accounts"))").font(.caption).monospacedDigit()
                    }
                }
            }.disabled(store.runID != nil)
        }
    }

    private var currentMinutes: Int { store.plan.int("intervalMinutes") == 0 ? 360 : store.plan.int("intervalMinutes") }
    private func saveMinutes() {
        minutesFocused = false
        guard let m = Int(minutesText.trimmingCharacters(in: .whitespaces)), m >= 1 else {
            minutesText = String(currentMinutes); toast.show("间隔至少 1 分钟"); return
        }
        if m != currentMinutes { savePlan(true, m) }
    }

    private func savePlan(_ on: Bool, _ minutes: Int) {
        Task {
            do { store.plan = try await api.post("/api/app/gpt/plan", ["enabled": on, "intervalMinutes": minutes == 0 ? 360 : minutes]).dict("plan"); toast.show(on ? "已开启定期测试" : "已关闭定期测试") }
            catch { toast.show(error.localizedDescription) }
        }
    }
}

/// 列表里的一个账号
struct GPTRow: View {
    let a: JSON
    var body: some View {
        let iq = a.dict("iq")
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(a.str("name").isEmpty ? a.str("email") : a.str("name")).font(.body.weight(.semibold)).lineLimit(1)
                if !a.str("plan").isEmpty { Tag(text: a.str("plan"), color: .brand) }
                Spacer()
                Tag(text: iq.str("label") + (iq.int("consecutiveFails") > 1 && iq.str("label") == "降智" ? " ×\(iq.int("consecutiveFails"))" : ""), color: iqColor(iq.str("label")))
            }
            if a.str("email") != a.str("name") && !a.str("email").isEmpty { Text(a.str("email")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack(spacing: 10) {
                QuotaBar(label: "5h", w: a.dict("fiveHour"), color: .brand)
                QuotaBar(label: "7d", w: a.dict("sevenDay"), color: .good)
            }
            HStack(spacing: 6) {
                RecentDots(recent: iq["recent"] as? [Bool] ?? [])
                ResetTag(r: a.dict("resets"))
                Spacer()
                if a.str("status") == "error" { Text("出错").font(.caption.weight(.semibold)).foregroundStyle(Color.bad) }
                else if !a.bool("schedulable") { Text("已暂停调度").font(.caption).foregroundStyle(Color.warn) }
                else if !a.str("rateLimitResetAt").isEmpty, untilText(a.str("rateLimitResetAt")) != "已重置" { Text("限流中").font(.caption).foregroundStyle(Color.warn) }
            }
        }.padding(.vertical, 3)
    }
}

/// 重置次数（sub2api 刷新额度时记下来的）
struct ResetTag: View {
    let r: JSON
    var body: some View {
        if r.isEmpty { EmptyView() }
        else if !r.bool("known") { Text("重置 ?").font(.caption).foregroundStyle(.tertiary) }
        else if r.int("available") == 0 { Text("没有重置次数").font(.caption).foregroundStyle(.secondary) }
        else {
            let first = (r["expiresAt"] as? [String])?.first.map { " · " + monthDay($0) + " 到期" } ?? ""
            Tag(text: "重置 \(r.int("available")) 次" + first + (r.bool("auto") ? " · 自动" : ""), color: .brand)
        }
    }
}

func monthDay(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let d else { return "" }
    let c = Calendar.current.dateComponents([.month, .day], from: d)
    return "\(c.month ?? 0)-\(c.day ?? 0)"
}

func resetDetail(_ r: JSON) -> String {
    guard r.bool("known") else { return "还没刷新过，点下面的「刷新额度」" }
    let exp = (r["expiresAt"] as? [String] ?? []).map { monthDay($0) + " 到期" }
    return "\(r.int("available")) 次" + (exp.isEmpty ? "" : "（" + exp.joined(separator: "、") + "）") + (r.bool("auto") ? " · 自动重置" : "")
}

struct QuotaBar: View {
    let label: String
    let w: JSON
    let color: Color
    var body: some View {
        let used = w["used"] as? Double ?? (w["used"] as? NSNumber)?.doubleValue
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(used.map { "\(Int($0.rounded()))%" } ?? "—").font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle((used ?? 0) >= 90 ? Color.bad : .primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill((used ?? 0) >= 90 ? Color.bad : color).frame(width: g.size.width * CGFloat(min(100, max(0, used ?? 0)) / 100))
                }
            }.frame(height: 5)
            Text(w.str("resetAt").isEmpty ? " " : untilText(w.str("resetAt"))).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
}

struct RecentDots: View {
    let recent: [Bool]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(recent.suffix(8).enumerated()), id: \.offset) { _, ok in
                RoundedRectangle(cornerRadius: 2).fill(ok ? Color.good : Color.bad).frame(width: 9, height: 9)
            }
            if recent.isEmpty { Text("还没测过").font(.caption2).foregroundStyle(.tertiary) }
        }
    }
}

/// 一个账号的详情：额度、测试记录、操作
struct GPTDetail: View {
    let id: Int
    @EnvironmentObject var api: API
    @EnvironmentObject var store: GPTStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @State private var results: [JSON] = []
    @State private var quota: JSON?
    @State private var busy = ""
    @State private var confirmDelete = false

    private var a: JSON { store.accounts.first { $0.int("id") == id } ?? [:] }

    var body: some View {
        List {
            Section {
                row("账号", a.str("email"))
                row("名称", a.str("name"))
                row("套餐", a.str("plan"))
                if !a.str("subscriptionExpiresAt").isEmpty { row("订阅到期", shortTime(a.str("subscriptionExpiresAt"))) }
                row("状态", a.str("status") == "error" ? "出错：\(a.str("error"))" : a.bool("schedulable") ? "正常调度" : "已暂停调度")
                if !a.str("lastUsedAt").isEmpty { row("最近使用", shortTime(a.str("lastUsedAt"))) }
                if !a.str("privacy").isEmpty { row("训练数据", a.str("privacy") == "training_off" ? "已关闭" : a.str("privacy")) }
            }
            Section {
                HStack(spacing: 12) {
                    QuotaBar(label: "5 小时", w: a.dict("fiveHour"), color: .brand)
                    QuotaBar(label: "7 天", w: a.dict("sevenDay"), color: .good)
                }.padding(.vertical, 4)
                row("重置次数", resetDetail(a.dict("resets")))
                if let q = quota {
                    let cr = q.dict("credits")
                    row("点数余额", cr.bool("unlimited") ? "无限" : cr.str("balance").isEmpty ? "—" : cr.str("balance"))
                    row("当前可用", q.dict("rate_limit").bool("limit_reached") ? "已到上限" : "可以使用")
                }
                Button { act("quota") { quota = try await api.get("/api/app/gpt/accounts/\(id)/quota").dict("quota"); await store.load() } } label: {
                    HStack { Label("刷新额度", systemImage: "arrow.clockwise"); Spacer(); if busy == "quota" { ProgressView() } }
                }
            } header: { Text("额度") } footer: { Text(a.str("usageUpdatedAt").isEmpty ? "" : "额度观测于 \(shortTime(a.str("usageUpdatedAt")))") }
            Section {
                Button { act("test") { try await store.testAll([id]); toast.show("已开始测试，稍后刷新查看") } } label: {
                    HStack { Label("测一次智商", systemImage: "brain.head.profile"); Spacer(); if busy == "test" { ProgressView() } }
                }
                Toggle("参与调度", isOn: Binding(get: { a.bool("schedulable") }, set: { on in act("sched") { _ = try await api.post("/api/app/gpt/accounts/\(id)/schedulable", ["schedulable": on]); await store.load() } }))
                Button("删除这个账号", role: .destructive) { confirmDelete = true }
            }
            Section {
                ForEach(results, id: \.idKey) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let o = r.str("outcome")
                            Tag(text: o == "pass" ? "答对" : o == "quality_fail" ? "答错" : o == "skipped" ? "跳过" : "请求失败", color: o == "pass" ? .good : o == "quality_fail" ? .bad : .gray)
                            Text(r.str("model")).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Text(shortTime(r.str("created_at"))).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            if !r.str("reason").isEmpty { Text(r.str("reason")).font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            if r.int("duration_ms") > 0 { Text(String(format: "%.1f 秒", Double(r.int("duration_ms")) / 1000)).font(.caption2).foregroundStyle(.tertiary) }
                        }
                        if !r.str("detail").isEmpty { Text(r.str("detail")).font(.caption2).foregroundStyle(.tertiary).lineLimit(2) }
                    }
                }
                if results.isEmpty { Text("还没有测试记录").foregroundStyle(.secondary) }
            } header: { Text("智商测试记录（糖果题，正确答案 21）") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(a.str("name").isEmpty ? "GPT 账号" : a.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadResults(); await store.load() }
        .task { await loadResults() }
        .alert("删除这个 GPT 账号？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { act("del") { _ = try await api.delete("/api/app/gpt/accounts/\(id)"); await store.load(); dismiss() } }
        } message: { Text("会从 sub2api 里删除这个账号，不能恢复。") }
    }

    private func loadResults() async { results = (try? await api.get("/api/app/gpt/accounts/\(id)/results").list("results")) ?? results }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v.isEmpty ? "—" : v).multilineTextAlignment(.trailing) }
            .contentShape(Rectangle())
            .onTapGesture { if !v.isEmpty { toast.copy(v, "已复制\(k)") } }
    }

    private func act(_ name: String, _ f: @escaping () async throws -> Void) {
        busy = name
        Task { do { try await f() } catch { toast.show(error.localizedDescription) }; busy = "" }
    }
}

/// 授权登录一个新的 GPT 账号（Codex OAuth，和 sub2api 后台的「添加账号」一样）
struct GPTAuthSheet: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var authURL = ""
    @State private var session = ""
    @State private var callback = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        busy = true
                        Task {
                            do {
                                let d = try await api.post("/api/app/gpt/oauth/start")
                                authURL = d.str("authUrl"); session = d.str("sessionId")
                                if let u = URL(string: authURL) { openURL(u) }
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: { Label(authURL.isEmpty ? "1. 打开授权页面" : "重新打开授权页面", systemImage: "safari") }
                    if !authURL.isEmpty { Button("复制授权链接") { toast.copy(authURL, "已复制授权链接") } }
                } footer: { Text("会在 Safari 里打开 OpenAI 的登录页，用要添加的 GPT 账号登录并同意授权。链接 30 分钟内有效。") }
                Section {
                    TextField("http://localhost:1455/auth/callback?code=…", text: $callback, axis: .vertical)
                        .font(.footnote.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...5)
                    Button("从剪贴板粘贴") { callback = UIPasteboard.general.string ?? callback }
                    TextField("名称（可不填，默认用邮箱）", text: $name)
                } header: { Text("2. 粘贴跳转后的地址") } footer: {
                    Text("登录完 Safari 会跳到一个 http://localhost 开头、打不开的页面，这是正常的：点地址栏，把整个地址复制过来粘贴到这里。")
                }
                if let error { Text(error).foregroundStyle(Color.bad) }
            }
            .navigationTitle("授权登录 GPT").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        busy = true; error = nil
                        Task {
                            do {
                                let d = try await api.post("/api/app/gpt/oauth/finish", ["sessionId": session, "callback": callback, "name": name])
                                toast.show("已添加 \(d.dict("account").str("email"))"); dismiss()
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }.disabled(busy || session.isEmpty || callback.isEmpty)
                }
            }
        }
    }
}

/// 第一次用：填 sub2api 的地址和管理员 API Key
struct GPTSetupView: View {
    var done: () -> Void
    @EnvironmentObject var api: API
    @EnvironmentObject var toast: Toast
    @State private var url = ""
    @State private var key = ""
    @State private var hasKey = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("sub2api 地址，如 https://api.example.com", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField(hasKey ? "管理员 API Key（不改就留空）" : "管理员 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("连接 sub2api") } footer: {
                Text("GPT 账号、额度和智商测试都在你自己的 sub2api 里，合租管理只是读取和操作。\n\nKey 在 sub2api 后台创建：系统设置 → 安全与认证 → 管理员访问密钥 → 创建管理密钥，并勾选「全权访问」（不勾选的话读不到智商测试，也不能授权登录）。Key 只显示一次。\n\nKey 加密保存在合租管理服务器上，不会存在手机里。")
            }
            if let error { Text(error).foregroundStyle(Color.bad) }
            Button {
                busy = true; error = nil
                Task {
                    do {
                        var b: JSON = ["url": url]; if !key.isEmpty { b["key"] = key }
                        _ = try await api.post("/api/app/gpt/config", b)
                        toast.show("已连接 sub2api"); key = ""; done()
                    } catch { self.error = error.localizedDescription }
                    busy = false
                }
            } label: { HStack { Text("保存并连接"); if busy { Spacer(); ProgressView() } } }
                .disabled(busy || url.isEmpty || (key.isEmpty && !hasKey))
        }
        .navigationTitle("连接 sub2api")
        .task { if let c = try? await api.get("/api/app/gpt/config") { url = c.str("url"); hasKey = c.bool("hasKey") } }
    }
}
