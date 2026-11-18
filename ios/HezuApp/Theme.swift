import SwiftUI

/// 模块里每一项的浅色底：每一行变成一张单独的小卡片，用浅色打底、细边框和左边一条色条区分。
/// 颜色跟着内容走（分组色、类型色、状态色），整页再铺一层很淡的模块主色。
enum Theme {
    /// 区分用的一组颜色（备忘录、VPS、卡种这种本身没有颜色的，按名字固定取一个）
    static let palette: [Color] = ["#0d9488", "#ea580c", "#2563eb", "#db2777", "#7c3aed", "#16a34a",
                                   "#d97706", "#0891b2", "#dc2626", "#4f46e5", "#c026d3", "#65a30d"].map { Color(hex: $0) }
    /// 同一个字符串每次都得到同一个颜色（Swift 自带的 hashValue 每次启动都会变，不能用）
    static func pick(_ key: String) -> Color {
        var h: UInt32 = 5381
        for u in key.unicodeScalars { h = (h &* 33) &+ u.value }
        return palette[Int(h % UInt32(palette.count))]
    }
    static let codes = Color(hex: "#0d9488"), vault = Color(hex: "#ea580c"), notes = Color(hex: "#eab308")
    static let vps = Color(hex: "#2563eb"), cards = Color(hex: "#db2777"), gpt = Color(hex: "#16a34a")
}

private struct TintedRow: ViewModifier {
    let color: Color
    var bar: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content.listRowBackground(
            shape.fill(Color(.secondarySystemGroupedBackground))
                .overlay(shape.fill(color.opacity(scheme == .dark ? 0.16 : 0.08)))
                .overlay(shape.strokeBorder(color.opacity(scheme == .dark ? 0.35 : 0.2), lineWidth: 0.8))
                .overlay(alignment: .leading) {
                    if bar { Capsule().fill(color.opacity(0.85)).frame(width: 4).padding(.vertical, 12).padding(.leading, 6) }
                }
                .padding(.vertical, 3)
        )
        .listRowSeparator(.hidden)
    }
}

private struct ModuleBackground: ViewModifier {
    let color: Color
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background {
            LinearGradient(colors: [color.opacity(scheme == .dark ? 0.16 : 0.10), color.opacity(0.02)], startPoint: .top, endPoint: .center)
                .background(Color(.systemGroupedBackground))
                .ignoresSafeArea()
        }
    }
}

extension View {
    /// 列表里的一行：浅色打底的独立小卡片；bar 为 true 时左边加一条色条
    func tintedRow(_ color: Color, bar: Bool = true) -> some View { modifier(TintedRow(color: color, bar: bar)) }
    /// 整页铺一层很淡的模块主色
    func moduleBackground(_ color: Color) -> some View { modifier(ModuleBackground(color: color)) }
}
