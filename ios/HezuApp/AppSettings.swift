import Foundation

/// App 的设置都存在本机（UserDefaults）。服务器地址第一次打开时填；
/// 之后在系统「设置」App → 合租管理 里可以改地址、开关面容 ID、设置多久后重新上锁。
final class AppSettings: ObservableObject {
    static let serverKey = "server_url"
    static let lockKey = "lock_enabled"
    static let lockAfterKey = "lock_after"

    @Published private(set) var homeURL: URL?
    @Published private(set) var lockEnabled = true
    @Published private(set) var lockAfterSeconds: Double = 60

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [Self.lockKey: true, Self.lockAfterKey: "60"])
        reload()
    }

    func reload() {
        let home = Self.normalize(defaults.string(forKey: Self.serverKey) ?? "")
        if home != homeURL { homeURL = home }
        lockEnabled = defaults.bool(forKey: Self.lockKey)
        lockAfterSeconds = Double(defaults.string(forKey: Self.lockAfterKey) ?? "60") ?? 60
    }

    /// 保存服务器地址；地址不对时返回错误说明
    func setServer(_ text: String) -> String? {
        guard let url = Self.normalize(text) else {
            return "地址不对。请填后台的网址，比如 https://example.com"
        }
        defaults.set(url.scheme! + "://" + url.host! + (url.port.map { ":\($0)" } ?? ""), forKey: Self.serverKey)
        reload()
        return nil
    }

    /// 「example.com」→「https://example.com/admin/hezu」。只接受 https；本机调试（localhost）允许 http。
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard var parts = URLComponents(string: text), let host = parts.host, !host.isEmpty else { return nil }
        let local = host == "localhost" || host == "127.0.0.1"
        if parts.scheme?.lowercased() != "https" && !local { return nil }
        parts.path = "/admin/hezu"
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }
}
