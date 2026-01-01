import SwiftUI
import WebKit
import PhpIOS

struct ContentView: View {
    private enum EvoPage {
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

        var requestUri: String {
            switch self {
            case .home:
                return "/index.php"
            case .manager:
                return "/manager/index.php"
            }
        }
    }

    @State private var htmlOutput = "<html><body><pre>Loading Evolution CMS...</pre></body></html>"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var baseURL: URL?
    @State private var activePage: EvoPage = .home
    @State private var jsLogs: [String] = []
    @State private var phpLogOutput = ""

    var body: some View {
        HStack(spacing: 12) {
            WebView(html: htmlOutput, baseURL: baseURL, jsLogs: $jsLogs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                ScrollView {
                    Text(htmlOutput)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                ScrollView {
                    Text(jsLogs.joined(separator: "\n"))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                ScrollView {
                    Text(phpLogOutput.isEmpty ? "No PHP logs yet." : phpLogOutput)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .overlay(alignment: .topLeading) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 8)
                    .padding(.leading, 8)
            }
        }
        .onAppear {
            if htmlOutput.isEmpty || htmlOutput.contains("Loading Evolution CMS") {
                loadPage(.home)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            pageButton(.home, systemImage: "house.fill")
            pageButton(.manager, systemImage: "gearshape.fill")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func pageButton(_ page: EvoPage, systemImage: String) -> some View {
        Button {
            loadPage(page)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(activePage == page ? .white : .primary)
                .frame(width: 44, height: 36)
            .background(
                Group {
                    if activePage == page {
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.45, blue: 0.95),
                                     Color(red: 0.35, green: 0.7, blue: 0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .disabled(isLoading && activePage == page)
    }

    private func loadPage(_ page: EvoPage) {
        activePage = page
        isLoading = true
        errorMessage = nil
        jsLogs.removeAll()
        phpLogOutput = ""

        Task {
            do {
                let (output, pageBaseURL, phpLogs) = try runEvoPage(page)
                await MainActor.run {
                    guard activePage == page else { return }
                    htmlOutput = output
                    baseURL = pageBaseURL
                    phpLogOutput = phpLogs
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard activePage == page else { return }
                    errorMessage = error.localizedDescription
                    htmlOutput = "<html><body><pre>\(error.localizedDescription)</pre></body></html>"
                    baseURL = nil
                    phpLogOutput = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func runEvoPage(_ page: EvoPage) throws -> (String, URL, String) {
        let siteRoot = try ensureEvoSiteInstalled()
        let scriptPath = siteRoot.appendingPathComponent(page.scriptRelativePath).path
        let databasePath = siteRoot.appendingPathComponent("database.sqlite").path
        let sessionPath = siteRoot.appendingPathComponent("core/storage/sessions").path
        let errorLogPath = siteRoot.appendingPathComponent("php-error.log").path
        let pageBaseURL: URL
        if page == .manager {
            pageBaseURL = siteRoot.appendingPathComponent("manager", isDirectory: true)
        } else {
            pageBaseURL = siteRoot
        }

        if !FileManager.default.fileExists(atPath: errorLogPath) {
            FileManager.default.createFile(atPath: errorLogPath, contents: nil)
        } else {
            try? "".write(toFile: errorLogPath, atomically: true, encoding: .utf8)
        }

        let engine = try PhpEngine.shared()
        let refererURL = "http://localhost" + (page == .manager ? "/manager/" : "/")
        let result = try engine.runFile(
            scriptPath,
            env: [
                "DOCUMENT_ROOT": siteRoot.path,
                "REQUEST_URI": page.requestUri,
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
                "PHP_SELF": page.requestUri,
                "SCRIPT_NAME": page.requestUri,
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
            return ("<html><body><pre>\(fallback)</pre></body></html>", pageBaseURL, phpLogs.joined(separator: "\n\n"))
        }
        return (result.stdout, pageBaseURL, phpLogs.joined(separator: "\n\n"))
    }

    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    private func ensureEvoSiteInstalled() throws -> URL {
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

    private func escapeHtml(_ input: String) -> String {
        var escaped = input.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        return escaped
    }
}

struct WebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var jsLogs: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(jsLogs: $jsLogs)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        let scriptSource = """
        (function() {
          function stringify(args) {
            return Array.prototype.slice.call(args).map(function(item) {
              try { return typeof item === 'string' ? item : JSON.stringify(item); } catch (e) { return String(item); }
            }).join(' ');
          }
          function wrap(level) {
            var original = console[level];
            console[level] = function() {
              try {
                window.webkit.messageHandlers.jsLog.postMessage({ level: level, message: stringify(arguments) });
              } catch (e) {}
              if (original) { original.apply(console, arguments); }
            };
          }
          ['log','info','warn','error','debug'].forEach(wrap);
          window.addEventListener('error', function(event) {
            try {
              window.webkit.messageHandlers.jsLog.postMessage({ level: 'error', message: event.message + ' @ ' + event.filename + ':' + event.lineno });
            } catch (e) {}
          });
        })();
        """
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(script)
        contentController.add(context.coordinator, name: "jsLog")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let jsLogs: Binding<[String]>
        weak var webView: WKWebView?

        init(jsLogs: Binding<[String]>) {
            self.jsLogs = jsLogs
        }

        deinit {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "jsLog")
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "jsLog" else { return }
            var line = "\(message.body)"
            if let body = message.body as? [String: Any],
               let level = body["level"] as? String,
               let msg = body["message"] as? String {
                line = "[\(level)] \(msg)"
            }
            appendLog(line)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            appendLog("[error] WebView navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            appendLog("[error] WebView load failed: \(error.localizedDescription)")
        }

        private func appendLog(_ line: String) {
            DispatchQueue.main.async {
                var current = self.jsLogs.wrappedValue
                current.append(line)
                if current.count > 300 {
                    current.removeFirst(current.count - 300)
                }
                self.jsLogs.wrappedValue = current
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
