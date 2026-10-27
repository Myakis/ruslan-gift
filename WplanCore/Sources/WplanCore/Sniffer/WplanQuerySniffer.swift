#if canImport(WebKit) && os(macOS)
import AppKit
import WebKit

/// Loads the real Wplan frontend in a `WKWebView` and records the persisted-query
/// hashes its own GraphQL requests carry, so ours never need copying from DevTools.
///
/// Hidden mode (`refreshHashes()`) logs in with the Keychain credentials and
/// presses the day button itself; every GraphQL POST except `Login` is blocked
/// there, so the press yields the `StartOrFinishDay` hash without starting or
/// finishing the day. Visible mode (`openWindow()`) blocks nothing.
@MainActor
public final class WplanQuerySniffer: NSObject, ObservableObject, PersistedQueryHashRefreshing {
    public enum Status: Equatable {
        case idle
        case running
        case finished(captured: Int, changed: Int)
        case failed(String)
    }

    public static let siteURL = URL(string: "https://wplan.office.lan/ru-RU")!
    private static let messageHandlerName = "wplanSniffer"
    private static let hiddenTimeout: TimeInterval = 45
    private static let maxAutopilotRuns = 3
    private static let automaticCooldown: TimeInterval = 10 * 60
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var entries: [PersistedQueryHashStore.Entry]

    private let hashStore: PersistedQueryHashStore
    private let credentialsStore: KeychainStore
    private var webView: WKWebView?
    private var window: NSWindow?
    private var isHiddenSession = false
    private var autopilotRuns = 0
    private var captured: Set<PersistedQueryHashStore.Operation> = []
    private var changedCount = 0
    private var inFlight: Task<Bool, Never>?
    private var lastAutomaticAttemptAt: Date?

    public init(hashStore: PersistedQueryHashStore, credentialsStore: KeychainStore) {
        self.hashStore = hashStore
        self.credentialsStore = credentialsStore
        self.entries = hashStore.entries()
    }

    /// Automatic path (called on `PersistedQueryNotFound`). Rate-limited, since the
    /// scheduler ticks every 30s and each run is a real login in the web view.
    public func refreshHashes() async -> Bool {
        if let inFlight { return await inFlight.value }
        if let lastAutomaticAttemptAt, Date().timeIntervalSince(lastAutomaticAttemptAt) < Self.automaticCooldown {
            return false
        }
        lastAutomaticAttemptAt = Date()
        return await refreshHashesNow()
    }

    public func refreshHashesNow() async -> Bool {
        if let inFlight { return await inFlight.value }
        guard webView == nil else { return false }
        let task = Task { await self.runHiddenSession() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    /// Shows the real site in a normal window — the fallback when the hidden
    /// autopilot can't find the login form or the day button.
    public func openWindow() {
        if let window, !isHiddenSession {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard webView == nil else { return }
        startSession(hidden: false)
        status = .running
    }

    private func runHiddenSession() async -> Bool {
        guard (try? credentialsStore.load()) != nil else {
            status = .failed("Нет сохранённых логина и пароля")
            return false
        }
        startSession(hidden: true)
        status = .running

        let deadline = Date().addingTimeInterval(Self.hiddenTimeout)
        while Date() < deadline, captured.count < PersistedQueryHashStore.Operation.allCases.count {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let result = (captured: captured.count, changed: changedCount)
        endSession()
        status = result.captured == 0
            ? .failed("Не удалось перехватить запросы — откройте Wplan вручную")
            : .finished(captured: result.captured, changed: result.changed)
        return result.captured > 0
    }

    private func startSession(hidden: Bool) {
        isHiddenSession = hidden
        autopilotRuns = 0
        captured = []
        changedCount = 0

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(source: Self.interceptorScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        contentController.add(WeakScriptMessageHandler(self), name: Self.messageHandlerName)
        configuration.userContentController = contentController

        let frame = NSRect(x: 0, y: 0, width: 1200, height: 860)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        self.webView = webView

        let window: NSWindow
        if hidden {
            // Off-screen rather than unattached, so the page gets real layout and
            // the autopilot's visibility checks work.
            window = NSWindow(contentRect: frame.offsetBy(dx: -30_000, dy: -30_000), styleMask: .borderless, backing: .buffered, defer: false)
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.transient, .ignoresCycle]
        } else {
            window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Wplan — обновление хэшей"
            window.delegate = self
            window.center()
        }
        window.isReleasedWhenClosed = false
        window.contentView = webView
        if hidden {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        self.window = window

        webView.load(URLRequest(url: Self.siteURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    private func endSession() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        webView?.navigationDelegate = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        webView = nil
        window = nil
        isHiddenSession = false
    }

    fileprivate func handleMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.securityOrigin.host == Self.siteURL.host,
              let body = message.body as? [String: Any],
              body["type"] as? String == "hash",
              let name = body["operationName"] as? String,
              let operation = PersistedQueryHashStore.Operation(rawValue: name),
              let hash = body["hash"] as? String,
              PersistedQueryHashStore.isValidHash(hash)
        else { return }

        if hashStore.update(hash, for: operation) { changedCount += 1 }
        captured.insert(operation)
        entries = hashStore.entries()
        if !isHiddenSession {
            status = .finished(captured: captured.count, changed: changedCount)
        }
    }

    private func runAutopilot() {
        guard isHiddenSession, let webView, webView.url?.host == Self.siteURL.host,
              autopilotRuns < Self.maxAutopilotRuns,
              let credentials = try? credentialsStore.load()
        else { return }
        autopilotRuns += 1
        webView.callAsyncJavaScript(
            "window.__wplanSniffer && window.__wplanSniffer.autopilot(credentials)",
            arguments: ["credentials": ["username": credentials.username, "password": credentials.password]],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }
}

extension WplanQuerySniffer: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        runAutopilot()
    }
}

extension WplanQuerySniffer: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard !isHiddenSession else { return }
        endSession()
        if captured.isEmpty { status = .idle }
    }
}

/// `WKUserContentController` retains its handlers strongly.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var sniffer: WplanQuerySniffer?

    init(_ sniffer: WplanQuerySniffer) {
        self.sniffer = sniffer
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { sniffer?.handleMessage(message) }
    }
}

extension WplanQuerySniffer {
    static let interceptorScript = #"""
    (() => {
      if (window.__wplanSniffer) return;
      const state = { blockMutations: false, autopiloting: false };
      const post = (message) => {
        try { window.webkit.messageHandlers.wplanSniffer.postMessage(message); } catch (_) {}
      };
      const isGraphQL = (url) => String(url || '').includes('/api/graphql');
      const fromURL = (url) => {
        try {
          const parsed = new URL(String(url), location.href);
          const operationName = parsed.searchParams.get('operationName');
          const extensions = JSON.parse(parsed.searchParams.get('extensions') || '{}');
          return operationName ? [{ operationName, hash: extensions?.persistedQuery?.sha256Hash }] : [];
        } catch (_) { return []; }
      };
      const fromBody = (body) => {
        if (typeof body !== 'string') return [];
        try {
          const parsed = JSON.parse(body);
          return (Array.isArray(parsed) ? parsed : [parsed])
            .map((item) => ({ operationName: item?.operationName, hash: item?.extensions?.persistedQuery?.sha256Hash }));
        } catch (_) { return []; }
      };
      const inspect = (method, url, body) => {
        const operations = fromURL(url).concat(fromBody(body));
        operations.forEach((op) => {
          if (op.operationName && op.hash) post({ type: 'hash', operationName: op.operationName, hash: op.hash });
        });
        const isPost = String(method || 'GET').toUpperCase() === 'POST';
        return state.blockMutations && isPost &&
          (operations.length === 0 || operations.some((op) => op.operationName !== 'Login'));
      };

      const originalFetch = window.fetch;
      window.fetch = function (input, init) {
        const url = input instanceof Request ? input.url : String(input);
        const method = (init && init.method) || (input instanceof Request ? input.method : 'GET');
        if (isGraphQL(url) && inspect(method, url, init && init.body)) {
          return Promise.resolve(new Response(
            JSON.stringify({ data: null, errors: [{ message: 'Blocked by Wplan Widget' }] }),
            { status: 200, headers: { 'Content-Type': 'application/json' } }
          ));
        }
        return originalFetch.apply(this, arguments);
      };

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__wplanRequest = { method, url: String(url) };
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function (body) {
        const request = this.__wplanRequest;
        if (request && isGraphQL(request.url) && inspect(request.method, request.url, body)) {
          setTimeout(() => this.dispatchEvent(new Event('error')), 0);
          return;
        }
        return originalSend.apply(this, arguments);
      };

      const isVisible = (el) => !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length));
      const textOf = (el) => (el.innerText || el.textContent || '').trim();
      const clickables = (root) => Array.from((root || document).querySelectorAll('button, [role="button"], input[type="submit"]')).filter(isVisible);
      const setValue = (input, value) => {
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setter.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      };

      const autopilot = (credentials) => {
        if (state.autopiloting) return;
        state.autopiloting = true;
        state.blockMutations = true;
        let loginSubmitted = false;
        let dayClickedAt = 0;
        let confirmClicked = false;
        const startedAt = Date.now();
        const timer = setInterval(() => {
          if (Date.now() - startedAt > 40000) { clearInterval(timer); return; }

          const password = Array.from(document.querySelectorAll('input[type="password"]')).find(isVisible);
          if (password) {
            if (loginSubmitted) return;
            const scope = password.form || document;
            const username = Array.from(scope.querySelectorAll('input'))
              .filter((el) => isVisible(el) && !['password', 'hidden', 'checkbox', 'radio', 'submit', 'button'].includes(el.type))[0];
            if (!username) return;
            setValue(username, credentials.username);
            setValue(password, credentials.password);
            loginSubmitted = true;
            setTimeout(() => {
              const submit = (password.form && password.form.querySelector('button[type="submit"], input[type="submit"]')) ||
                clickables().find((el) => /^(войти|вход|login|sign in)/i.test(textOf(el)));
              if (submit) submit.click();
              else if (password.form) password.form.requestSubmit();
            }, 300);
            return;
          }

          if (!dayClickedAt) {
            const dayButton = clickables().find((el) => {
              const text = textOf(el);
              return text.length < 40 && /^(начать|завершить)/i.test(text);
            });
            if (dayButton) { dayButton.click(); dayClickedAt = Date.now(); }
            return;
          }

          if (!confirmClicked && Date.now() - dayClickedAt > 500) {
            const dialog = document.querySelector('[role="dialog"], [role="alertdialog"], [class*="modal" i]');
            const confirm = dialog && clickables(dialog).find((el) => /^(да|подтвердить|ок|ok|начать|завершить)/i.test(textOf(el)));
            if (confirm) { confirm.click(); confirmClicked = true; }
          }
        }, 500);
      };

      window.__wplanSniffer = { autopilot };
    })();
    """#
}
#endif
