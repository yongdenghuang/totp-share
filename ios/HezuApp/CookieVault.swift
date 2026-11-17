import Foundation
import Security

/// 登录状态（后台「记住这台设备」发的 cookie）在钥匙串里另存一份。
/// WKWebView 自己也会存，但刚登录完就把 App 划掉时，它有时还没来得及写到磁盘，下次打开又要重新登录。
/// 只存带过期时间的 cookie（会话 cookie 本来就该关掉 App 就失效），只在这台手机上、解锁时可读。
enum CookieVault {
    private static let service = "com.hezu.manager.cookies"

    static func save(_ cookies: [HTTPCookie], for host: String) {
        let now = Date()
        let keep = cookies.filter { c in
            guard let exp = c.expiresDate, exp > now else { return false }
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            return d == host || host.hasSuffix("." + d)
        }
        guard !keep.isEmpty else { return clear(host) }      // 退出登录了：钥匙串里的也删掉
        let list: [[String: String]] = keep.map { c in
            var d = ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path,
                     "expires": String(c.expiresDate!.timeIntervalSince1970)]
            if c.isSecure { d["secure"] = "1" }
            if c.isHTTPOnly { d["httpOnly"] = "1" }
            if let s = c.sameSitePolicy { d["sameSite"] = s.rawValue }
            return d
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list) else { return }
        let query = base(host)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func load(for host: String) -> [HTTPCookie] {
        var query = base(host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        let now = Date()
        return list.compactMap { d in
            guard let name = d["name"], let value = d["value"], let domain = d["domain"],
                  let exp = Double(d["expires"] ?? ""), Date(timeIntervalSince1970: exp) > now else { return nil }
            var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain,
                                                   .path: d["path"] ?? "/", .expires: Date(timeIntervalSince1970: exp)]
            if d["secure"] == "1" { p[.secure] = "TRUE" }
            if d["httpOnly"] == "1" { p[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let s = d["sameSite"] { p[.sameSitePolicy] = s }
            return HTTPCookie(properties: p)
        }
    }

    static func clear(_ host: String) {
        SecItemDelete(base(host) as CFDictionary)
    }

    private static func base(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: host]
    }
}
