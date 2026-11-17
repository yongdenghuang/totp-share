import SafariServices
import SwiftUI
import WebKit

/// App 里还没做成原生的页面（合租账本的表格、支付卡、VPS、设置……）：嵌一个网页进来。
/// 用 App 已登录的会话（把 cookie 交给网页），并隐藏网页自己的左侧导航——导航由 App 负责。
struct EmbeddedWeb: View {
    let path: String
    @EnvironmentObject var api: API
    @StateObject private var web = WebController()

    var body: some View {
        ZStack {
            WebViewHost(controller: web)
            if let err = web.loadError {
                ErrorBanner(message: err) { web.reload(home: api.url(path)) }.background(Color(.systemBackground))
            } else if !web.ready {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGroupedBackground))
            }
        }
        .task { web.open(api.url(path)) }
    }
}

struct WebViewHost: UIViewRepresentable {
    let controller: WebController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

@MainActor
final class WebController: NSObject, ObservableObject {
    @Published var loadError: String?
    @Published var ready = false        // 网页第一次画出来之前为 false
    let webView: WKWebView
    private var home: URL?
    fileprivate var pending: [ObjectIdentifier: URL] = [:]   // 正在下载的文件 → 存到哪里

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // 登录状态（记住这台设备）长期保存在手机上
        config.applicationNameForUserAgent = "Mobile/15E148 Safari/604.1 HezuApp/1.0"
        config.allowsInlineMediaPlayback = true
        config.dataDetectorTypes = []                 // 不要把账号、手机号自动变成链接
        // 点输入框时 iOS 会自动放大页面（字号小于 16 时），在 App 里看着像页面乱跳：禁止自动缩放
        config.userContentController.addUserScript(WKUserScript(source: """
            (function () {
              var m = document.querySelector('meta[name=viewport]');
              if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
              m.content = 'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover';
              // 导航由 App 负责：隐藏网页自己的左侧（手机上是顶部）导航
              var st = document.createElement('style');
              st.textContent = '.side{display:none!important}.shell{display:block!important}';
              document.head.appendChild(st);
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemGroupedBackground
        webView.scrollView.backgroundColor = .systemGroupedBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }   // Mac 上的 Safari 可以调试
        #endif
        let refresh = UIRefreshControl()
        refresh.tintColor = .gray
        refresh.addTarget(self, action: #selector(pulled(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func open(_ url: URL) {
        if home?.host == url.host && home?.port == url.port && webView.url != nil { return }
        home = url
        loadError = nil
        // App 原生部分登录用的 cookie（HTTPCookieStorage）交给网页，网页就不用再登录一次
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for c in cookies { group.enter(); store.setCookie(c) { group.leave() } }
        group.notify(queue: .main) { [weak self] in self?.webView.load(URLRequest(url: url)) }
    }

    func reload(home url: URL) {
        loadError = nil
        if webView.url == nil { webView.load(URLRequest(url: url)) } else { webView.reload() }
    }

    @objc private func pulled(_ sender: UIRefreshControl) {
        loadError = nil
        if webView.url == nil, let h = home { webView.load(URLRequest(url: h)) } else { webView.reload() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
    }

    fileprivate func isOwn(_ url: URL?) -> Bool {
        guard let url, let home else { return false }
        return url.host == home.host && url.port == home.port
    }

    fileprivate func openOutside(_ url: URL) {
        if url.scheme == "http" || url.scheme == "https" {
            // 官网、VPS 面板这些外部网址：在 App 里弹出 Safari 页面打开，看完一关就回来
            topController()?.present(SFSafariViewController(url: url), animated: true)
        } else {
            UIApplication.shared.open(url)            // mailto:、tel: 等交给系统
        }
    }

    fileprivate func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

// MARK: - 页面跳转
extension WebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if url.scheme == "blob" || url.scheme == "data" || url.scheme == "about" { return decisionHandler(.allow) }
        if !isOwn(url) && action.targetFrame?.isMainFrame != false {
            openOutside(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if !response.canShowMIMEType || disposition.lowercased().hasPrefix("attachment") {
            return decisionHandler(.download)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !ready { withAnimation(.easeOut(duration: 0.2)) { ready = true } }
        loadError = nil
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()   // 系统内存紧张时网页进程被回收：自动重新打开
    }

    private func showError(_ error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }   // 交给下载处理的跳转
        loadError = e.localizedDescription
        webView.scrollView.refreshControl?.endRefreshing()
    }
}

// MARK: - 新窗口、提示框
extension WebController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank：本站的在当前页面打开，外部网址用 Safari 页面打开
        if let url = action.request.url {
            if isOwn(url) { webView.load(action.request) } else { openOutside(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "知道了", style: .default) { _ in completionHandler() })
        present(a, or: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(a) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a) { completionHandler(nil) }
    }

    private func present(_ alert: UIAlertController, or fallback: @escaping () -> Void) {
        guard let top = topController() else { return fallback() }
        top.present(alert, animated: true)
    }
}

// MARK: - 下载（导出的 Excel、JSON 备份）：存到临时目录后弹出系统分享面板，可以存到「文件」或发给别人
extension WebController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)
        try? FileManager.default.removeItem(at: dest)
        pending[ObjectIdentifier(download)] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = pending.removeValue(forKey: ObjectIdentifier(download)), let top = topController() else { return }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {   // iPad 上要指定弹出位置
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pending.removeValue(forKey: ObjectIdentifier(download))
        let a = UIAlertController(title: "下载失败", message: error.localizedDescription, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "知道了", style: .default))
        topController()?.present(a, animated: true)
    }
}

