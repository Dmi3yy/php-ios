import SwiftUI
import WebKit
import PhpIOS
import UIKit

protocol LogProvider {
    func fetchConsoleLog() async -> String
    func fetchNetworkLog() async -> String
    func fetchSourceCode() async -> String
    func fetchPHPLog() async -> String
}

struct ClosureLogProvider: LogProvider {
    let consoleLog: () -> String
    let networkLog: () -> String
    let sourceCode: () -> String
    let phpLog: () -> String

    func fetchConsoleLog() async -> String {
        consoleLog()
    }

    func fetchNetworkLog() async -> String {
        networkLog()
    }

    func fetchSourceCode() async -> String {
        sourceCode()
    }

    func fetchPHPLog() async -> String {
        phpLog()
    }
}

struct NetworkEvent: Identifiable {
    enum Kind: String {
        case request
        case response
        case error
        case resourceError
        case nativeRequest
        case nativeResponse
    }

    let id: String
    let requestId: String?
    let kind: Kind
    let method: String?
    let url: String
    let status: Int?
    let durationMs: Int?
    let error: String?
    let tag: String?
    let time: Date
    let requestHeaders: [String: String]?
    let requestBodyPreview: String?
    let responseHeaders: [String: String]?
    let responseBodyPreview: String?
    let cookiesBefore: String?
    let cookiesAfter: String?

    var methodText: String {
        (method ?? "—").uppercased()
    }

    var statusText: String {
        if let status {
            return "\(status)"
        }
        return "—"
    }

    var durationText: String {
        if let durationMs {
            return "\(durationMs)ms"
        }
        return "—"
    }

    var summaryLine: String {
        var parts: [String] = [kindLabel, methodText, statusText, durationText, url]
        if let error, !error.isEmpty {
            parts.append("error:\(error)")
        }
        if let tag, !tag.isEmpty {
            parts.append("tag:\(tag)")
        }
        if let requestId, !requestId.isEmpty {
            parts.append("requestId:\(requestId)")
        }
        return parts.joined(separator: " ")
    }

    var detailText: String {
        var lines: [String] = [summaryLine]
        if let requestId, !requestId.isEmpty {
            lines.append("requestId: \(requestId)")
        }
        if let cookiesBefore, !cookiesBefore.isEmpty {
            lines.append("cookiesBefore: \(cookiesBefore)")
        }
        if let cookiesAfter, !cookiesAfter.isEmpty {
            lines.append("cookiesAfter: \(cookiesAfter)")
        }
        if let requestHeaders, !requestHeaders.isEmpty {
            lines.append("requestHeaders:\n\(formattedHeaders(requestHeaders))")
        }
        if let requestBodyPreview, !requestBodyPreview.isEmpty {
            lines.append("requestBody:\n\(requestBodyPreview)")
        }
        if let responseHeaders, !responseHeaders.isEmpty {
            lines.append("responseHeaders:\n\(formattedHeaders(responseHeaders))")
        }
        if let responseBodyPreview, !responseBodyPreview.isEmpty {
            lines.append("responseBody:\n\(responseBodyPreview)")
        }
        return lines.joined(separator: "\n\n")
    }

    var kindLabel: String {
        switch kind {
        case .request:
            return "REQUEST"
        case .response:
            return "RESPONSE"
        case .error:
            return "ERROR"
        case .resourceError:
            return "RESOURCE"
        case .nativeRequest:
            return "NATIVE REQ"
        case .nativeResponse:
            return "NATIVE RESP"
        }
    }

    private func formattedHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}

private enum SyntaxLanguage {
    case html
    case php
    case log
}

private struct SyntaxTextView: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let language: SyntaxLanguage

    var body: some View {
        SyntaxTextViewRepresentable(text: text, language: language, colorScheme: colorScheme)
    }
}

private struct SyntaxTextViewRepresentable: UIViewRepresentable {
    let text: String
    let language: SyntaxLanguage
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.textContainer.widthTracksTextView = true
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard context.coordinator.shouldUpdate(text: text, language: language, colorScheme: colorScheme) else {
            return
        }
        let attributed = SyntaxHighlighter.highlight(text: text,
                                                     language: language,
                                                     colorScheme: colorScheme)
        view.attributedText = attributed
    }

    final class Coordinator {
        private var lastText: String = ""
        private var lastLanguage: SyntaxLanguage?
        private var lastScheme: ColorScheme?

        func shouldUpdate(text: String, language: SyntaxLanguage, colorScheme: ColorScheme) -> Bool {
            if text == lastText, language == lastLanguage, colorScheme == lastScheme {
                return false
            }
            lastText = text
            lastLanguage = language
            lastScheme = colorScheme
            return true
        }
    }
}

private enum SyntaxHighlighter {
    static func highlight(text: String, language: SyntaxLanguage, colorScheme: ColorScheme) -> NSAttributedString {
        let fontSize = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 12)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let baseColor = colorScheme == .dark ? UIColor.white : UIColor.label
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseColor
        ]
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)

        switch language {
        case .html:
            apply(pattern: "<!--[\\s\\S]*?-->", color: .systemGreen, to: attributed)
            apply(pattern: "<[^>]+>", color: .systemBlue, to: attributed)
            apply(pattern: "\\b[a-zA-Z-:]+(?=\\=)", color: .systemTeal, to: attributed)
            apply(pattern: "\"[^\"]*\"|'[^']*'", color: .systemOrange, to: attributed)
        case .php:
            apply(pattern: "/\\*[\\s\\S]*?\\*/", color: .systemGreen, to: attributed)
            apply(pattern: "//.*", color: .systemGreen, to: attributed)
            apply(pattern: "#.*", color: .systemGreen, to: attributed)
            apply(pattern: "\"[^\"]*\"|'[^']*'", color: .systemOrange, to: attributed)
            apply(pattern: "\\$[a-zA-Z_][a-zA-Z0-9_]*", color: .systemTeal, to: attributed)
            apply(pattern: "\\b(function|class|public|private|protected|static|if|else|elseif|foreach|for|while|switch|case|return|new|try|catch|throw|namespace|use|extends|implements)\\b",
                  color: .systemBlue,
                  to: attributed)
        case .log:
            apply(pattern: "\\[error\\]", color: .systemRed, to: attributed)
            apply(pattern: "\\[warn\\]", color: .systemOrange, to: attributed)
            apply(pattern: "\\[info\\]", color: .systemBlue, to: attributed)
            apply(pattern: "\\[debug\\]", color: .systemGray, to: attributed)
        }

        return attributed
    }

    private static func apply(pattern: String, color: UIColor, to attributed: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(location: 0, length: attributed.string.utf16.count)
        regex.enumerateMatches(in: attributed.string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }
}

private struct ParsedPhpOutput {
    let headers: [String: [String]]
    let body: String
    let statusCode: Int
    let mimeType: String?
    let textEncoding: String?
    let location: String?
    let hadHeaders: Bool
}

private func parseContentTypeHeader(_ value: String) -> (mimeType: String?, textEncoding: String?) {
    let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let first = parts.first, !first.isEmpty else {
        return (nil, nil)
    }
    let mimeType = String(first)
    let charsetPart = parts.first(where: { $0.lowercased().hasPrefix("charset=") })
    let textEncoding = charsetPart?.split(separator: "=", maxSplits: 1).last.map(String.init)
    return (mimeType, textEncoding)
}

private func parsePhpOutput(_ output: String) -> ParsedPhpOutput {
    let separatorRange: Range<String.Index>?
    if let range = output.range(of: "\r\n\r\n") {
        separatorRange = range
    } else {
        separatorRange = output.range(of: "\n\n")
    }
    guard let separatorRange else {
        return ParsedPhpOutput(headers: [:],
                               body: output,
                               statusCode: 200,
                               mimeType: nil,
                               textEncoding: nil,
                               location: nil,
                               hadHeaders: false)
    }

    let headerPart = String(output[..<separatorRange.lowerBound])
    let bodyPart = String(output[separatorRange.upperBound...])
    var headers: [String: [String]] = [:]
    var statusCode: Int?
    var hadHeaderFields = false

    let lines = headerPart.components(separatedBy: .newlines)
    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("HTTP/") {
            let components = line.split(separator: " ")
            if components.count >= 2, let code = Int(components[1]) {
                statusCode = code
                hadHeaderFields = true
            }
            continue
        }
        let lower = line.lowercased()
        if lower.hasPrefix("status:") {
            let value = line.dropFirst("Status:".count).trimmingCharacters(in: .whitespaces)
            if let code = Int(value.split(separator: " ").first ?? "") {
                statusCode = code
                hadHeaderFields = true
            }
            continue
        }
        guard let colonIndex = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        let lowerKey = key.lowercased()
        headers[lowerKey, default: []].append(value)
        hadHeaderFields = true
    }

    guard hadHeaderFields else {
        return ParsedPhpOutput(headers: [:],
                               body: output,
                               statusCode: 200,
                               mimeType: nil,
                               textEncoding: nil,
                               location: nil,
                               hadHeaders: false)
    }

    let contentType = headers["content-type"]?.first
    var mimeType: String?
    var textEncoding: String?
    if let contentType {
        let parsed = parseContentTypeHeader(contentType)
        mimeType = parsed.mimeType
        textEncoding = parsed.textEncoding
    }

    let location = headers["location"]?.first
    let status = statusCode ?? 200

    return ParsedPhpOutput(headers: headers,
                           body: bodyPart,
                           statusCode: status,
                           mimeType: mimeType,
                           textEncoding: textEncoding,
                           location: location,
                           hadHeaders: true)
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
        case network
        case source
        case php

        var id: String { rawValue }

        var title: String {
            switch self {
            case .console:
                return "Console log"
            case .network:
                return "Network log"
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
            case .network:
                return "network"
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
    @State private var expandedNetworkEventID: String?
    @State private var didRunStartupDiagnostics = false

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

        let homeLogStore = WebLogStore()
        let managerLogStore = WebLogStore()
        let homeSchemeHandler = PhpIOSSchemeHandler(sessionID: sessionID,
                                                    logStore: homeLogStore,
                                                    dataStore: dataStore)
        let managerSchemeHandler = PhpIOSSchemeHandler(sessionID: sessionID,
                                                       logStore: managerLogStore,
                                                       dataStore: dataStore)
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

    private var activeNetworkEvents: [NetworkEvent] {
        activeLogStore.networkEvents.sorted { $0.time > $1.time }
    }

    private var logProvider: some LogProvider {
        ClosureLogProvider(
            consoleLog: {
                activeLogStore.console.joined(separator: "\n")
            },
            networkLog: {
                activeLogStore.networkEvents.map { $0.summaryLine }.joined(separator: "\n")
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
                expandedNetworkEventID = nil
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
            UITabBar.appearance().isHidden = true
            configureWebViewStore(homeWebViewStore, logStore: homeLogStore, tab: .home)
            configureWebViewStore(managerWebViewStore, logStore: managerLogStore, tab: .manager)
            updateWebViewStyles()
            runStartupDiagnosticsIfNeeded()
            Task.detached(priority: .userInitiated) {
                do {
                    let root = try EvoSiteInstaller.ensureInstalled()
                    await MainActor.run {
                        homeSchemeHandler.setInstalledRoot(root)
                        managerSchemeHandler.setInstalledRoot(root)
                    }
                } catch {
                    await MainActor.run {
                        updateContentState(for: .home) { state in
                            state.errorMessage = error.localizedDescription
                        }
                        updateContentState(for: .manager) { state in
                            state.errorMessage = error.localizedDescription
                        }
                        homeLogStore.appendPhp("install error:\n\(error.localizedDescription)")
                        managerLogStore.appendPhp("install error:\n\(error.localizedDescription)")
                    }
                }
            }

            if !homeContent.hasLoaded {
                loadPage(.home)
            }
        }
    }

    private func webContentView(state: TabContentState, store: WebViewStore) -> some View {
        ZStack {
            WebViewContainer(store: store, html: state.htmlOutput, baseURL: state.baseURL)
                .background(Color(.systemBackground))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        VStack(spacing: 0) {
            logPanelHeader
            Divider()
            logPanelContent
            Divider()
            logPanelFooter
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 440, maxWidth: 560, minHeight: 280, idealHeight: 420, maxHeight: 640)
    }

    private var logPanelHeader: some View {
        HStack {
            Text(activeLogPanel?.title ?? "Logs")
                .font(.headline)
            Spacer()
            if activeLogPanel == .network {
                Button {
                    activeLogStore.clearNetwork()
                    expandedNetworkEventID = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear network log")
            }
            Button {
                isLogPanelPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close log panel")
        }
        .padding(.bottom, 10)
    }

    private var logPanelContent: some View {
        Group {
            if isLogLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isActiveLogEmpty {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if activeLogPanel == .network {
                networkLogView
            } else {
                ScrollView {
                    SyntaxTextView(text: logContent, language: syntaxLanguage(for: activeLogPanel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .refreshable {
                    await refreshLogContent()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logPanelFooter: some View {
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
        .padding(.top, 10)
    }

    private var isActiveLogEmpty: Bool {
        switch activeLogPanel {
        case .network:
            return activeNetworkEvents.isEmpty
        default:
            return logContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func syntaxLanguage(for panel: LogPanel?) -> SyntaxLanguage {
        switch panel {
        case .source:
            return .html
        case .php:
            return .php
        default:
            return .log
        }
    }

    private var networkLogView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(activeNetworkEvents) { event in
                    networkRow(for: event)
                }
            }
            .padding(.vertical, 4)
        }
        .refreshable {
            await refreshLogContent()
        }
    }

    @ViewBuilder
    private func networkRow(for event: NetworkEvent) -> some View {
        let isExpanded = expandedNetworkEventID == event.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(event.methodText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 48, alignment: .leading)
                Text(event.statusText)
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
                Text(event.durationText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Text(event.kindLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(event.url)
                .font(.caption2)
                .lineLimit(1)

            if isExpanded {
                networkDetailView(for: event)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedNetworkEventID = isExpanded ? nil : event.id
            }
        }
    }

    private func networkDetailView(for event: NetworkEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.url)
                .font(.caption2)
                .textSelection(.enabled)
            if let status = event.status {
                Text("Status: \(status)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let duration = event.durationMs {
                Text("Time: \(duration)ms")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let requestId = event.requestId {
                Text("Request ID: \(requestId)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let error = event.error, !error.isEmpty {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let tag = event.tag, !tag.isEmpty {
                Text("Tag: \(tag)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let cookiesBefore = event.cookiesBefore, !cookiesBefore.isEmpty {
                detailSection(title: "Cookies before", text: cookiesBefore)
            }
            if let cookiesAfter = event.cookiesAfter, !cookiesAfter.isEmpty {
                detailSection(title: "Cookies after", text: cookiesAfter)
            }
            if let requestHeaders = event.requestHeaders, !requestHeaders.isEmpty {
                detailSection(title: "Request headers", text: formatHeaders(requestHeaders))
            }
            if let requestBody = event.requestBodyPreview, !requestBody.isEmpty {
                detailSection(title: "Request body", text: requestBody)
            }
            if let responseHeaders = event.responseHeaders, !responseHeaders.isEmpty {
                detailSection(title: "Response headers", text: formatHeaders(responseHeaders))
            }
            if let responseBody = event.responseBodyPreview, !responseBody.isEmpty {
                detailSection(title: "Response body", text: responseBody)
            }
        }
        .padding(.top, 4)
    }

    private func formatHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption2)
                .textSelection(.enabled)
        }
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
        expandedNetworkEventID = nil
        Task { await refreshLogContent() }
    }

    private var currentCopyText: String {
        if activeLogPanel == .network {
            if let expandedID = expandedNetworkEventID,
               let event = activeNetworkEvents.first(where: { $0.id == expandedID }) {
                return event.detailText
            }
            return activeNetworkEvents.map { $0.summaryLine }.joined(separator: "\n")
        }
        return logContent
    }

    private func handleCopy() {
        UIPasteboard.general.string = currentCopyText
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        didCopy = true
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            } catch {
                return
            }
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
        case .network:
            return await provider.fetchNetworkLog()
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
        let cookieStore = webViewStore(for: page).webView.configuration.websiteDataStore.httpCookieStore
        logStore.reset()
        Task.detached(priority: .userInitiated) {
            do {
                let result = try await runEvoPage(page, sessionID: sessionID, cookieStore: cookieStore)
                await MainActor.run {
                    updateContentState(for: page) { state in
                        state.htmlOutput = result.output
                        state.baseURL = result.baseURL
                        state.isLoading = false
                    }
                    logStore.setPhpLogs(result.phpLogs)
                    logStore.setCurrentScriptURL(result.scriptURL)
                    logStore.setLastHtmlOutput(result.output)
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
                    logStore.setLastHtmlOutput("")
                }
            }
        }
    }

    private func configureWebViewStore(_ store: WebViewStore, logStore: WebLogStore, tab: NavigationTab) {
        store.onConsoleLine = { line in
            logStore.appendConsole(line)
        }
        store.onNetworkEvent = { event in
            logStore.appendNetworkEvent(event)
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

    private func webViewStore(for tab: NavigationTab) -> WebViewStore {
        switch tab {
        case .home:
            return homeWebViewStore
        case .manager:
            return managerWebViewStore
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

    private func runStartupDiagnosticsIfNeeded() {
        guard !didRunStartupDiagnostics else { return }
        didRunStartupDiagnostics = true
        Task.detached(priority: .background) {
            let diagnostics = Self.collectStartupDiagnostics()
            let lines = diagnostics.lines
            let iniMissing = diagnostics.iniMissing
            await MainActor.run {
                for line in lines {
                    homeLogStore.appendPhp(line)
                    managerLogStore.appendPhp(line)
                }
                if iniMissing {
                    updateContentState(for: .home) { state in
                        if state.errorMessage == nil {
                            state.errorMessage = "Missing php.ini; using defaults."
                        }
                    }
                    updateContentState(for: .manager) { state in
                        if state.errorMessage == nil {
                            state.errorMessage = "Missing php.ini; using defaults."
                        }
                    }
                }
            }
        }
    }

    private nonisolated static func collectStartupDiagnostics() -> (lines: [String], iniMissing: Bool) {
        var lines: [String] = []
        var iniMissing = false
        do {
            let engine = try PhpEngine.shared()
            if let iniPath = engine.resolvedIniPath {
                lines.append("php.ini: \(iniPath)")
            } else {
                lines.append("php.ini missing; using defaults")
                iniMissing = true
            }
            switch engine.selfTest() {
            case .success(let result):
                lines.append("php self-test: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            case .failure(let error):
                lines.append("php self-test error: \(error.localizedDescription)")
            }
        } catch {
            lines.append("php init error: \(error.localizedDescription)")
        }
        return (lines, iniMissing)
    }

    private func loadSourceCode() -> String {
        let html = activeLogStore.lastHtmlOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !html.isEmpty {
            return html
        }
        return "HTML output unavailable yet."
    }

    private func storeCookies(from headers: [String: [String]],
                              for url: URL,
                              cookieStore: WKHTTPCookieStore) {
        guard let values = headers["set-cookie"], !values.isEmpty else { return }
        let host = url.host ?? "localhost"
        let path = url.path.isEmpty ? "/" : url.path
        let httpURL = URL(string: "http://\(host)\(path)") ?? URL(string: "http://\(host)/")!
        for value in values {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: httpURL)
            for cookie in cookies {
                cookieStore.setCookie(cookie)
            }
        }
    }

    private func cookieHeader(for url: URL, cookieStore: WKHTTPCookieStore) async -> String? {
        let host = url.host ?? "localhost"
        let path = url.path.isEmpty ? "/" : url.path
        return await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                let relevant = cookies.filter { cookie in
                    let domainMatch = cookie.domain == host
                        || cookie.domain == ".\(host)"
                        || host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    let pathMatch = path.hasPrefix(cookie.path)
                    return domainMatch && pathMatch
                }
                if relevant.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    let header = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    continuation.resume(returning: header)
                }
            }
        }
    }

    private func runEvoPage(_ page: NavigationTab,
                            sessionID: String,
                            cookieStore: WKHTTPCookieStore) async throws -> (output: String, baseURL: URL, phpLogs: [String], scriptURL: URL) {
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
            _ = try? "".write(toFile: errorLogPath, atomically: true, encoding: .utf8)
        }

        let engine = try PhpEngine.shared()
        let refererURL = "phpios://localhost" + page.envRequestUri
        let siteRootPath = siteRoot.path.hasSuffix("/") ? siteRoot.path : siteRoot.path + "/"
        let siteRootURL = "phpios://localhost/"
        let managerPath = siteRoot.appendingPathComponent("manager", isDirectory: true).path
        let managerPathWithSlash = managerPath.hasSuffix("/") ? managerPath : managerPath + "/"
        let managerURL = siteRootURL + "manager/"
        let storedCookieHeader = await cookieHeader(for: pageBaseURL, cookieStore: cookieStore) ?? ""
        let cookieHeaderValue: String
        if storedCookieHeader.contains("PHPSESSID=") {
            cookieHeaderValue = storedCookieHeader
        } else if storedCookieHeader.isEmpty {
            cookieHeaderValue = "PHPSESSID=\(sessionID)"
        } else {
            cookieHeaderValue = "PHPSESSID=\(sessionID); \(storedCookieHeader)"
        }

        let shimsFlag = "1"
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
                "HTTP_COOKIE": cookieHeaderValue,
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
                "PHP_IOS_DEBUG": "1",
                "PHP_IOS_SHIMS": shimsFlag
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

        let shimsEnabled = !["0", "false", "off"].contains(shimsFlag.lowercased())
        var phpLogs: [String] = ["exitCode: \(result.exitCode)",
                                 "shims: \(shimsEnabled ? "on" : "off")"]
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

        var headers: [String: [String]] = [:]
        for (key, values) in result.responseHeaders {
            headers[key.lowercased(), default: []].append(contentsOf: values)
        }
        var bodyOutput = result.stdout
        if headers.isEmpty {
            let parsed = parsePhpOutput(result.stdout)
            if parsed.hadHeaders {
                headers = parsed.headers
                bodyOutput = parsed.body
            }
        }
        storeCookies(from: headers,
                     for: pageBaseURL,
                     cookieStore: cookieStore)
        let trimmedOutput = bodyOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty {
            let fallback = stderr.isEmpty ? "Empty output from PHP." : escapeHtml(stderr)
            return ("<html><body><pre>\(fallback)</pre></body></html>", pageBaseURL, phpLogs, scriptURL)
        }
        return (bodyOutput, pageBaseURL, phpLogs, scriptURL)
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
    var onNetworkEvent: (NetworkEvent) -> Void = { _ in }
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
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        super.init()

        let scriptSource = """
        (function() {
          function safeStringify(value) {
            if (typeof value === 'string') { return value; }
            try { return JSON.stringify(value); } catch (e) { return String(value); }
          }

          function createId() {
            return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
          }

          function stringifyArgs(args) {
            return Array.prototype.slice.call(args).map(safeStringify).join(' ');
          }

          function limitText(value, maxLen) {
            var text = String(value || '');
            if (text.length <= maxLen) { return text; }
            return text.slice(0, maxLen) + '\\n... (truncated)';
          }

          var SENSITIVE_KEYS = ['password', 'pass', 'pwd', 'token', 'authorization', 'cookie', 'set-cookie'];

          function isSensitiveKey(key) {
            var lower = String(key || '').toLowerCase();
            return SENSITIVE_KEYS.indexOf(lower) !== -1;
          }

          function redactCookieString(cookieString) {
            if (!cookieString) { return ''; }
            return cookieString.split(';').map(function(part) {
              var trimmed = part.trim();
              if (!trimmed) { return ''; }
              var idx = trimmed.indexOf('=');
              if (idx < 0) { return trimmed; }
              var name = trimmed.slice(0, idx).trim();
              return name + '=***';
            }).filter(Boolean).join('; ');
          }

          function sanitizeHeaderValue(key, value) {
            if (isSensitiveKey(key)) {
              return '<redacted>';
            }
            if (String(key || '').toLowerCase() === 'cookie' || String(key || '').toLowerCase() === 'set-cookie') {
              return redactCookieString(value);
            }
            return value;
          }

          function sanitizeHeaders(headersObj) {
            var sanitized = {};
            if (!headersObj) { return sanitized; }
            var total = 0;
            Object.keys(headersObj).forEach(function(key) {
              var value = String(headersObj[key]);
              value = sanitizeHeaderValue(key, value);
              total += key.length + value.length;
              if (total > 8192) {
                sanitized['...'] = '<truncated>';
                return;
              }
              sanitized[key] = value;
            });
            return sanitized;
          }

          function headersToObject(headers) {
            if (!headers) { return {}; }
            var output = {};
            if (headers.forEach) {
              headers.forEach(function(value, key) {
                output[key] = value;
              });
              return output;
            }
            if (Array.isArray(headers)) {
              headers.forEach(function(pair) {
                if (pair && pair.length >= 2) {
                  output[pair[0]] = pair[1];
                }
              });
              return output;
            }
            if (typeof headers === 'object') {
              Object.keys(headers).forEach(function(key) {
                output[key] = headers[key];
              });
            }
            return output;
          }

          function redactObject(value) {
            if (Array.isArray(value)) {
              return value.map(redactObject);
            }
            if (value && typeof value === 'object') {
              var result = {};
              Object.keys(value).forEach(function(key) {
                if (isSensitiveKey(key)) {
                  result[key] = '<redacted>';
                } else {
                  result[key] = redactObject(value[key]);
                }
              });
              return result;
            }
            return value;
          }

          function redactUrlEncoded(text) {
            return text.split('&').map(function(pair) {
              var parts = pair.split('=');
              var key = decodeURIComponent(parts[0] || '');
              if (isSensitiveKey(key)) {
                return encodeURIComponent(key) + '=***';
              }
              return pair;
            }).join('&');
          }

          function redactTextBody(text, headersObj) {
            var trimmed = text.trim();
            var contentType = '';
            if (headersObj) {
              contentType = headersObj['content-type'] || headersObj['Content-Type'] || '';
            }
            contentType = String(contentType).toLowerCase();
            if (contentType.indexOf('application/json') !== -1 || trimmed.indexOf('{') === 0 || trimmed.indexOf('[') === 0) {
              try {
                var parsed = JSON.parse(text);
                return JSON.stringify(redactObject(parsed));
              } catch (e) {}
            }
            if (contentType.indexOf('application/x-www-form-urlencoded') !== -1) {
              return redactUrlEncoded(text);
            }
            return text;
          }

          function bodyPreview(body, headersObj, limit) {
            if (typeof body === 'string') {
              return limitText(redactTextBody(body, headersObj), limit);
            }
            if (body && body.toString && body.toString() === '[object URLSearchParams]') {
              return limitText(redactUrlEncoded(body.toString()), limit);
            }
            if (body && body.toString && body.toString() === '[object FormData]') {
              var data = {};
              try {
                body.forEach(function(value, key) {
                  if (isSensitiveKey(key)) {
                    data[key] = '<redacted>';
                  } else if (value && value.name) {
                    data[key] = '<file ' + value.name + '>';
                  } else {
                    data[key] = String(value);
                  }
                });
                return limitText(JSON.stringify(data), limit);
              } catch (e) {
                return '<form-data>';
              }
            }
            if (body && body.byteLength !== undefined) {
              return '<binary ' + body.byteLength + ' bytes>';
            }
            if (body && body.size !== undefined) {
              return '<binary ' + body.size + ' bytes>';
            }
            return '';
          }

          function parseHeaderLines(raw) {
            var headers = {};
            if (!raw) { return headers; }
            raw.split(/\\r?\\n/).forEach(function(line) {
              var idx = line.indexOf(':');
              if (idx > 0) {
                var key = line.slice(0, idx).trim();
                var value = line.slice(idx + 1).trim();
                if (key) { headers[key] = value; }
              }
            });
            return headers;
          }

          function shouldReadBody(contentType) {
            var type = String(contentType || '').toLowerCase();
            return type.indexOf('text/') !== -1
              || type.indexOf('application/json') !== -1
              || type.indexOf('application/javascript') !== -1
              || type.indexOf('application/xml') !== -1
              || type.indexOf('text/html') !== -1;
          }

          function postMessage(payload) {
            try { window.webkit.messageHandlers.jsLog.postMessage(payload); } catch (e) {}
          }

          function logConsole(level, message) {
            postMessage({ channel: 'console', level: level, message: message, time: Date.now() });
          }

          function logNetwork(event, detail) {
            var payload = { channel: 'network', event: event, time: Date.now(), id: createId() };
            for (var key in detail) { payload[key] = detail[key]; }
            postMessage(payload);
          }

          function hookConsole() {
            ['log','info','warn','error','debug'].forEach(function(level) {
              var original = console[level];
              if (original && original.__phpiosWrapped) { return; }
              console[level] = function() {
                try { logConsole(level, stringifyArgs(arguments)); } catch (e) {}
                if (original) { original.apply(console, arguments); }
              };
              console[level].__phpiosWrapped = true;
            });
          }

          function installLogger() {
            hookConsole();
            if (!window.__phpiosDidLogBootstrap) {
              window.__phpiosDidLogBootstrap = true;
              logConsole('debug', 'phpios logger attached');
            }
          }

          installLogger();
          document.addEventListener('DOMContentLoaded', installLogger, true);
          window.addEventListener('pageshow', installLogger, true);

          if (!window.__phpiosErrorHandlerInstalled) {
            window.__phpiosErrorHandlerInstalled = true;
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
          }

          if (window.fetch) {
            var originalFetch = window.fetch;
            window.fetch = function(input, init) {
              var method = (init && init.method) || (input && input.method) || 'GET';
              var url = (typeof input === 'string') ? input : (input && input.url) || '';
              var start = Date.now();
              var requestId = createId();
              var requestHeaders = sanitizeHeaders(headersToObject((init && init.headers) || (input && input.headers)));
              var requestBodyPreview = bodyPreview(init && init.body, requestHeaders, 4096);
              var cookiesBefore = redactCookieString(document.cookie || '');
              logNetwork('request', {
                requestId: requestId,
                method: method,
                url: String(url),
                requestHeaders: requestHeaders,
                requestBodyPreview: requestBodyPreview,
                cookiesBefore: cookiesBefore
              });
              return originalFetch.apply(this, arguments).then(function(response) {
                var responseHeaders = sanitizeHeaders(headersToObject(response.headers));
                var contentType = response.headers.get('content-type') || '';
                var cookiesAfter = redactCookieString(document.cookie || '');
                var detail = {
                  requestId: requestId,
                  method: method,
                  url: String(response.url || url),
                  status: response.status,
                  durationMs: Date.now() - start,
                  requestHeaders: requestHeaders,
                  requestBodyPreview: requestBodyPreview,
                  responseHeaders: responseHeaders,
                  cookiesBefore: cookiesBefore,
                  cookiesAfter: cookiesAfter
                };
                if (shouldReadBody(contentType)) {
                  return response.clone().text().then(function(text) {
                    detail.responseBodyPreview = limitText(redactTextBody(text, responseHeaders), 8192);
                    logNetwork('response', detail);
                    return response;
                  }).catch(function() {
                    logNetwork('response', detail);
                    return response;
                  });
                }
                detail.responseBodyPreview = '<non-text body>';
                logNetwork('response', detail);
                return response;
              }).catch(function(error) {
                logNetwork('error', {
                  requestId: requestId,
                  method: method,
                  url: String(url),
                  error: safeStringify(error),
                  durationMs: Date.now() - start,
                  requestHeaders: requestHeaders,
                  requestBodyPreview: requestBodyPreview,
                  cookiesBefore: cookiesBefore
                });
                throw error;
              });
            };
          }

          if (window.XMLHttpRequest) {
            var originalOpen = XMLHttpRequest.prototype.open;
            var originalSend = XMLHttpRequest.prototype.send;
            var originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
            XMLHttpRequest.prototype.open = function(method, url) {
              this.__phpiosRequest = { id: createId(), method: method, url: url, start: 0, headers: {} };
              return originalOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
              if (this.__phpiosRequest) {
                this.__phpiosRequest.headers[name] = value;
              }
              return originalSetHeader.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function(body) {
              var request = this.__phpiosRequest;
              if (request) {
                request.start = Date.now();
                var requestHeaders = sanitizeHeaders(request.headers || {});
                var requestBodyPreview = bodyPreview(body, requestHeaders, 4096);
                var cookiesBefore = redactCookieString(document.cookie || '');
                logNetwork('request', {
                  requestId: request.id,
                  method: request.method,
                  url: String(request.url),
                  requestHeaders: requestHeaders,
                  requestBodyPreview: requestBodyPreview,
                  cookiesBefore: cookiesBefore
                });
                var finalize = function(eventType) {
                  var rawHeaders = parseHeaderLines(this.getAllResponseHeaders && this.getAllResponseHeaders());
                  var responseHeaders = sanitizeHeaders(rawHeaders);
                  var cookiesAfter = redactCookieString(document.cookie || '');
                  var detail = {
                    requestId: request.id,
                    method: request.method,
                    url: String(request.url),
                    status: this.status,
                    durationMs: Date.now() - request.start,
                    requestHeaders: requestHeaders,
                    requestBodyPreview: requestBodyPreview,
                    responseHeaders: responseHeaders,
                    cookiesBefore: cookiesBefore,
                    cookiesAfter: cookiesAfter,
                    event: eventType
                  };
                  var contentType = responseHeaders['content-type'] || responseHeaders['Content-Type'] || '';
                  if (shouldReadBody(contentType)) {
                    detail.responseBodyPreview = limitText(redactTextBody(this.responseText || '', responseHeaders), 8192);
                  } else if (this.responseType && this.responseType !== '' && this.responseType !== 'text') {
                    detail.responseBodyPreview = '<non-text body>';
                  }
                  logNetwork(eventType === 'load' ? 'response' : 'error', detail);
                };
                this.addEventListener('load', function() { finalize.call(this, 'load'); });
                this.addEventListener('error', function() { finalize.call(this, 'error'); });
                this.addEventListener('abort', function() { finalize.call(this, 'abort'); });
              }
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
        let adjustedHTML = ensureViewportMeta(in: html)
        guard adjustedHTML != lastLoadedHTML || baseURL != lastLoadedBaseURL else { return }
        lastLoadedHTML = adjustedHTML
        lastLoadedBaseURL = baseURL
        webView.loadHTMLString(adjustedHTML, baseURL: baseURL)
    }

    private func ensureViewportMeta(in html: String) -> String {
        let lower = html.lowercased()
        if lower.contains("name=\"viewport\"") || lower.contains("name='viewport'") || lower.contains("name=viewport") {
            return html
        }
        let meta = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1\">"
        if let headRange = html.range(of: "<head", options: [.caseInsensitive]) {
            if let closeRange = html[headRange.upperBound...].range(of: ">") {
                let insertIndex = closeRange.upperBound
                let before = String(html.prefix(upTo: insertIndex))
                let after = String(html.suffix(from: insertIndex))
                return before + meta + after
            }
        }
        if let htmlRange = html.range(of: "<html", options: [.caseInsensitive]),
           let closeRange = html[htmlRange.upperBound...].range(of: ">") {
            let insertIndex = closeRange.upperBound
            let before = String(html.prefix(upTo: insertIndex))
            let after = String(html.suffix(from: insertIndex))
            return before + "<head>" + meta + "</head>" + after
        }
        return "<head>\(meta)</head>\(html)"
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
            if let event = makeNetworkEvent(from: body) {
                appendNetworkEvent(event)
            }
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

    private func appendNetworkEvent(_ event: NetworkEvent) {
        DispatchQueue.main.async {
            self.onNetworkEvent(event)
        }
    }

    private func makeNetworkEvent(from body: [String: Any]) -> NetworkEvent? {
        guard let url = body["url"] as? String else { return nil }
        let event = body["event"] as? String ?? "event"
        let kind: NetworkEvent.Kind
        switch event {
        case "request":
            kind = .request
        case "response":
            kind = .response
        case "error":
            kind = .error
        case "resource-error":
            kind = .resourceError
        default:
            kind = .error
        }
        let id = body["id"] as? String ?? UUID().uuidString
        let requestId = body["requestId"] as? String
        let method = body["method"] as? String
        let status = (body["status"] as? NSNumber)?.intValue ?? body["status"] as? Int
        let duration = (body["durationMs"] as? NSNumber)?.intValue ?? body["durationMs"] as? Int
        let error = body["error"] as? String
        let tag = body["tag"] as? String
        let requestHeaders = sanitizeHeaders(stringMap(from: body["requestHeaders"]))
        let responseHeaders = sanitizeHeaders(stringMap(from: body["responseHeaders"]))
        let requestBodyPreview = limitedText(body["requestBodyPreview"] as? String, limit: 4096)
        let responseBodyPreview = limitedText(body["responseBodyPreview"] as? String, limit: 8192)
        let cookiesBefore = redactCookieHeader(body["cookiesBefore"] as? String)
        let cookiesAfter = redactCookieHeader(body["cookiesAfter"] as? String)
        let time: Date
        if let timestamp = (body["time"] as? NSNumber)?.doubleValue {
            time = Date(timeIntervalSince1970: timestamp / 1000.0)
        } else {
            time = Date()
        }
        return NetworkEvent(id: id,
                            requestId: requestId,
                            kind: kind,
                            method: method,
                            url: url,
                            status: status,
                            durationMs: duration,
                            error: error,
                            tag: tag,
                            time: time,
                            requestHeaders: requestHeaders,
                            requestBodyPreview: requestBodyPreview,
                            responseHeaders: responseHeaders,
                            responseBodyPreview: responseBodyPreview,
                            cookiesBefore: cookiesBefore,
                            cookiesAfter: cookiesAfter)
    }

    private func stringMap(from value: Any?) -> [String: String]? {
        guard let value else { return nil }
        if let map = value as? [String: String] {
            return map
        }
        if let map = value as? [String: Any] {
            var result: [String: String] = [:]
            for (key, raw) in map {
                if let stringValue = raw as? String {
                    result[key] = stringValue
                } else if let numberValue = raw as? NSNumber {
                    result[key] = numberValue.stringValue
                } else {
                    result[key] = "\(raw)"
                }
            }
            return result
        }
        return nil
    }

    private func limitedText(_ text: String?, limit: Int) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if text.count <= limit {
            return text
        }
        let truncated = text.prefix(limit)
        return "\(truncated)\n... (truncated)"
    }

    private func sanitizeHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers, !headers.isEmpty else { return headers }
        var result: [String: String] = [:]
        for (key, value) in headers {
            let lower = key.lowercased()
            if lower == "cookie" || lower == "set-cookie" {
                result[key] = redactCookieHeader(value) ?? ""
            } else if isSensitiveKey(lower) {
                result[key] = "<redacted>"
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func redactCookieHeader(_ header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        let parts = header.split(separator: ";")
        let redacted = parts.compactMap { part -> String? in
            let pair = part.split(separator: "=", maxSplits: 1)
            guard let name = pair.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return nil
            }
            return "\(name)=***"
        }
        return redacted.joined(separator: "; ")
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let sensitive = ["password", "pass", "pwd", "token", "authorization"]
        return sensitive.contains(key.lowercased())
    }
}

final class WebLogStore: ObservableObject {
    @Published var console: [String] = []
    @Published var networkEvents: [NetworkEvent] = []
    @Published var php: [String] = []
    @Published var currentScriptURL: URL?
    @Published var lastHtmlOutput: String = ""

    func reset() {
        updateOnMain {
            self.console.removeAll()
            self.networkEvents.removeAll()
            self.php.removeAll()
            self.currentScriptURL = nil
            self.lastHtmlOutput = ""
        }
    }

    func appendConsole(_ line: String) {
        updateOnMain {
            self.console = self.append(line, to: self.console, limit: 300)
        }
    }

    func appendNetworkEvent(_ event: NetworkEvent) {
        updateOnMain {
            self.networkEvents = self.append(event, to: self.networkEvents, limit: 500)
        }
    }

    func clearNetwork() {
        updateOnMain {
            self.networkEvents.removeAll()
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

    func setLastHtmlOutput(_ output: String) {
        updateOnMain {
            self.lastHtmlOutput = output
        }
    }

    private func append<T>(_ item: T, to logs: [T], limit: Int) -> [T] {
        var updated = logs
        updated.append(item)
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
    private struct PhpResponse {
        let data: Data
        let output: String
        let mimeType: String
        let textEncoding: String?
        let headers: [String: [String]]
        let statusCode: Int
        let location: String?
        let logEntry: String
    }

    private let sessionID: String
    private let logStore: WebLogStore
    private let cookieStore: WKHTTPCookieStore
    private let requestQueue = DispatchQueue(label: "phpios.scheme", attributes: .concurrent)
    private let rootLock = NSLock()
    private var installedRoot: URL?

    init(sessionID: String, logStore: WebLogStore, dataStore: WKWebsiteDataStore) {
        self.sessionID = sessionID
        self.logStore = logStore
        self.cookieStore = dataStore.httpCookieStore
    }

    private func currentSiteRoot() throws -> URL {
        rootLock.lock()
        let cached = installedRoot
        rootLock.unlock()
        if let cached {
            return cached
        }
        let root = try EvoSiteInstaller.ensureInstalled()
        setInstalledRoot(root)
        return root
    }

    private func cookieHeader(for url: URL, requestHeader: String?) -> String? {
        let host = url.host ?? "localhost"
        let path = url.path.isEmpty ? "/" : url.path
        let semaphore = DispatchSemaphore(value: 0)
        var storeHeader: String?
        cookieStore.getAllCookies { cookies in
            let relevant = cookies.filter { cookie in
                let domainMatch = cookie.domain == host
                    || cookie.domain == ".\(host)"
                    || host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                let pathMatch = path.hasPrefix(cookie.path)
                return domainMatch && pathMatch
            }
            if relevant.isEmpty {
                storeHeader = nil
            } else {
                storeHeader = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
            semaphore.signal()
        }
        semaphore.wait()
        return mergeCookieHeaders(storeHeader, requestHeader)
    }

    private func mergeCookieHeaders(_ primary: String?, _ secondary: String?) -> String? {
        var merged: [String: String] = [:]
        func ingest(_ header: String?) {
            guard let header, !header.isEmpty else { return }
            let parts = header.split(separator: ";")
            for part in parts {
                let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard pair.count == 2 else { continue }
                merged[String(pair[0])] = String(pair[1])
            }
        }
        ingest(primary)
        ingest(secondary)
        if merged.isEmpty {
            return nil
        }
        return merged.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func storeCookies(from headers: [String: [String]], for url: URL) {
        guard let values = headers["set-cookie"], !values.isEmpty else { return }
        let host = url.host ?? "localhost"
        let path = url.path.isEmpty ? "/" : url.path
        let httpURL = URL(string: "http://\(host)\(path)") ?? URL(string: "http://\(host)/")!
        for value in values {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: httpURL)
            for cookie in cookies {
                cookieStore.setCookie(cookie)
            }
        }
    }

    func setInstalledRoot(_ url: URL) {
        rootLock.lock()
        installedRoot = url
        rootLock.unlock()
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
        let requestId = UUID().uuidString
        let startTime = Date()
        var requestHeaders = task.request.allHTTPHeaderFields ?? [:]
        let cookieHeaderValue = cookieHeader(for: url,
                                             requestHeader: task.request.value(forHTTPHeaderField: "Cookie"))
        if let cookieHeaderValue, requestHeaders["Cookie"] == nil {
            requestHeaders["Cookie"] = cookieHeaderValue
        }
        let redactedRequestHeaders = redactHeaders(requestHeaders)
        let cookiesBefore = redactCookieHeader(cookieHeaderValue)
        let bodyData = requestBody(from: task.request) ?? Data()
        let requestBodyPreview = previewBody(data: bodyData,
                                             contentType: requestHeaders["Content-Type"],
                                             limit: 4096)
        logNetworkEvent(kind: .nativeRequest,
                        method: method,
                        url: url,
                        requestId: requestId,
                        status: nil,
                        durationMs: nil,
                        tag: nil,
                        error: nil,
                        requestHeaders: redactedRequestHeaders,
                        requestBodyPreview: requestBodyPreview,
                        cookiesBefore: cookiesBefore)

        do {
            let siteRoot = try currentSiteRoot()
            let resolved = try resolveFileURL(for: url,
                                              request: task.request,
                                              siteRoot: siteRoot)
            if resolved.isPhp {
                let requestPathOverride = overrideRequestPath(for: url, resolved: resolved)
                let response = try runPhp(for: task.request,
                                          bodyData: bodyData,
                                          url: url,
                                          scriptURL: resolved.fileURL,
                                          siteRoot: siteRoot,
                                          requestPathOverride: requestPathOverride,
                                          requestId: requestId,
                                          cookieHeader: cookieHeaderValue)
                storeCookies(from: response.headers, for: url)
                let cookiesAfter = redactCookieHeader(cookieHeader(for: url, requestHeader: nil))
                let responseHeaders = redactHeaders(flattenHeaders(response.headers))
                let responseBodyPreview = previewText(response.output,
                                                      contentType: response.mimeType,
                                                      limit: 8192)
                if shouldCaptureSourceOutput(mimeType: response.mimeType, output: response.output) {
                    logStore.setLastHtmlOutput(response.output)
                }

                if (300...399).contains(response.statusCode), let location = response.location {
                    let redirectURL = normalizedRedirectURL(from: location, baseURL: url)
                    let redirectHTML = redirectHtml(to: redirectURL)
                    respond(task,
                            url: url,
                            mimeType: "text/html",
                            data: Data(redirectHTML.utf8),
                            statusCode: response.statusCode,
                            headerFields: ["Location": redirectURL.absoluteString],
                            textEncoding: "utf-8")
                    let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                    logNetworkEvent(kind: .nativeResponse,
                                    method: method,
                                    url: url,
                                    requestId: requestId,
                                    status: response.statusCode,
                                    durationMs: duration,
                                    tag: "redirect",
                                    error: nil,
                                    requestHeaders: redactedRequestHeaders,
                                    requestBodyPreview: requestBodyPreview,
                                    responseHeaders: responseHeaders,
                                    responseBodyPreview: responseBodyPreview,
                                    cookiesBefore: cookiesBefore,
                                    cookiesAfter: cookiesAfter)
                    logPhp(response.logEntry, isMainDocument: resolved.isMainDocument, scriptURL: resolved.fileURL)
                    return
                }

                let headerFields = responseHeaderFields(from: response)
                respond(task,
                        url: url,
                        mimeType: response.mimeType,
                        data: response.data,
                        statusCode: response.statusCode,
                        headerFields: headerFields,
                        textEncoding: response.textEncoding ?? "utf-8")
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                logNetworkEvent(kind: .nativeResponse,
                                method: method,
                                url: url,
                                requestId: requestId,
                                status: response.statusCode,
                                durationMs: duration,
                                tag: "PHP \(response.data.count) bytes",
                                error: nil,
                                requestHeaders: redactedRequestHeaders,
                                requestBodyPreview: requestBodyPreview,
                                responseHeaders: responseHeaders,
                                responseBodyPreview: responseBodyPreview,
                                cookiesBefore: cookiesBefore,
                                cookiesAfter: cookiesAfter)
                logPhp(response.logEntry, isMainDocument: resolved.isMainDocument, scriptURL: resolved.fileURL)
            } else {
                let data = try Data(contentsOf: resolved.fileURL, options: .mappedIfSafe)
                let mimeType = mimeType(for: resolved.fileURL.pathExtension)
                let responseHeaders = redactHeaders(["Content-Type": mimeType])
                let responseBodyPreview = previewBody(data: data, contentType: mimeType, limit: 8192)
                respond(task,
                        url: url,
                        mimeType: mimeType,
                        data: data,
                        statusCode: 200,
                        headerFields: [:],
                        textEncoding: nil)
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                logNetworkEvent(kind: .nativeResponse,
                                method: method,
                                url: url,
                                requestId: requestId,
                                status: 200,
                                durationMs: duration,
                                tag: "FILE \(data.count) bytes",
                                error: nil,
                                requestHeaders: redactedRequestHeaders,
                                requestBodyPreview: requestBodyPreview,
                                responseHeaders: responseHeaders,
                                responseBodyPreview: responseBodyPreview,
                                cookiesBefore: cookiesBefore,
                                cookiesAfter: nil)
            }
        } catch {
            let message = error.localizedDescription
            let statusCode: Int
            if case PhpError.scriptNotFound = error {
                statusCode = 404
            } else {
                statusCode = 500
            }
            respond(task,
                    url: url,
                    mimeType: "text/html",
                    data: Data("<html><body><pre>\(message)</pre></body></html>".utf8),
                    statusCode: statusCode,
                    headerFields: [:],
                    textEncoding: "utf-8")
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            logNetworkEvent(kind: .error,
                            method: method,
                            url: url,
                            requestId: requestId,
                            status: statusCode,
                            durationMs: duration,
                            tag: "native",
                            error: message,
                            requestHeaders: redactedRequestHeaders,
                            requestBodyPreview: requestBodyPreview,
                            responseHeaders: ["Content-Type": "text/html"],
                            responseBodyPreview: previewText(message, contentType: "text/html", limit: 8192),
                            cookiesBefore: cookiesBefore,
                            cookiesAfter: nil)
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
                        bodyData: Data,
                        url: URL,
                        scriptURL: URL,
                        siteRoot: URL,
                        requestPathOverride: String?,
                        requestId: String,
                        cookieHeader: String?) throws -> PhpResponse {
        let engine = try PhpEngine.shared()
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
            _ = try? "".write(toFile: errorLogPath, atomically: true, encoding: .utf8)
        }

        let accept = request.value(forHTTPHeaderField: "Accept")
            ?? "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        let acceptLanguage = request.value(forHTTPHeaderField: "Accept-Language") ?? "en-US,en;q=0.9"
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? "PhpIOS/1.0 (iOS)"
        let referer = request.value(forHTTPHeaderField: "Referer") ?? ""
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let host = url.host ?? "localhost"

        let shimsFlag = "1"
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
            "PHP_IOS_DEBUG": "1",
            "PHP_IOS_SHIMS": shimsFlag
        ]

        if !contentType.isEmpty {
            env["CONTENT_TYPE"] = contentType
        }
        if !bodyData.isEmpty {
            env["CONTENT_LENGTH"] = "\(bodyData.count)"
        }

        let requestCookieHeader = cookieHeader ?? request.value(forHTTPHeaderField: "Cookie") ?? ""
        if requestCookieHeader.contains("PHPSESSID=") {
            env["HTTP_COOKIE"] = requestCookieHeader
        } else if requestCookieHeader.isEmpty {
            env["HTTP_COOKIE"] = "PHPSESSID=\(sessionID)"
        } else {
            env["HTTP_COOKIE"] = "PHPSESSID=\(sessionID); \(requestCookieHeader)"
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

        let shimsEnabled = !["0", "false", "off"].contains(shimsFlag.lowercased())
        var phpLogs: [String] = ["requestId: \(requestId)",
                                 "request: \(request.httpMethod ?? "GET") \(requestUri)",
                                 "exitCode: \(result.exitCode)",
                                 "shims: \(shimsEnabled ? "on" : "off")"]
        let stdoutByteCount = result.stdout.utf8.count
        if stdoutByteCount > 0 {
            phpLogs.append("stdout bytes: \(stdoutByteCount)")
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            phpLogs.append("stderr:\n\(stderr)")
        }
        if let errorLogContents = try? String(contentsOfFile: errorLogPath, encoding: .utf8) {
            let trimmed = errorLogContents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                phpLogs.append("error_log:\n\(trimmed)")
            }
        }

        let stdout = result.stdout.isEmpty ? "<html><body><pre>Empty output from PHP.</pre></body></html>" : result.stdout
        var headers: [String: [String]] = [:]
        for (key, values) in result.responseHeaders {
            headers[key.lowercased(), default: []].append(contentsOf: values)
        }
        var statusCode = Int(result.statusCode)
        if statusCode == 0 {
            statusCode = 200
        }
        var mimeType: String?
        var textEncoding: String?
        var location: String?
        if let contentType = headers["content-type"]?.first {
            let parsed = parseContentTypeHeader(contentType)
            mimeType = parsed.mimeType
            textEncoding = parsed.textEncoding
        }
        if let locationHeader = headers["location"]?.first {
            location = locationHeader
        }

        var output = stdout
        if headers.isEmpty {
            let parsed = parsePhpOutput(stdout)
            if parsed.hadHeaders {
                headers = parsed.headers
                output = parsed.body
                statusCode = parsed.statusCode
                if let contentType = parsed.headers["content-type"]?.first {
                    let parsedContent = parseContentTypeHeader(contentType)
                    mimeType = parsedContent.mimeType
                    textEncoding = parsedContent.textEncoding
                }
                location = parsed.location
            }
        }

        if let contentType = headers["content-type"]?.first {
            phpLogs.append("content-type: \(contentType)")
        }
        if let location {
            phpLogs.append("location: \(location)")
        }
        if statusCode > 0 {
            phpLogs.append("statusCode: \(statusCode)")
        }

        let outputData = Data(output.utf8)
        let resolvedMime = mimeType ?? (outputLooksLikeJson(output) ? "application/json" : "text/html")
        let resolvedEncoding = textEncoding ?? "utf-8"
        return PhpResponse(data: outputData,
                           output: output,
                           mimeType: resolvedMime,
                           textEncoding: resolvedEncoding,
                           headers: headers,
                           statusCode: statusCode,
                           location: location,
                           logEntry: phpLogs.joined(separator: "\n\n"))
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

    private func shouldCaptureSourceOutput(mimeType: String, output: String) -> Bool {
        let lower = mimeType.lowercased()
        if lower.hasPrefix("text/") {
            return true
        }
        if lower.contains("application/json")
            || lower.contains("application/xml")
            || lower.contains("application/javascript") {
            return true
        }
        return outputLooksLikeJson(output)
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
                         statusCode: Int,
                         headerFields: [String: String],
                         textEncoding: String?) {
        var headers = headerFields
        if headers["Content-Type"] == nil {
            if let textEncoding {
                headers["Content-Type"] = "\(mimeType); charset=\(textEncoding)"
            } else {
                headers["Content-Type"] = mimeType
            }
        }
        if let httpResponse = HTTPURLResponse(url: url,
                                              statusCode: statusCode,
                                              httpVersion: "HTTP/1.1",
                                              headerFields: headers) {
            task.didReceive(httpResponse)
        } else {
            let response = URLResponse(url: url,
                                       mimeType: mimeType,
                                       expectedContentLength: data.count,
                                       textEncodingName: textEncoding ?? "utf-8")
            task.didReceive(response)
        }
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, message: String) {
        let error = NSError(domain: "PhpIOS.SchemeHandler",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message])
        task.didFailWithError(error)
    }

    private func responseHeaderFields(from response: PhpResponse) -> [String: String] {
        var fields: [String: String] = [:]
        if let contentType = response.headers["content-type"]?.first {
            fields["Content-Type"] = contentType
        }
        if let location = response.location {
            fields["Location"] = location
        }
        return fields
    }

    private func normalizedRedirectURL(from location: String, baseURL: URL) -> URL {
        if let url = URL(string: location), url.scheme != nil {
            return url
        }
        if location.hasPrefix("/") {
            return URL(string: "phpios://localhost\(location)") ?? baseURL
        }
        let base = baseURL.deletingLastPathComponent()
        return URL(string: location, relativeTo: base)?.absoluteURL ?? baseURL
    }

    private func redirectHtml(to url: URL) -> String {
        let escaped = url.absoluteString.replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <html><head>
        <meta http-equiv="refresh" content="0; url=\(escaped)">
        <script>window.location.href="\(escaped)";</script>
        </head><body>Redirecting to <a href="\(escaped)">\(escaped)</a></body></html>
        """
    }

    private func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            let lower = key.lowercased()
            if lower == "cookie" || lower == "set-cookie" {
                result[key] = redactCookieHeader(value) ?? ""
            } else if isSensitiveKey(lower) {
                result[key] = "<redacted>"
            } else {
                result[key] = truncate(value, limit: 2048)
            }
        }
        return result
    }

    private func redactCookieHeader(_ header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        let parts = header.split(separator: ";")
        let redacted = parts.compactMap { part -> String? in
            let pair = part.split(separator: "=", maxSplits: 1)
            guard let name = pair.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return nil
            }
            return "\(name)=***"
        }
        return redacted.joined(separator: "; ")
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let sensitive = ["password", "pass", "pwd", "token", "authorization"]
        return sensitive.contains(key.lowercased())
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let truncated = text.prefix(limit)
        return "\(truncated)\n... (truncated)"
    }

    private func previewBody(data: Data, contentType: String?, limit: Int) -> String? {
        guard !data.isEmpty else { return nil }
        let lower = contentType?.lowercased() ?? ""
        let isText = lower.contains("text/")
            || lower.contains("application/json")
            || lower.contains("application/x-www-form-urlencoded")
            || lower.contains("application/xml")
            || lower.contains("application/javascript")
        guard isText else {
            return "<binary \(data.count) bytes>"
        }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            return "<binary \(data.count) bytes>"
        }
        let redacted = redactTextBody(text, contentType: lower)
        return truncate(redacted, limit: limit)
    }

    private func previewText(_ text: String, contentType: String?, limit: Int) -> String? {
        let lower = contentType?.lowercased() ?? ""
        let isText = lower.contains("text/")
            || lower.contains("application/json")
            || lower.contains("application/x-www-form-urlencoded")
            || lower.contains("application/xml")
            || lower.contains("application/javascript")
            || lower.contains("text/html")
        guard isText else {
            return "<non-text body>"
        }
        let redacted = redactTextBody(text, contentType: lower)
        return truncate(redacted, limit: limit)
    }

    private func redactTextBody(_ text: String, contentType: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if contentType.contains("application/json") || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let redacted = redactJson(json),
               let output = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted]),
               let text = String(data: output, encoding: .utf8) {
                return text
            }
        }
        if contentType.contains("application/x-www-form-urlencoded") {
            return redactUrlEncoded(text)
        }
        return text
    }

    private func redactJson(_ value: Any) -> Any? {
        if let array = value as? [Any] {
            return array.map { redactJson($0) ?? "<redacted>" }
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                if isSensitiveKey(key) {
                    result[key] = "<redacted>"
                } else {
                    result[key] = redactJson(value) ?? "<redacted>"
                }
            }
            return result
        }
        return value
    }

    private func redactUrlEncoded(_ text: String) -> String {
        let parts = text.split(separator: "&")
        let redacted = parts.map { part -> String in
            let pair = part.split(separator: "=", maxSplits: 1)
            guard let rawKey = pair.first else { return String(part) }
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            if isSensitiveKey(key) {
                return "\(rawKey)=***"
            }
            return String(part)
        }
        return redacted.joined(separator: "&")
    }

    private func flattenHeaders(_ headers: [String: [String]]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, values) in headers {
            result[key] = values.joined(separator: ", ")
        }
        return result
    }

    private func logNetworkEvent(kind: NetworkEvent.Kind,
                                 method: String,
                                 url: URL,
                                 requestId: String,
                                 status: Int?,
                                 durationMs: Int?,
                                 tag: String?,
                                 error: String?,
                                 requestHeaders: [String: String]? = nil,
                                 requestBodyPreview: String? = nil,
                                 responseHeaders: [String: String]? = nil,
                                 responseBodyPreview: String? = nil,
                                 cookiesBefore: String? = nil,
                                 cookiesAfter: String? = nil) {
        let event = NetworkEvent(id: UUID().uuidString,
                                 requestId: requestId,
                                 kind: kind,
                                 method: method,
                                 url: url.absoluteString,
                                 status: status,
                                 durationMs: durationMs,
                                 error: error,
                                 tag: tag,
                                 time: Date(),
                                 requestHeaders: requestHeaders,
                                 requestBodyPreview: requestBodyPreview,
                                 responseHeaders: responseHeaders,
                                 responseBodyPreview: responseBodyPreview,
                                 cookiesBefore: cookiesBefore,
                                 cookiesAfter: cookiesAfter)
        logStore.appendNetworkEvent(event)
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
        case "mjs":
            return "application/javascript"
        case "wasm":
            return "application/wasm"
        case "xml":
            return "application/xml"
        case "txt":
            return "text/plain"
        case "webmanifest":
            return "application/manifest+json"
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
    private static let installQueue = DispatchQueue(label: "phpios.evo.install")
    private static var cachedRoot: URL?

    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    static func ensureInstalled() throws -> URL {
        try installQueue.sync {
            if let cachedRoot {
                return cachedRoot
            }
            let root = try performInstallIfNeeded()
            cachedRoot = root
            return root
        }
    }

    private static func performInstallIfNeeded() throws -> URL {
        let fileManager = FileManager.default
        let supportURL = try fileManager.url(for: .applicationSupportDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true)
        let installLogURL = supportURL.appendingPathComponent("evo-install.log")
        let destinationRoot = supportURL.appendingPathComponent("evo", isDirectory: true)

        let indexMarker = destinationRoot.appendingPathComponent("index.php")
        var needsRefresh = false
        var needsIndexUpdate = false
        let destinationExists = fileManager.fileExists(atPath: destinationRoot.path)

        if destinationExists, fileManager.fileExists(atPath: indexMarker.path) {
            if let contents = try? String(contentsOf: indexMarker, encoding: .utf8),
               !contents.contains("PHP_IOS_DEBUG") {
                needsIndexUpdate = true
            }
        } else {
            needsRefresh = true
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

        if needsRefresh {
            guard let indexUrl = resourceBundle.url(forResource: "index",
                                                    withExtension: "php",
                                                    subdirectory: "payload/work/evo") else {
                throw PhpError.scriptNotFound("payload/work/evo/index.php")
            }
            let resourceRoot = indexUrl.deletingLastPathComponent()
            let tempRoot = supportURL.appendingPathComponent("evo.tmp.\(UUID().uuidString)", isDirectory: true)
            if fileManager.fileExists(atPath: tempRoot.path) {
                _ = try? fileManager.removeItem(at: tempRoot)
            }
            try fileManager.copyItem(at: resourceRoot, to: tempRoot)
            do {
                if destinationExists {
                    _ = try fileManager.replaceItemAt(destinationRoot, withItemAt: tempRoot, backupItemName: nil)
                } else {
                    try fileManager.moveItem(at: tempRoot, to: destinationRoot)
                }
            } catch {
                appendInstallLog("replace failed: \(error.localizedDescription)", to: installLogURL)
                if destinationExists {
                    _ = try? fileManager.removeItem(at: destinationRoot)
                }
                do {
                    try fileManager.moveItem(at: tempRoot, to: destinationRoot)
                } catch {
                    appendInstallLog("fallback move failed: \(error.localizedDescription)", to: installLogURL)
                    throw error
                }
            }
            needsIndexUpdate = false
        } else if needsIndexUpdate {
            guard let indexUrl = resourceBundle.url(forResource: "index",
                                                    withExtension: "php",
                                                    subdirectory: "payload/work/evo") else {
                throw PhpError.scriptNotFound("payload/work/evo/index.php")
            }
            let tempIndex = destinationRoot.appendingPathComponent("index.php.tmp.\(UUID().uuidString)")
            try fileManager.copyItem(at: indexUrl, to: tempIndex)
            do {
                if fileManager.fileExists(atPath: indexMarker.path) {
                    _ = try fileManager.replaceItemAt(indexMarker, withItemAt: tempIndex, backupItemName: nil)
                } else {
                    try fileManager.moveItem(at: tempIndex, to: indexMarker)
                }
            } catch {
                appendInstallLog("index replace failed: \(error.localizedDescription)", to: installLogURL)
                if fileManager.fileExists(atPath: indexMarker.path) {
                    _ = try? fileManager.removeItem(at: indexMarker)
                }
                do {
                    try fileManager.moveItem(at: tempIndex, to: indexMarker)
                } catch {
                    appendInstallLog("index fallback move failed: \(error.localizedDescription)", to: installLogURL)
                    throw error
                }
            }
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

    private static func appendInstallLog(_ message: String, to url: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { _ = try? handle.close() }
                _ = try? handle.seekToEnd()
                handle.write(data)
            } else {
                _ = try? data.write(to: url, options: .atomic)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
