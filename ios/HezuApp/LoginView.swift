import SwiftUI

/// 原生登录页。登录后会话保持 30 天（每次使用顺延），和网页上勾「记住这台设备」一样。
struct LoginView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var settings: AppSettings
    @State private var user = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focus: Field?
    enum Field { case user, password }

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    AppMark(size: 80).padding(.top, 70)
                    Text("合租管理").font(.title.weight(.semibold)).foregroundColor(.white)
                    Text(api.host).font(.footnote).foregroundColor(.white.opacity(0.45))
                    VStack(spacing: 0) {
                        TextField("", text: $user, prompt: Text("用户名").foregroundColor(.white.opacity(0.35)))
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .user).submitLabel(.next).onSubmit { focus = .password }
                            .padding(14)
                        Divider().overlay(Color.white.opacity(0.12))
                        SecureField("", text: $password, prompt: Text("密码").foregroundColor(.white.opacity(0.35)))
                            .textContentType(.password).focused($focus, equals: .password)
                            .submitLabel(.go).onSubmit(submit)
                            .padding(14)
                    }
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 14)
                    if let error {
                        Text(error).font(.footnote).foregroundColor(Color(red: 1, green: 0.55, blue: 0.6))
                    }
                    Button(action: submit) {
                        Group { if busy { ProgressView().tint(.white) } else { Text("登录").font(.headline) } }
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundColor(.white)
                    }
                    .disabled(busy)
                    Text("登录后 30 天内打开都不用再输密码；打开 App 时先用面容 ID 解锁。")
                        .font(.caption).foregroundColor(.white.opacity(0.45)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { if user.isEmpty { focus = .user } }
    }

    private func submit() {
        guard !busy else { return }
        guard !user.isEmpty, !password.isEmpty else { error = "请填写用户名和密码"; return }
        busy = true; error = nil
        Task {
            do { try await api.login(user: user, password: password); password = "" }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
