import Foundation

/// 和后台通信。App 和网页共用同一套登录会话（cookie）和防伪令牌：
/// 先 GET /api/app/session 拿令牌，之后的写操作都在 X-CSRFToken 头里带上。
/// cookie 存在系统的 HTTPCookieStorage（会写到磁盘），另外在钥匙串里备份一份，App 被划掉也不丢登录。
@MainActor
final class API: ObservableObject {
    enum Status: Equatable { case unknown, loggedOut, loggedIn(String) }

    @Published private(set) var status: Status = .unknown
    private(set) var base: URL
    private var csrf = ""
    private let session: URLSession

    init(base: URL) {
        self.base = base
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        if let host = base.host {
            for c in CookieVault.load(for: host) { HTTPCookieStorage.shared.setCookie(c) }
            #if DEBUG
            // 只在调试版里：模拟器自动化测试时用环境变量 HEZU_DEBUG_COOKIE=名称=值 直接带上登录状态
            if let raw = ProcessInfo.processInfo.environment["HEZU_DEBUG_COOKIE"], let eq = raw.firstIndex(of: "="),
               let c = HTTPCookie(properties: [.name: String(raw[..<eq]), .value: String(raw[raw.index(after: eq)...]),
                                               .domain: host, .path: "/", .expires: Date().addingTimeInterval(30 * 86400)]) {
                HTTPCookieStorage.shared.setCookie(c)
            }
            #endif
        }
    }

    var host: String { base.host ?? "" }

    func url(_ path: String) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }

    /// 打开 App / 回到前台时：问一下还登录着没有
    func refreshSession() async {
        do {
            let d = try await raw("GET", "/api/app/session", nil, retry: false)
            csrf = d["csrf"] as? String ?? csrf
            if d["loggedIn"] as? Bool == true {
                status = .loggedIn(d["user"] as? String ?? "")
            } else {
                status = .loggedOut
            }
            rememberCookies()
        } catch APIError.loggedOut {
            status = .loggedOut
        } catch {
            if status == .unknown { status = .loggedOut }
        }
    }

    func login(user: String, password: String) async throws {
        if csrf.isEmpty { await refreshSession() }
        let d = try await raw("POST", "/api/app/login", ["username": user, "password": password, "remember": true], retry: true, loginRequest: true)
        csrf = d["csrf"] as? String ?? csrf
        status = .loggedIn(d["user"] as? String ?? user)
        rememberCookies()
    }

    func logout() async {
        _ = try? await raw("POST", "/api/app/logout", [:], retry: true)
        for c in HTTPCookieStorage.shared.cookies(for: base) ?? [] { HTTPCookieStorage.shared.deleteCookie(c) }
        CookieVault.clear(host)
        status = .loggedOut
    }

    // MARK: - 通用请求

    func get(_ path: String) async throws -> [String: Any] { try await raw("GET", path, nil, retry: false) }
    func post(_ path: String, _ body: [String: Any] = [:]) async throws -> [String: Any] { try await raw("POST", path, body, retry: true) }
    func put(_ path: String, _ body: [String: Any]) async throws -> [String: Any] { try await raw("PUT", path, body, retry: true) }
    func delete(_ path: String) async throws -> [String: Any] { try await raw("DELETE", path, nil, retry: true) }

    /// 发请求，返回 JSON。登录过期抛 loggedOut；服务器说「不行」时抛 server(说明, 状态码, 返回内容)。
    private func raw(_ method: String, _ path: String, _ body: [String: Any]?, retry: Bool, loginRequest: Bool = false) async throws -> [String: Any] {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            req.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")   // 后台要求 https 写请求带同站 Referer
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let t = json["csrf"] as? String { csrf = t }
        if code == 401 && !loginRequest {
            status = .loggedOut
            throw APIError.loggedOut
        }
        if code == 400 && retry && json.isEmpty {
            // 防伪令牌过期（服务器返回的是 HTML 错误页）：换一个新的再试一次
            await refreshSession()
            return try await raw(method, path, body, retry: false, loginRequest: loginRequest)
        }
        if code >= 400 || json["ok"] as? Bool == false {
            throw APIError.server(json["error"] as? String ?? "出错了（\(code)）", code, json)
        }
        return json
    }

    func rememberCookies() {
        CookieVault.save(HTTPCookieStorage.shared.cookies(for: base) ?? [], for: host)
    }
}

enum APIError: LocalizedError {
    case loggedOut
    case server(String, Int, [String: Any])

    var errorDescription: String? {
        switch self {
        case .loggedOut: return "登录已过期，请重新登录"
        case .server(let m, _, _): return m
        }
    }

    var code: Int { if case .server(_, let c, _) = self { return c }; return 401 }
    var payload: [String: Any] { if case .server(_, _, let p) = self { return p }; return [:] }
}

// MARK: - JSON 小工具
extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String { (self[k] as? String) ?? (self[k].map { "\($0)" } ?? "") }
    func int(_ k: String) -> Int { (self[k] as? Int) ?? Int(self[k] as? String ?? "") ?? 0 }
    func bool(_ k: String) -> Bool { (self[k] as? Bool) ?? false }
    func dict(_ k: String) -> [String: Any] { (self[k] as? [String: Any]) ?? [:] }
    func list(_ k: String) -> [[String: Any]] { (self[k] as? [[String: Any]]) ?? [] }
}
