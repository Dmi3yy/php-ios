import SwiftUI
import WebKit
import PhpIOS

struct ContentView: View {
    @State private var htmlOutput = "<html><body><pre>Loading phpinfo()...</pre></body></html>"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack {
                    Button(action: loadPhpInfo) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Run PHP")
                        }
                    }
                    .disabled(isLoading)

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                WebView(html: htmlOutput)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
            .padding()
            .navigationTitle("PHP WebView")
        }
        .onAppear {
            if htmlOutput.isEmpty {
                loadPhpInfo()
            } else if htmlOutput.contains("Loading phpinfo()") {
                loadPhpInfo()
            }
        }
    }

    private func loadPhpInfo() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let output = try runPhpInfo()
                await MainActor.run {
                    htmlOutput = output
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    htmlOutput = "<html><body><pre>\(error.localizedDescription)</pre></body></html>"
                    isLoading = false
                }
            }
        }
    }

    private func runPhpInfo() throws -> String {
        guard let url = Bundle.main.url(forResource: "index",
                                        withExtension: "php",
                                        subdirectory: "PhpScripts") else {
            throw PhpError.scriptNotFound("PhpScripts/index.php")
        }
        let engine = try PhpEngine.shared()
        let output = try engine.runFile(url.path).stdout
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "<html><body><pre>&lt;?php\nphpinfo();\n?&gt;</pre></body></html>"
        }
        return output
    }
}

struct WebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
