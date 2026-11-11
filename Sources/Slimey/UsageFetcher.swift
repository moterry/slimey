import AppKit
import WebKit

enum FetchState {
    case loading
    case ok(UsageSnapshot)
    case needsLogin(UsageSnapshot?)
    case failed(String, UsageSnapshot?)
}

/// Safari's UA: some sign-in providers refuse WKWebView's default one.
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

/// Keeps a hidden claude.ai page open and polls claude.ai's own usage API from it,
/// so requests carry the session the user logged into (cookies never leave WebKit).
final class UsageFetcher: NSObject, WKNavigationDelegate {
    var onUpdate: (FetchState) -> Void = { _ in }

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var pollTimer: Timer?
    private var pageReady = false
    private var pageLoadedAt = Date.distantPast
    private var lastSnapshot: UsageSnapshot?
    private var inFlight = false
    private var loginWindow: LoginWindow?

    /// A tiny same-origin JSON page: gives the web view a claude.ai origin to fetch from
    /// without keeping the whole claude.ai app loaded in memory.
    static let home = URL(string: "https://claude.ai/api/organizations")!
    static let pollInterval: TimeInterval = 60
    static let pageMaxAge: TimeInterval = 30 * 60

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.customUserAgent = safariUserAgent
        // WebKit throttles views that aren't in a window, so park it in an invisible one.
        hostWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        hostWindow.alphaValue = 0
        hostWindow.ignoresMouseEvents = true
        hostWindow.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        onUpdate(.loading)
        loadPage()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        if !pageReady || Date().timeIntervalSince(pageLoadedAt) > Self.pageMaxAge {
            loadPage()
        } else {
            poll()
        }
    }

    func showLogin() {
        if loginWindow == nil {
            loginWindow = LoginWindow { [weak self] in
                self?.loginWindow = nil
                self?.loadPage()
            }
        }
        loginWindow?.present()
    }

    private func loadPage() {
        pageReady = false
        webView.load(URLRequest(url: Self.home))
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        if url.path.hasPrefix("/login") {
            onUpdate(.needsLogin(lastSnapshot))
            return
        }
        pageReady = true
        pageLoadedAt = Date()
        poll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onUpdate(.failed(L10n.t("Page failed to load: ", "页面加载失败：") + error.localizedDescription, lastSnapshot))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onUpdate(.failed(L10n.t("Can't reach claude.ai: ", "连不上 claude.ai：") + error.localizedDescription, lastSnapshot))
    }

    // MARK: Polling

    private static let fetchScript = """
    const get = async (path) => {
        const r = await fetch(path, { credentials: 'include', headers: { 'accept': 'application/json' } });
        return { status: r.status, body: await r.text() };
    };
    const orgs = await get('/api/organizations');
    if (orgs.status !== 200) return { stage: 'orgs', status: orgs.status };
    let list;
    try { list = JSON.parse(orgs.body); } catch (e) { return { stage: 'orgs', status: -1 }; }
    const org = list.find(o => (o.capabilities || []).includes('chat')) || list[0];
    if (!org) return { stage: 'orgs', status: -2 };
    const usage = await get(`/api/organizations/${org.uuid}/usage?cedar_ember=1&skip_spend=1`);
    return { stage: 'usage', status: usage.status, usage: usage.body, orgId: org.uuid };
    """

    private func poll() {
        guard pageReady, !inFlight else { return }
        inFlight = true
        webView.callAsyncJavaScript(Self.fetchScript, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            self.inFlight = false
            switch result {
            case .failure(let error):
                self.onUpdate(.failed(L10n.t("Script error: ", "脚本出错：") + error.localizedDescription, self.lastSnapshot))
            case .success(let value):
                self.handle(value as? [String: Any] ?? [:])
            }
        }
    }

    private func handle(_ result: [String: Any]) {
        let status = (result["status"] as? NSNumber)?.intValue ?? 0
        let stage = result["stage"] as? String ?? "?"
        if status == 401 || status == 403 {
            onUpdate(.needsLogin(lastSnapshot))
            return
        }
        guard status == 200, let body = (result["usage"] as? String)?.data(using: .utf8) else {
            onUpdate(.failed(L10n.t("Unexpected response (\(stage) \(status))", "接口返回异常（\(stage) \(status)）"), lastSnapshot))
            return
        }
        do {
            let (session, weekly) = try UsageParser.parseUsage(body)
            let snapshot = UsageSnapshot(session: session, weekly: weekly,
                                         freeReset: UsageParser.parseFreeReset(body), fetchedAt: Date())
            lastSnapshot = snapshot
            onUpdate(.ok(snapshot))
        } catch {
            onUpdate(.failed(L10n.t("claude.ai changed its data format. Slimey needs an update.", "数据格式变了，需要更新解析逻辑"), lastSnapshot))
        }
    }
}
