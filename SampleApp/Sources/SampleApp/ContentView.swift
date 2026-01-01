import SwiftUI
import WebKit
import PhpIOS
import UIKit

protocol LogProvider {
    func fetchConsoleLog() async -> String
    func fetchSourceCode() async -> String
    func fetchPHPLog() async -> String
}

struct ClosureLogProvider: LogProvider {
    let consoleLog: () -> String
    let sourceCode: () -> String
    let phpLog: () -> String

    func fetchConsoleLog() async -> String {
        consoleLog()
    }

    func fetchSourceCode() async -> String {
        sourceCode()
    }

    func fetchPHPLog() async -> String {
        phpLog()
    }
}

struct ContentView: View {
    private enum NavigationTab: Hashable {
        case home
        case manager

        var title: String {
            switch self {
            case .home:
                return "Home"
            case .manager:
                return "Manager"
            }
        }

        var scriptRelativePath: String {
            switch self {
            case .home:
                return "index.php"
            case .manager:
                return "manager/index.php"
            }
        }

        var envRequestUri: String {
            switch self {
            case .home:
                return "/"
            case .manager:
                return "/manager/"
            }
        }

        var requestUri: String {
            switch self {
            case .home:
                return "/index.php"
            case .manager:
                return "/manager/admin.php"
            }
        }

        var tabSymbol: String {
            switch self {
            case .home:
                return "house"
            case .manager:
                return "gearshape"
            }
        }
    }

    private enum LogPanel: String, Identifiable, CaseIterable {
        case console
        case source
        case php

        var id: String { rawValue }

        var title: String {
            switch self {
            case .console:
                return "Console log"
            case .source:
                return "Source code"
            case .php:
                return "PHP log"
            }
        }

        var symbolName: String {
            switch self {
            case .console:
                return "terminal"
            case .source:
                return "doc.plaintext"
            case .php:
                return "chevron.left.slash.chevron.right"
            }
        }
    }

    private struct TabContentState {
        var htmlOutput: String = "<html><body><pre>Loading Evolution CMS...</pre></body></html>"
        var baseURL: URL?
        var errorMessage: String?
        var isLoading = false
        var hasLoaded = false
    }

    @State private var homeContent = TabContentState()
    @State private var managerContent = TabContentState()
    @State private var selectedTab: NavigationTab = .home

    @State private var isLogsMenuPresented = false
    @State private var activeLogPanel: LogPanel?
    @State private var isLogPanelPresented = false
    @State private var logContent = ""
    @State private var isLogLoading = false
    @State private var didCopy = false

    @StateObject private var homeWebViewStore: WebViewStore
    @StateObject private var managerWebViewStore: WebViewStore
    @StateObject private var homeLogStore: WebLogStore
    @StateObject private var managerLogStore: WebLogStore

    private let sessionID: String
    private let homeSchemeHandler: PhpIOSSchemeHandler
    private let managerSchemeHandler: PhpIOSSchemeHandler

    init() {
        let sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let dataStore = WKWebsiteDataStore.default()
        UITabBar.appearance().isHidden = true

        let homeLogStore = WebLogStore()
        let managerLogStore = WebLogStore()
        let homeSchemeHandler = PhpIOSSchemeHandler(sessionID: sessionID, logStore: homeLogStore)
        let managerSchemeHandler = PhpIOSSchemeHandler(sessionID: sessionID, logStore: managerLogStore)
        let homeWebViewStore = WebViewStore(dataStore: dataStore,
                                            schemeHandler: homeSchemeHandler)
        let managerWebViewStore = WebViewStore(dataStore: dataStore,
                                               schemeHandler: managerSchemeHandler)

        _homeLogStore = StateObject(wrappedValue: homeLogStore)
        _managerLogStore = StateObject(wrappedValue: managerLogStore)
        _homeWebViewStore = StateObject(wrappedValue: homeWebViewStore)
        _managerWebViewStore = StateObject(wrappedValue: managerWebViewStore)

        self.sessionID = sessionID
        self.homeSchemeHandler = homeSchemeHandler
        self.managerSchemeHandler = managerSchemeHandler
    }

    private var activeLogStore: WebLogStore {
        selectedTab == .home ? homeLogStore : managerLogStore
    }

    private var activeContent: TabContentState {
        selectedTab == .home ? homeContent : managerContent
    }

    private var logProvider: some LogProvider {
        ClosureLogProvider(
            consoleLog: {
                let consoleText = activeLogStore.console.joined(separator: "\n")
                let networkText = activeLogStore.network.joined(separator: "\n")
                if networkText.isEmpty {
                    return consoleText
                }
                let separator = consoleText.isEmpty ? "" : "\n\n"
                return consoleText + separator + "Network log:\n" + networkText
            },
            sourceCode: { loadSourceCode() },
            phpLog: { activeLogStore.php.joined(separator: "\n\n") }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if selectedTab == .home {
                    webContentView(state: homeContent, store: homeWebViewStore)
                } else {
                    Color.clear
                }
            }
            .tag(NavigationTab.home)
            .tabItem {
                Label(NavigationTab.home.title, systemImage: NavigationTab.home.tabSymbol)
            }

            Group {
                if selectedTab == .manager {
                    webContentView(state: managerContent, store: managerWebViewStore)
                } else {
                    Color.clear
                }
            }
            .tag(NavigationTab.manager)
            .tabItem {
                Label(NavigationTab.manager.title, systemImage: NavigationTab.manager.tabSymbol)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(selectedTab == .manager ? .dark : .light)
        .onChange(of: selectedTab) { newValue in
            updateWebViewStyles()
            if newValue == .home {
                if !homeContent.hasLoaded {
                    loadPage(.home)
                }
            } else {
                if !managerContent.hasLoaded {
                    loadPage(.manager)
                }
            }
        }
        .onChange(of: isLogPanelPresented) { newValue in
            if !newValue {
                activeLogPanel = nil
                didCopy = false
            }
        }
        .overlay(alignment: .topLeading) {
            if let errorMessage = activeContent.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 8)
                    .padding(.leading, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .onAppear {
            configureWebViewStore(homeWebViewStore, logStore: homeLogStore, tab: .home)
            configureWebViewStore(managerWebViewStore, logStore: managerLogStore, tab: .manager)
            updateWebViewStyles()

            if !homeContent.hasLoaded {
                loadPage(.home)
            }
        }
    }

    private func webContentView(state: TabContentState, store: WebViewStore) -> some View {
        ZStack {
            WebViewContainer(store: store, html: state.htmlOutput, baseURL: state.baseURL)
                .background(Color(.systemBackground))

            if state.isLoading {
                ProgressView("Loading")
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Loading page")
            }
        }
    }

    private var logsMenuPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(LogPanel.allCases) { panel in
                Button {
                    openLogPanel(panel)
                } label: {
                    Label(panel.title, systemImage: panel.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.title)
            }
        }
        .padding(16)
        .frame(minWidth: 220)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                navBarButton(for: .home)
                navBarButton(for: .manager)
            }

            Spacer(minLength: 12)

            logsBarButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .environment(\.colorScheme, selectedTab == .manager ? .dark : .light)
    }

    private func navBarButton(for tab: NavigationTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            triggerHaptic()
            selectedTab = tab
        } label: {
            barButtonLabel(title: tab.title, systemImage: tab.tabSymbol, isActive: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var logsBarButton: some View {
        let isActive = isLogsMenuPresented || isLogPanelPresented
        return Button {
            handleLogsTap()
        } label: {
            barButtonLabel(title: "Logs", systemImage: "terminal", isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Logs")
        .accessibilityHint("Show log menu")
        .popover(isPresented: $isLogsMenuPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            if #available(iOS 16.4, *) {
                logsMenuPopover
                    .environment(\.colorScheme, selectedTab == .manager ? .dark : .light)
                    .presentationCompactAdaptation(.popover)
            } else {
                logsMenuPopover
                    .environment(\.colorScheme, selectedTab == .manager ? .dark : .light)
            }
        }
        .popover(isPresented: $isLogPanelPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            if #available(iOS 16.4, *) {
                logPanelPopover
                    .environment(\.colorScheme, selectedTab == .manager ? .dark : .light)
                    .presentationCompactAdaptation(.popover)
            } else {
                logPanelPopover
                    .environment(\.colorScheme, selectedTab == .manager ? .dark : .light)
            }
        }
    }

    private func barButtonLabel(title: String, systemImage: String, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption2)
        }
        .frame(minWidth: 72, minHeight: 44)
        .contentShape(Rectangle())
        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private var logPanelPopover: some View {
        VStack(spacing: 12) {
            HStack {
                Text(activeLogPanel?.title ?? "Logs")
                    .font(.headline)
                Spacer()
                Button {
                    isLogPanelPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close log panel")
            }

            if isLogLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if logContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 12) {
                    Text("No log entries yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button {
                        Task { await refreshLogContent() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh log content")
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.bottom, 8)
                }
                .refreshable {
                    await refreshLogContent()
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            HStack {
                Button {
                    handleCopy()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy to clipboard")

                Spacer()

                Button {
                    isLogPanelPresented = false
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close log panel")
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 520, minHeight: 320, idealHeight: 420, maxHeight: 600)
    }

    private func handleLogsTap() {
        triggerHaptic()
        if isLogPanelPresented {
            isLogPanelPresented = false
            activeLogPanel = nil
            return
        }

        isLogsMenuPresented.toggle()
    }

    private func openLogPanel(_ panel: LogPanel) {
        triggerHaptic()
        isLogsMenuPresented = false
        activeLogPanel = panel
        isLogPanelPresented = true
        didCopy = false
        Task { await refreshLogContent() }
    }

    private func handleCopy() {
        UIPasteboard.general.string = logContent
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                didCopy = false
            }
        }
    }

    @MainActor
    private func refreshLogContent() async {
        guard let panel = activeLogPanel else { return }
        isLogLoading = true
        logContent = ""
        let content = await fetchLogContent(for: panel)
        logContent = content
        isLogLoading = false
    }

    private func fetchLogContent(for panel: LogPanel) async -> String {
        let provider = logProvider
        switch panel {
        case .console:
            return await provider.fetchConsoleLog()
        case .source:
            return await provider.fetchSourceCode()
        case .php:
            return await provider.fetchPHPLog()
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func loadPage(_ page: NavigationTab) {
        updateContentState(for: page) { state in
            state.isLoading = true
            state.errorMessage = nil
            state.hasLoaded = true
        }
        let logStore = logStore(for: page)
        logStore.reset()
        Task {
            do {
                let result = try runEvoPage(page, sessionID: sessionID)
                await MainActor.run {
                    updateContentState(for: page) { state in
                        state.htmlOutput = result.output
                        state.baseURL = result.baseURL
                        state.isLoading = false
                    }
                    logStore.setPhpLogs(result.phpLogs)
                    logStore.setCurrentScriptURL(result.scriptURL)
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    updateContentState(for: page) { state in
                        state.errorMessage = message
                        state.htmlOutput = "<html><body><pre>\(escapeHtml(message))</pre></body></html>"
                        state.baseURL = nil
                        state.isLoading = false
                    }
                    logStore.setPhpLogs([message])
                    logStore.setCurrentScriptURL(nil)
                }
            }
        }
    }

    private func configureWebViewStore(_ store: WebViewStore, logStore: WebLogStore, tab: NavigationTab) {
        store.onConsoleLine = { line in
            logStore.appendConsole(line)
        }
        store.onNetworkLine = { line in
            logStore.appendNetwork(line)
        }
        store.onLoadingChange = { isLoading in
            updateContentState(for: tab) { state in
                state.isLoading = isLoading
            }
        }
    }

    private func updateWebViewStyles() {
        let homeView = homeWebViewStore.webView
        homeView.overrideUserInterfaceStyle = .light
        homeView.isOpaque = false
        homeView.backgroundColor = UIColor.white
        homeView.scrollView.backgroundColor = UIColor.white
        homeView.scrollView.indicatorStyle = .default

        let managerView = managerWebViewStore.webView
        managerView.overrideUserInterfaceStyle = .dark
        managerView.isOpaque = false
        managerView.backgroundColor = UIColor.black
        managerView.scrollView.backgroundColor = UIColor.black
        managerView.scrollView.indicatorStyle = .white
    }

    private func logStore(for tab: NavigationTab) -> WebLogStore {
        switch tab {
        case .home:
            return homeLogStore
        case .manager:
            return managerLogStore
        }
    }

    private func updateContentState(for tab: NavigationTab, _ update: (inout TabContentState) -> Void) {
        switch tab {
        case .home:
            update(&homeContent)
        case .manager:
            update(&managerContent)
        }
    }

    private func loadSourceCode() -> String {
        guard let currentScriptURL = activeLogStore.currentScriptURL else {
            return "Source code unavailable."
        }
        do {
            return try String(contentsOf: currentScriptURL, encoding: .utf8)
        } catch {
            return "Unable to load source code: \(error.localizedDescription)"
        }
    }

    private func runEvoPage(_ page: NavigationTab,
                            sessionID: String) throws -> (output: String, baseURL: URL, phpLogs: [String], scriptURL: URL) {
        let siteRoot = try EvoSiteInstaller.ensureInstalled()
        let scriptURL = siteRoot.appendingPathComponent(page.scriptRelativePath)
        let scriptPath = scriptURL.path
        let databasePath = siteRoot.appendingPathComponent("database.sqlite").path
        let sessionPath = siteRoot.appendingPathComponent("core/storage/sessions").path
        let errorLogPath = siteRoot.appendingPathComponent("php-error.log").path
        let scriptName = "/" + page.scriptRelativePath
        let pageBaseURL: URL
        if page == .manager {
            pageBaseURL = URL(string: "phpios://localhost/manager/") ?? URL(fileURLWithPath: "/")
        } else {
            pageBaseURL = URL(string: "phpios://localhost/") ?? URL(fileURLWithPath: "/")
        }

        if !FileManager.default.fileExists(atPath: errorLogPath) {
            FileManager.default.createFile(atPath: errorLogPath, contents: nil)
        } else {
            try? "".write(toFile: errorLogPath, atomically: true, encoding: .utf8)
        }

        let engine = try PhpEngine.shared()
        let refererURL = "phpios://localhost" + page.envRequestUri
        let siteRootPath = siteRoot.path.hasSuffix("/") ? siteRoot.path : siteRoot.path + "/"
        let siteRootURL = "phpios://localhost/"
        let managerPath = siteRoot.appendingPathComponent("manager", isDirectory: true).path
        let managerPathWithSlash = managerPath.hasSuffix("/") ? managerPath : managerPath + "/"
        let managerURL = siteRootURL + "manager/"
        let result = try engine.runFile(
            scriptPath,
            env: [
                "DOCUMENT_ROOT": siteRoot.path,
                "REQUEST_URI": page.envRequestUri,
                "QUERY_STRING": "",
                "HTTP_HOST": "localhost",
                "HTTP_ACCEPT": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "HTTP_ACCEPT_LANGUAGE": "en-US,en;q=0.9",
                "HTTP_USER_AGENT": "PhpIOS/1.0 (iOS)",
                "HTTP_REFERER": refererURL,
                "SERVER_NAME": "localhost",
                "SERVER_PORT": "80",
                "REQUEST_SCHEME": "http",
                "HTTPS": "off",
                "REQUEST_METHOD": "GET",
                "SERVER_PROTOCOL": "HTTP/1.1",
                "PHP_SELF": scriptName,
                "SCRIPT_NAME": scriptName,
                "SCRIPT_FILENAME": scriptPath,
                "HTTP_COOKIE": "PHPSESSID=\(sessionID)",
                "MODX_BASE_PATH": siteRootPath,
                "EVO_BASE_PATH": siteRootPath,
                "MODX_BASE_URL": "/",
                "EVO_BASE_URL": "/",
                "MODX_SITE_URL": siteRootURL,
                "EVO_SITE_URL": siteRootURL,
                "MODX_MANAGER_PATH": managerPathWithSlash,
                "EVO_MANAGER_PATH": managerPathWithSlash,
                "MODX_MANAGER_URL": managerURL,
                "EVO_MANAGER_URL": managerURL,
                "DB_DATABASE": databasePath,
                "DB_TYPE": "sqlite",
                "PHP_IOS_DEBUG": "1"
            ],
            ini: [
                "session.save_path": sessionPath,
                "pcre.jit": "0",
                "display_errors": "1",
                "display_startup_errors": "1",
                "log_errors": "1",
                "error_log": errorLogPath,
                "error_reporting": "32767"
            ]
        )

        var phpLogs: [String] = ["exitCode: \(result.exitCode)"]
        var hasErrorLog = false
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            phpLogs.append("stderr:\n\(stderr)")
        }
        if let errorLogContents = try? String(contentsOfFile: errorLogPath, encoding: .utf8) {
            let trimmed = errorLogContents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                phpLogs.append("error_log:\n\(trimmed)")
                hasErrorLog = true
            }
        }
        if stderr.isEmpty && !hasErrorLog {
            let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                let maxLength = 4000
                let prefix = trimmedStdout.prefix(maxLength)
                let suffix = trimmedStdout.count > maxLength ? "\n... (truncated)" : ""
                phpLogs.append("stdout:\n\(prefix)\(suffix)")
            }
        }

        let trimmedOutput = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty {
            let fallback = stderr.isEmpty ? "Empty output from PHP." : escapeHtml(stderr)
            return ("<html><body><pre>\(fallback)</pre></body></html>", pageBaseURL, phpLogs, scriptURL)
        }
        return (result.stdout, pageBaseURL, phpLogs, scriptURL)
    }

    private func escapeHtml(_ input: String) -> String {
        var escaped = input.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        return escaped
    }
}

struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var store: WebViewStore
    let html: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        store.webView
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        store.loadHTML(html, baseURL: baseURL)
    }
}

final class WebViewStore: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onConsoleLine: (String) -> Void = { _ in }
    var onNetworkLine: (String) -> Void = { _ in }
    var onLoadingChange: (Bool) -> Void = { _ in }

    let webView: WKWebView
    private let contentController: WKUserContentController
    private var lastLoadedHTML: String?
    private var lastLoadedBaseURL: URL?

    init(dataStore: WKWebsiteDataStore, schemeHandler: WKURLSchemeHandler) {
        contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = dataStore
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "phpios")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        let scriptSource = """
        (function() {
          function safeStringify(value) {
            if (typeof value === 'string') { return value; }
            try { return JSON.stringify(value); } catch (e) { return String(value); }
          }

          function stringifyArgs(args) {
            return Array.prototype.slice.call(args).map(safeStringify).join(' ');
          }

          function postMessage(payload) {
            try { window.webkit.messageHandlers.jsLog.postMessage(payload); } catch (e) {}
          }

          function logConsole(level, message) {
            postMessage({ channel: 'console', level: level, message: message });
          }

          function logNetwork(event, detail) {
            var payload = { channel: 'network', event: event };
            for (var key in detail) { payload[key] = detail[key]; }
            postMessage(payload);
          }

          ['log','info','warn','error','debug'].forEach(function(level) {
            var original = console[level];
            console[level] = function() {
              try { logConsole(level, stringifyArgs(arguments)); } catch (e) {}
              if (original) { original.apply(console, arguments); }
            };
          });

          window.addEventListener('error', function(event) {
            try {
              var target = event.target || event.srcElement;
              var url = target && (target.src || target.href);
              if (url) {
                logNetwork('resource-error', {
                  url: String(url),
                  tag: target.tagName || 'unknown'
                });
              } else {
                logConsole('error', event.message + ' @ ' + event.filename + ':' + event.lineno + ':' + event.colno);
              }
            } catch (e) {}
          }, true);

          window.addEventListener('unhandledrejection', function(event) {
            try {
              var reason = event.reason && (event.reason.message || event.reason);
              logConsole('error', 'Unhandled promise rejection: ' + safeStringify(reason));
            } catch (e) {}
          });

          if (window.fetch) {
            var originalFetch = window.fetch;
            window.fetch = function(input, init) {
              var method = (init && init.method) || (input && input.method) || 'GET';
              var url = (typeof input === 'string') ? input : (input && input.url) || '';
              var start = Date.now();
              logNetwork('request', { method: method, url: String(url) });
              return originalFetch.apply(this, arguments).then(function(response) {
                logNetwork('response', {
                  method: method,
                  url: String(response.url || url),
                  status: response.status,
                  durationMs: Date.now() - start
                });
                return response;
              }).catch(function(error) {
                logNetwork('error', {
                  method: method,
                  url: String(url),
                  error: safeStringify(error),
                  durationMs: Date.now() - start
                });
                throw error;
              });
            };
          }

          if (window.XMLHttpRequest) {
            var originalOpen = XMLHttpRequest.prototype.open;
            var originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
              this.__phpiosRequest = { method: method, url: url, start: 0 };
              return originalOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
              var request = this.__phpiosRequest;
              if (request) {
                request.start = Date.now();
                logNetwork('request', { method: request.method, url: String(request.url) });
              }
              var finalize = function(status, eventType) {
                if (!request) { return; }
                logNetwork(eventType === 'load' ? 'response' : 'error', {
                  method: request.method,
                  url: String(request.url),
                  status: status,
                  durationMs: Date.now() - request.start,
                  event: eventType
                });
              };
              this.addEventListener('load', function() { finalize(this.status, 'load'); });
              this.addEventListener('error', function() { finalize(this.status, 'error'); });
              this.addEventListener('abort', function() { finalize(this.status, 'abort'); });
              return originalSend.apply(this, arguments);
            };
          }
        })();
        """

        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(script)
        contentController.add(self, name: "jsLog")
        webView.navigationDelegate = self
    }

    deinit {
        contentController.removeScriptMessageHandler(forName: "jsLog")
    }

    func loadHTML(_ html: String, baseURL: URL?) {
        guard html != lastLoadedHTML || baseURL != lastLoadedBaseURL else { return }
        lastLoadedHTML = html
        lastLoadedBaseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "jsLog" else { return }
        guard let body = message.body as? [String: Any] else {
            appendConsoleLog("\(message.body)")
            return
        }
        let channel = body["channel"] as? String ?? "console"
        switch channel {
        case "network":
            appendNetworkLog(formatNetworkLog(body))
        default:
            let level = body["level"] as? String ?? "log"
            let msg = body["message"] as? String ?? "\(message.body)"
            appendConsoleLog("[\(level)] \(msg)")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        appendConsoleLog("[error] WebView navigation failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.onLoadingChange(false)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        appendConsoleLog("[error] WebView load failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.onLoadingChange(false)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.onLoadingChange(true)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.onLoadingChange(false)
        }
    }

    private func appendConsoleLog(_ line: String) {
        DispatchQueue.main.async {
            self.onConsoleLine(line)
        }
    }

    private func appendNetworkLog(_ line: String) {
        DispatchQueue.main.async {
            self.onNetworkLine(line)
        }
    }

    private func formatNetworkLog(_ body: [String: Any]) -> String {
        let event = (body["event"] as? String ?? "event").uppercased()
        let method = body["method"] as? String
        let url = body["url"] as? String
        let status = (body["status"] as? NSNumber)?.intValue ?? body["status"] as? Int
        let duration = (body["durationMs"] as? NSNumber)?.intValue ?? body["durationMs"] as? Int
        let error = body["error"] as? String
        let tag = body["tag"] as? String

        var parts: [String] = [event]
        if let method { parts.append(method) }
        if let url { parts.append(url) }
        if let status { parts.append("status:\(status)") }
        if let duration { parts.append("time:\(duration)ms") }
        if let error { parts.append("error:\(error)") }
        if let tag { parts.append("tag:\(tag)") }
        return parts.joined(separator: " ")
    }
}

final class WebLogStore: ObservableObject {
    @Published var console: [String] = []
    @Published var network: [String] = []
    @Published var php: [String] = []
    @Published var currentScriptURL: URL?

    func reset() {
        updateOnMain {
            self.console.removeAll()
            self.network.removeAll()
            self.php.removeAll()
            self.currentScriptURL = nil
        }
    }

    func appendConsole(_ line: String) {
        updateOnMain {
            self.console = self.append(line, to: self.console, limit: 300)
        }
    }

    func appendNetwork(_ line: String) {
        updateOnMain {
            self.network = self.append(line, to: self.network, limit: 500)
        }
    }

    func appendPhp(_ entry: String) {
        updateOnMain {
            self.php = self.append(entry, to: self.php, limit: 200)
        }
    }

    func setPhpLogs(_ logs: [String]) {
        updateOnMain {
            self.php = logs
        }
    }

    func setCurrentScriptURL(_ url: URL?) {
        updateOnMain {
            self.currentScriptURL = url
        }
    }

    private func append(_ line: String, to logs: [String], limit: Int) -> [String] {
        var updated = logs
        updated.append(line)
        if updated.count > limit {
            updated.removeFirst(updated.count - limit)
        }
        return updated
    }

    private func updateOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async {
                work()
            }
        }
    }
}

final class PhpIOSSchemeHandler: NSObject, WKURLSchemeHandler {
    private let sessionID: String
    private let logStore: WebLogStore
    private let requestQueue = DispatchQueue(label: "phpios.scheme")

    init(sessionID: String, logStore: WebLogStore) {
        self.sessionID = sessionID
        self.logStore = logStore
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        requestQueue.async {
            self.handle(task: urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    private func handle(task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            fail(task, message: "Missing request URL.")
            return
        }

        let method = task.request.httpMethod ?? "GET"
        logNetwork("[REQ] \(method) \(url.absoluteString)")

        do {
            let siteRoot = try EvoSiteInstaller.ensureInstalled()
            let resolved = try resolveFileURL(for: url,
                                              request: task.request,
                                              siteRoot: siteRoot)
            if resolved.isPhp {
                let requestPathOverride = overrideRequestPath(for: url, resolved: resolved)
                let response = try runPhp(for: task.request,
                                          url: url,
                                          scriptURL: resolved.fileURL,
                                          siteRoot: siteRoot,
                                          requestPathOverride: requestPathOverride)
                respond(task,
                        url: url,
                        mimeType: response.mimeType,
                        data: response.data,
                        statusDescription: "PHP \(response.data.count) bytes")
                logPhp(response.logEntry, isMainDocument: resolved.isMainDocument, scriptURL: resolved.fileURL)
            } else {
                let data = try Data(contentsOf: resolved.fileURL)
                let mimeType = mimeType(for: resolved.fileURL.pathExtension)
                respond(task,
                        url: url,
                        mimeType: mimeType,
                        data: data,
                        statusDescription: "FILE \(data.count) bytes")
            }
        } catch {
            let message = error.localizedDescription
            respond(task,
                    url: url,
                    mimeType: "text/html",
                    data: Data("<html><body><pre>\(message)</pre></body></html>".utf8),
                    statusDescription: "ERROR")
            logNetwork("[ERR] \(method) \(url.absoluteString) \(message)")
        }
    }

    private func resolveFileURL(for url: URL,
                                request: URLRequest,
                                siteRoot: URL) throws -> (fileURL: URL, isPhp: Bool, isMainDocument: Bool) {
        let path = url.path.isEmpty ? "/" : url.path
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var fileURL = siteRoot.appendingPathComponent(relativePath)
        let fileManager = FileManager.default

        if path == "/" {
            fileURL = siteRoot.appendingPathComponent("index.php")
        } else {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let indexURL = fileURL.appendingPathComponent("index.php")
                if fileManager.fileExists(atPath: indexURL.path) {
                    fileURL = indexURL
                }
            } else if !fileManager.fileExists(atPath: fileURL.path) {
                if fileURL.pathExtension.isEmpty {
                    let phpURL = fileURL.appendingPathExtension("php")
                    if fileManager.fileExists(atPath: phpURL.path) {
                        fileURL = phpURL
                    }
                } else if path.hasPrefix("/manager/") {
                    let fallback = siteRoot.appendingPathComponent("manager/index.php")
                    if fileManager.fileExists(atPath: fallback.path) {
                        fileURL = fallback
                    }
                }
            }
        }

        let standardized = fileURL.standardizedFileURL
        if !standardized.path.hasPrefix(siteRoot.standardizedFileURL.path) {
            throw PhpError.scriptNotFound(standardized.path)
        }
        guard fileManager.fileExists(atPath: standardized.path) else {
            throw PhpError.scriptNotFound(standardized.path)
        }

        let mainDocumentURL = request.mainDocumentURL
        let acceptHeader = request.value(forHTTPHeaderField: "Accept") ?? ""
        let isDocumentLike = acceptHeader.contains("text/html")
        let isMainDocument = mainDocumentURL == nil ? isDocumentLike : mainDocumentURL == url
        return (standardized, standardized.pathExtension.lowercased() == "php", isMainDocument)
    }

    private func runPhp(for request: URLRequest,
                        url: URL,
                        scriptURL: URL,
                        siteRoot: URL,
                        requestPathOverride: String?) throws -> (data: Data, mimeType: String, logEntry: String) {
        let engine = try PhpEngine.shared()
        let bodyData = requestBody(from: request) ?? Data()
        let query = url.query ?? ""
        let requestPath = requestPathOverride ?? (url.path.isEmpty ? "/" : url.path)
        let requestUri = query.isEmpty ? requestPath : "\(requestPath)?\(query)"

        let rootPath = siteRoot.path.hasSuffix("/") ? siteRoot.path : siteRoot.path + "/"
        let scriptRelative = "/" + scriptURL.path.replacingOccurrences(of: rootPath, with: "")
        let databasePath = siteRoot.appendingPathComponent("database.sqlite").path
        let sessionPath = siteRoot.appendingPathComponent("core/storage/sessions").path
        let errorLogPath = siteRoot.appendingPathComponent("php-error.log").path
        let managerPath = siteRoot.appendingPathComponent("manager", isDirectory: true).path
        let managerPathWithSlash = managerPath.hasSuffix("/") ? managerPath : managerPath + "/"

        if !FileManager.default.fileExists(atPath: errorLogPath) {
            FileManager.default.createFile(atPath: errorLogPath, contents: nil)
        } else {
            try? "".write(toFile: errorLogPath, atomically: true, encoding: .utf8)
        }

        let accept = request.value(forHTTPHeaderField: "Accept")
            ?? "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        let acceptLanguage = request.value(forHTTPHeaderField: "Accept-Language") ?? "en-US,en;q=0.9"
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? "PhpIOS/1.0 (iOS)"
        let referer = request.value(forHTTPHeaderField: "Referer") ?? ""
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let host = url.host ?? "localhost"

        var env: [String: String] = [
            "DOCUMENT_ROOT": siteRoot.path,
            "REQUEST_URI": requestUri,
            "QUERY_STRING": query,
            "HTTP_HOST": host,
            "HTTP_ACCEPT": accept,
            "HTTP_ACCEPT_LANGUAGE": acceptLanguage,
            "HTTP_USER_AGENT": userAgent,
            "HTTP_REFERER": referer,
            "SERVER_NAME": host,
            "SERVER_PORT": "80",
            "REQUEST_SCHEME": "http",
            "HTTPS": "off",
            "REQUEST_METHOD": request.httpMethod ?? "GET",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "PHP_SELF": scriptRelative,
            "SCRIPT_NAME": scriptRelative,
            "SCRIPT_FILENAME": scriptURL.path,
            "MODX_BASE_PATH": rootPath,
            "EVO_BASE_PATH": rootPath,
            "MODX_BASE_URL": "/",
            "EVO_BASE_URL": "/",
            "MODX_SITE_URL": "phpios://localhost/",
            "EVO_SITE_URL": "phpios://localhost/",
            "MODX_MANAGER_PATH": managerPathWithSlash,
            "EVO_MANAGER_PATH": managerPathWithSlash,
            "MODX_MANAGER_URL": "phpios://localhost/manager/",
            "EVO_MANAGER_URL": "phpios://localhost/manager/",
            "DB_DATABASE": databasePath,
            "DB_TYPE": "sqlite",
            "PHP_IOS_DEBUG": "1"
        ]

        if !contentType.isEmpty {
            env["CONTENT_TYPE"] = contentType
        }
        if !bodyData.isEmpty {
            env["CONTENT_LENGTH"] = "\(bodyData.count)"
        }

        let cookieHeader = request.value(forHTTPHeaderField: "Cookie") ?? ""
        if cookieHeader.contains("PHPSESSID=") {
            env["HTTP_COOKIE"] = cookieHeader
        } else if cookieHeader.isEmpty {
            env["HTTP_COOKIE"] = "PHPSESSID=\(sessionID)"
        } else {
            env["HTTP_COOKIE"] = "PHPSESSID=\(sessionID); \(cookieHeader)"
        }

        let result = try engine.runFile(
            scriptURL.path,
            stdin: bodyData.isEmpty ? .none : .data(bodyData),
            env: env,
            ini: [
                "session.save_path": sessionPath,
                "pcre.jit": "0",
                "display_errors": "1",
                "display_startup_errors": "1",
                "log_errors": "1",
                "error_log": errorLogPath,
                "error_reporting": "32767"
            ]
        )

        var phpLogs: [String] = ["request: \(request.httpMethod ?? "GET") \(requestUri)",
                                 "exitCode: \(result.exitCode)"]
        var hasErrorLog = false
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            phpLogs.append("stderr:\n\(stderr)")
        }
        if let errorLogContents = try? String(contentsOfFile: errorLogPath, encoding: .utf8) {
            let trimmed = errorLogContents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                phpLogs.append("error_log:\n\(trimmed)")
                hasErrorLog = true
            }
        }
        if stderr.isEmpty && !hasErrorLog {
            let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                let maxLength = 1200
                let prefix = trimmedStdout.prefix(maxLength)
                let suffix = trimmedStdout.count > maxLength ? "\n... (truncated)" : ""
                phpLogs.append("stdout:\n\(prefix)\(suffix)")
            }
        }

        let output = result.stdout.isEmpty ? "<html><body><pre>Empty output from PHP.</pre></body></html>" : result.stdout
        let outputData = Data(output.utf8)
        let mimeType: String
        if accept.contains("text/css") {
            mimeType = "text/css"
        } else if accept.contains("application/javascript") || accept.contains("text/javascript") {
            mimeType = "application/javascript"
        } else if accept.contains("application/json") || outputLooksLikeJson(output) {
            mimeType = "application/json"
        } else {
            mimeType = "text/html"
        }
        return (outputData, mimeType, phpLogs.joined(separator: "\n\n"))
    }

    private func overrideRequestPath(for url: URL,
                                     resolved: (fileURL: URL, isPhp: Bool, isMainDocument: Bool)) -> String? {
        guard resolved.isMainDocument else { return nil }
        switch url.path {
        case "/index.php":
            return "/"
        case "/manager/admin.php":
            if resolved.fileURL.lastPathComponent == "index.php",
               resolved.fileURL.deletingLastPathComponent().lastPathComponent == "manager" {
                return "/manager/"
            }
            return nil
        default:
            return nil
        }
    }

    private func outputLooksLikeJson(_ output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func respond(_ task: WKURLSchemeTask,
                         url: URL,
                         mimeType: String,
                         data: Data,
                         statusDescription: String) {
        let response = URLResponse(url: url,
                                   mimeType: mimeType,
                                   expectedContentLength: data.count,
                                   textEncodingName: "utf-8")
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        logNetwork("[RESP] \(statusDescription) \(url.absoluteString)")
    }

    private func fail(_ task: WKURLSchemeTask, message: String) {
        let error = NSError(domain: "PhpIOS.SchemeHandler",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message])
        task.didFailWithError(error)
        logNetwork("[ERR] \(message)")
    }

    private func logNetwork(_ line: String) {
        logStore.appendNetwork(line)
    }

    private func logPhp(_ entry: String, isMainDocument: Bool, scriptURL: URL) {
        logStore.appendPhp(entry)
        if isMainDocument {
            logStore.setCurrentScriptURL(scriptURL)
        }
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "webp":
            return "image/webp"
        case "ico":
            return "image/x-icon"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        case "map":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }
}

private enum EvoSiteInstaller {
    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    static func ensureInstalled() throws -> URL {
        let fileManager = FileManager.default
        let supportURL = try fileManager.url(for: .applicationSupportDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true)
        let destinationRoot = supportURL.appendingPathComponent("evo", isDirectory: true)

        let indexMarker = destinationRoot.appendingPathComponent("index.php")
        var needsRefresh = false
        var needsIndexUpdate = false
        if fileManager.fileExists(atPath: indexMarker.path) {
            if let contents = try? String(contentsOf: indexMarker, encoding: .utf8),
               !contents.contains("PHP_IOS_DEBUG") {
                needsIndexUpdate = true
            }
        }
        let modelPath = destinationRoot.appendingPathComponent("core/src/Models/SiteContent.php")
        if fileManager.fileExists(atPath: modelPath.path) {
            if let contents = try? String(contentsOf: modelPath, encoding: .utf8),
               (contents.contains("SiteContent $parent = null")
                || contents.contains("callable $positionCallback = null")) {
                needsRefresh = true
            }
        }
        let utilsPath = destinationRoot.appendingPathComponent("core/functions/utils.php")
        if fileManager.fileExists(atPath: utilsPath.path) {
            if let contents = try? String(contentsOf: utilsPath, encoding: .utf8),
               contents.contains("array $options = null") {
                needsRefresh = true
            }
        }

        if !fileManager.fileExists(atPath: destinationRoot.path)
            || !fileManager.fileExists(atPath: indexMarker.path)
            || needsRefresh {
            if fileManager.fileExists(atPath: destinationRoot.path) {
                try fileManager.removeItem(at: destinationRoot)
            }
            guard let indexUrl = resourceBundle.url(forResource: "index",
                                                    withExtension: "php",
                                                    subdirectory: "payload/work/evo") else {
                throw PhpError.scriptNotFound("payload/work/evo/index.php")
            }
            let resourceRoot = indexUrl.deletingLastPathComponent()
            try fileManager.copyItem(at: resourceRoot, to: destinationRoot)
            needsIndexUpdate = false
        } else if needsIndexUpdate {
            guard let indexUrl = resourceBundle.url(forResource: "index",
                                                    withExtension: "php",
                                                    subdirectory: "payload/work/evo") else {
                throw PhpError.scriptNotFound("payload/work/evo/index.php")
            }
            if fileManager.fileExists(atPath: indexMarker.path) {
                try fileManager.removeItem(at: indexMarker)
            }
            try fileManager.copyItem(at: indexUrl, to: indexMarker)
        }

        let installMarker = destinationRoot.appendingPathComponent("core/.install")
        if !fileManager.fileExists(atPath: installMarker.path) {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            try timestamp.write(to: installMarker, atomically: true, encoding: .utf8)
        }
        let coreInstallMarker = destinationRoot.appendingPathComponent("core.install")
        if !fileManager.fileExists(atPath: coreInstallMarker.path) {
            let timestamp = (try? String(contentsOf: installMarker, encoding: .utf8))
                ?? String(Int(Date().timeIntervalSince1970))
            try timestamp.write(to: coreInstallMarker, atomically: true, encoding: .utf8)
        }
        let debugConfigDirectory = destinationRoot.appendingPathComponent("core/custom/config/app", isDirectory: true)
        if !fileManager.fileExists(atPath: debugConfigDirectory.path) {
            try fileManager.createDirectory(at: debugConfigDirectory, withIntermediateDirectories: true)
        }
        let debugConfigPath = debugConfigDirectory.appendingPathComponent("debug.php")
        if !fileManager.fileExists(atPath: debugConfigPath.path) {
            let debugConfig = "<?php\n\nreturn filter_var(env('PHP_IOS_DEBUG', false), FILTER_VALIDATE_BOOLEAN);\n"
            try debugConfig.write(to: debugConfigPath, atomically: true, encoding: .utf8)
        }

        let sessionsURL = destinationRoot.appendingPathComponent("core/storage/sessions", isDirectory: true)
        if !fileManager.fileExists(atPath: sessionsURL.path) {
            try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        }
        let storageURL = destinationRoot.appendingPathComponent("storage", isDirectory: true)
        if !fileManager.fileExists(atPath: storageURL.path) {
            try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        }
        let uploadsURL = destinationRoot.appendingPathComponent("uploads", isDirectory: true)
        if !fileManager.fileExists(atPath: uploadsURL.path) {
            try fileManager.createDirectory(at: uploadsURL, withIntermediateDirectories: true)
        }

        let databaseURL = destinationRoot.appendingPathComponent("database.sqlite")
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw PhpError.scriptNotFound(databaseURL.path)
        }

        return destinationRoot
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
