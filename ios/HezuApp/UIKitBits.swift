import SwiftUI
import UIKit

// MARK: - 配色（和网页一致）
extension Color {
    static let brand = Color(red: 0.31, green: 0.275, blue: 0.898)          // #4f46e5
    static let good = Color(red: 0.04, green: 0.52, blue: 0.35)
    static let bad = Color(red: 0.83, green: 0.18, blue: 0.30)
    static let warn = Color(red: 0.68, green: 0.37, blue: 0.01)

    init(hex: String, fallback: Color = .gray) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = fallback; return }
        self = Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// MARK: - 「已复制」提示
@MainActor
final class Toast: ObservableObject {
    @Published var text: String?
    private var task: Task<Void, Never>?

    func show(_ t: String) {
        text = t
        task?.cancel()
        task = Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if !Task.isCancelled { text = nil } }
    }

    /// 复制到剪贴板（10 分钟后系统自动清掉，只在本机，不同步到其他设备）
    func copy(_ value: String, _ label: String = "已复制") {
        guard !value.isEmpty else { return show("没有内容可复制") }
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        show(label)
    }
}

struct ToastView: View {
    @EnvironmentObject var toast: Toast
    var body: some View {
        VStack {
            Spacer()
            if let t = toast.text {
                Text(t).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 90)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toast.text)
        .allowsHitTesting(false)
    }
}

// MARK: - 分组 / 类型的小标签
struct Tag: View {
    let text: String
    var color: Color = .gray
    var body: some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 出错提示（服务器返回的说明）
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.secondary)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry { Button("重试", action: retry).buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity).padding(32)
    }
}

/// 金额显示：¥1,186 / -¥20.5
func money(_ v: Double) -> String {
    let r = (v * 100).rounded() / 100
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = r == r.rounded() ? 0 : 2
    f.minimumFractionDigits = 0
    return (r < 0 ? "-¥" : "¥") + (f.string(from: NSNumber(value: abs(r))) ?? "\(abs(r))")
}

func num(_ v: Any?) -> Double {
    if let d = v as? Double { return d.isFinite ? d : 0 }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "").trimmingCharacters(in: .whitespaces)) ?? 0 }
    return 0
}
