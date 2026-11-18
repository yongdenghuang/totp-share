import SwiftUI

/// GPT 账号（OAuth 授权、额度、定期智商测试）。下一步按 sub2api 的做法实现，这里先占位。
@MainActor
final class GPTStore: ObservableObject {
    var api: API!
    @Published var accounts: [JSON] = []
}

struct GPTView: View {
    var body: some View {
        ContentUnavailableCompat(title: "GPT 账号", message: "正在开发：授权登录、额度、定期智商测试。")
            .navigationTitle("GPT 账号")
    }
}

struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain.head.profile").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
