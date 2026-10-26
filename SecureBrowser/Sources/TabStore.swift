import SwiftUI
import WebKit

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let isPrivate: Bool
    let webView: WKWebView
    @Published var title = "新しいタブ"
    @Published var urlString = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isLoading = false
    private var observers: [NSKeyValueObservation] = []

    init(isPrivate: Bool, blockPopups: Bool) {
        self.isPrivate = isPrivate
        let config = WKWebViewConfiguration()
        // プライベートモードは非永続データストア（Cookie/キャッシュをディスクに残さない）
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false  // JSによる自動ポップアップ禁止
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        if #available(iOS 14.5, *) { config.upgradeKnownHostsToHTTPS = true }
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        // window.open を同一タブ遷移に制限するスクリプト（ユーザー操作のないwindow.openは無効化）
        let js = """
        (function(){
          var last=0; ['click','touchend','keydown'].forEach(function(e){document.addEventListener(e,function(){last=Date.now();},true);});
          var orig=window.open;
          window.open=function(u,n,f){ if(Date.now()-last>1000){return null;} if(u){location.href=u;} return null; };
          try{ Object.defineProperty(navigator,'sendBeacon',{value:function(){return true;}}); }catch(e){}
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ContentBlocker.shared.apply(to: config.userContentController)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observers = [
            webView.observe(\.estimatedProgress) { [weak self] w, _ in Task { @MainActor in self?.progress = w.estimatedProgress } },
            webView.observe(\.title) { [weak self] w, _ in Task { @MainActor in if let t = w.title, !t.isEmpty { self?.title = t } } },
            webView.observe(\.url) { [weak self] w, _ in Task { @MainActor in self?.urlString = w.url?.absoluteString ?? "" } },
            webView.observe(\.canGoBack) { [weak self] w, _ in Task { @MainActor in self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] w, _ in Task { @MainActor in self?.canGoForward = w.canGoForward } },
            webView.observe(\.isLoading) { [weak self] w, _ in Task { @MainActor in self?.isLoading = w.isLoading } },
        ]
    }

    func load(input: String) {
        guard let url = Self.resolve(input) else { return }
        webView.load(URLRequest(url: url))
    }

    static func resolve(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.lowercased().hasPrefix("https://") { return URL(string: s) }
        if s.lowercased().hasPrefix("http://") { return URL(string: "https://" + s.dropFirst(7)) }
        if !s.contains(" "), s.contains("."), let u = URL(string: "https://" + s), u.host != nil { return u }
        var c = URLComponents(string: "https://duckduckgo.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: s), URLQueryItem(name: "kl", value: "jp-jp"), URLQueryItem(name: "kp", value: "-1")]
        return c.url
    }

    // MARK: Navigation — HTTP を HTTPS に昇格、未知スキームを遮断
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { decisionHandler(.cancel); return }
        if scheme == "http", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.scheme = "https"
            if let u = c.url { decisionHandler(.cancel); webView.load(URLRequest(url: u)); return }
        }
        if ["https", "about", "blob", "data"].contains(scheme) { decisionHandler(.allow); return }
        decisionHandler(.cancel) // tel:, itms-apps: などの外部アプリ起動は拒否
    }

    // MARK: Popups — 新規ウィンドウは作らず、ユーザー操作によるリンクのみ同じタブで開く
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.navigationType == .linkActivated, let url = action.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler() // アラートスパムを抑止
    }
}

@MainActor
final class TabStore: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var currentID: UUID?
    @Published var ready = false
    var current: BrowserTab? { tabs.first { $0.id == currentID } }

    func start() async {
        await ContentBlocker.shared.load()
        ready = true
        if tabs.isEmpty { newTab(isPrivate: false) }
    }
    func newTab(isPrivate: Bool) {
        let t = BrowserTab(isPrivate: isPrivate, blockPopups: true)
        tabs.append(t); currentID = t.id
    }
    func close(_ tab: BrowserTab) {
        tabs.removeAll { $0.id == tab.id }
        if currentID == tab.id { currentID = tabs.last?.id }
        if tabs.isEmpty { newTab(isPrivate: false) }
    }
    func clearAllData() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
    }
}
