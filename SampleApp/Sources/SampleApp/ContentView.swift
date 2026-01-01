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

    var body: some View {
        VStack(spacing: 0) {
            WebView(html: htmlOutput, baseURL: baseURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .top)
        }
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

        Task {
            do {
                let (output, pageBaseURL) = try runEvoPage(page)
                await MainActor.run {
                    guard activePage == page else { return }
                    htmlOutput = output
                    baseURL = pageBaseURL
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard activePage == page else { return }
                    errorMessage = error.localizedDescription
                    htmlOutput = "<html><body><pre>\(error.localizedDescription)</pre></body></html>"
                    baseURL = nil
                    isLoading = false
                }
            }
        }
    }

    private func runEvoPage(_ page: EvoPage) throws -> (String, URL) {
        let siteRoot = try ensureEvoSiteInstalled()
        let scriptPath = siteRoot.appendingPathComponent(page.scriptRelativePath).path
        let databasePath = siteRoot.appendingPathComponent("database.sqlite").path
        let sessionPath = siteRoot.appendingPathComponent("core/storage/sessions").path
        let pageBaseURL: URL
        if page == .manager {
            pageBaseURL = siteRoot.appendingPathComponent("manager", isDirectory: true)
        } else {
            pageBaseURL = siteRoot
        }

        let engine = try PhpEngine.shared()
        let result = try engine.runFile(
            scriptPath,
            env: [
                "DOCUMENT_ROOT": siteRoot.path,
                "REQUEST_URI": page.requestUri,
                "QUERY_STRING": "",
                "HTTP_HOST": "localhost",
                "SERVER_NAME": "localhost",
                "SERVER_PORT": "80",
                "REQUEST_SCHEME": "http",
                "HTTPS": "off",
                "PHP_SELF": page.requestUri,
                "SCRIPT_NAME": page.requestUri,
                "DB_DATABASE": databasePath,
                "DB_TYPE": "sqlite"
            ],
            ini: [
                "session.save_path": sessionPath,
                "pcre.jit": "0"
            ]
        )

        let trimmedOutput = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty {
            let fallback = result.stderr.isEmpty ? "Empty output from PHP." : escapeHtml(result.stderr)
            return ("<html><body><pre>\(fallback)</pre></body></html>", pageBaseURL)
        }
        return (result.stdout, pageBaseURL)
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
        if !fileManager.fileExists(atPath: destinationRoot.path)
            || !fileManager.fileExists(atPath: indexMarker.path) {
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
        }

        let sessionsURL = destinationRoot.appendingPathComponent("core/storage/sessions", isDirectory: true)
        if !fileManager.fileExists(atPath: sessionsURL.path) {
            try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
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

    func makeUIView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: baseURL)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
