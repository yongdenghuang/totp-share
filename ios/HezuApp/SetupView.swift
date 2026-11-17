import SwiftUI

/// 第一次打开：填后台的网址。地址只存在这台手机上，不写进代码里。
struct SetupView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var lock: AppLock
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            AppMark(size: 84)
            Text("合租管理").font(.title.weight(.semibold)).foregroundColor(.white)
            Text("填写你的后台网址，以后打开 App 就直接进入。")
                .foregroundColor(.white.opacity(0.65)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", text: $text, prompt: Text("例如 https://example.com").foregroundColor(.white.opacity(0.35)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit(connect)
                .padding(14)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.white)
            if let e = error {
                Text(e).font(.footnote).foregroundColor(Color(red: 1, green: 0.55, blue: 0.6))
            }
            Button(action: connect) {
                Text("连接").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
            }
            Spacer()
            Text("登录时勾选「记住这台设备」，30 天内打开不用再输密码。App 每次打开会先用面容 ID 解锁。")
                .font(.caption).foregroundColor(.white.opacity(0.45)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .onAppear { focused = true }
    }

    private func connect() {
        error = settings.setServer(text)
        if error == nil { lock.locked = false }   // 刚填完地址，不用马上再解锁一次
    }
}
