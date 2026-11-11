import AppKit
import WebKit

/// A normal window showing claude.ai's login page. It shares WebKit's default data store with
/// the hidden fetcher, so once the user signs in here the fetcher is signed in too.
final class LoginWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private let onDone: () -> Void
    private var finished = false

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
        webView.customUserAgent = safariUserAgent
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.t("Sign in to claude.ai for Slimey", "登录 claude.ai（给 Slimey 用）")
        window.contentView = webView
        window.isReleasedWhenClosed = false
        super.init()
        webView.navigationDelegate = self
        window.delegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    func present() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host == "claude.ai" else { return }
        // Leaving /login (e.g. landing on /new) means the session cookie is set.
        if !url.path.hasPrefix("/login") && !url.path.hasPrefix("/magic-link") {
            finish()
            window.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }
}
