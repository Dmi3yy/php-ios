import Foundation
import PhpIOSBridge

/// Result of PHP script execution
public struct PhpResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let responseHeaders: [String: [String]]
    public let statusCode: Int32

    public init(exitCode: Int32,
                stdout: String,
                stderr: String,
                responseHeaders: [String: [String]] = [:],
                statusCode: Int32 = 200) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.responseHeaders = responseHeaders
        self.statusCode = statusCode
    }

    internal init(bridgeResult: PhpIOSBridge.PhpResult) {
        self.exitCode = bridgeResult.exitCode
        self.stdout = bridgeResult.stdoutOutput
        self.stderr = bridgeResult.stderrOutput
        self.responseHeaders = bridgeResult.responseHeaders as? [String: [String]] ?? [:]
        self.statusCode = bridgeResult.statusCode
    }

    /// Parse stdout as JSON and return the result
    public func json() throws -> Any {
        guard !stdout.isEmpty else {
            throw PhpError.emptyOutput
        }

        let data = stdout.data(using: .utf8) ?? Data()
        return try JSONSerialization.jsonObject(with: data, options: [])
    }
}

/// Input types for PHP scripts
public enum PhpInput {
    case none
    case text(String)
    case data(Data)
    case json(Any)

    internal func toData() -> Data? {
        switch self {
        case .none:
            return nil
        case .text(let string):
            return string.data(using: .utf8)
        case .data(let data):
            return data
        case .json(let object):
            do {
                return try JSONSerialization.data(withJSONObject: object, options: [])
            } catch {
                return nil
            }
        }
    }
}

/// Resource reference for bundled PHP scripts
public struct PhpResource {
    public let bundle: Bundle
    public let path: String

    public init(bundle: Bundle, path: String) {
        self.bundle = bundle
        self.path = path
    }
}

/// PHP Engine errors
public enum PhpError: Error, LocalizedError {
    case initializationFailed(String)
    case scriptNotFound(String)
    case executionFailed(String)
    case invalidInput(String)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "PHP initialization failed: \(message)"
        case .scriptNotFound(let path):
            return "PHP script not found: \(path)"
        case .executionFailed(let message):
            return "PHP execution failed: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .emptyOutput:
            return "Empty output from PHP script"
        }
    }
}

/// Main PHP Engine class
public final class PhpEngine {
    private static var sharedInstance: PhpEngine?
    private let bridge: PhpBridge
    private let iniPath: String?
    
    private init() throws {
        let bundleIni = Bundle.module.path(forResource: "php", ofType: "ini")
        let mainIni = Bundle.main.path(forResource: "php", ofType: "ini")
        let resolved = bundleIni ?? mainIni
        self.iniPath = resolved
        self.bridge = PhpBridge(iniPath: resolved)
    }

    /// Get the shared PHP engine instance
    public static func shared() throws -> PhpEngine {
        if let instance = sharedInstance {
            return instance
        }

        let instance = try PhpEngine()
        sharedInstance = instance
        return instance
    }

    public var resolvedIniPath: String? {
        iniPath
    }

    public func selfTest() -> Result<PhpResult, Error> {
        Result {
            try runInline("<?php echo \"ok\"; ?>")
        }
    }

    public static func selfTest() -> Result<PhpResult, Error> {
        Result {
            let engine = try shared()
            return try engine.runInline("<?php echo \"ok\"; ?>")
        }
    }

    /// Configure PHP engine paths (optional)
    public static func configure(paths: [String: String]) {
        // Store configuration for later use
        UserDefaults.standard.set(paths, forKey: "PhpIOS.Configuration")
    }

    /// Run inline PHP code
    public func runInline(_ code: String,
                         stdin: PhpInput = .none,
                         ini: [String: String] = [:]) throws -> PhpResult {
        guard !code.isEmpty else {
            throw PhpError.invalidInput("Empty PHP code")
        }

        let inputData = stdin.toData()
        let bridgeResult = try bridge.executeInline(code, stdinData: inputData, ini: ini)
        return PhpResult(bridgeResult: bridgeResult)
    }

    /// Run a bundled PHP script
    public func runScript(resource: PhpResource,
                         argv: [String] = [],
                         stdin: PhpInput = .none,
                         env: [String: String] = [:],
                         ini: [String: String] = [:]) throws -> PhpResult {

        guard let scriptPath = resource.bundle.path(forResource: resource.path, ofType: nil) else {
            throw PhpError.scriptNotFound(resource.path)
        }

        let inputData = stdin.toData()
        let bridgeResult = try bridge.executeScript(scriptPath, argv: argv, stdinData: inputData, env: env, ini: ini)
        return PhpResult(bridgeResult: bridgeResult)
    }

    /// Run PHP code from a file path
    public func runFile(_ filePath: String,
                       argv: [String] = [],
                       stdin: PhpInput = .none,
                       env: [String: String] = [:],
                       ini: [String: String] = [:]) throws -> PhpResult {

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw PhpError.scriptNotFound(filePath)
        }

        let inputData = stdin.toData()
        let bridgeResult = try bridge.executeScript(filePath, argv: argv, stdinData: inputData, env: env, ini: ini)
        return PhpResult(bridgeResult: bridgeResult)
    }
}

// MARK: - Convenience Extensions

extension PhpEngine {
    /// Quick JSON processing
    public func processJSON<T>(_ input: T, with code: String) throws -> Any where T: Codable {
        let jsonData = try JSONEncoder().encode(input)
        let result = try runInline(code, stdin: .data(jsonData))
        return try result.json()
    }

    /// Quick text processing
    public func processText(_ text: String, with code: String) throws -> String {
        let result = try runInline(code, stdin: .text(text))
        return result.stdout
    }
}
