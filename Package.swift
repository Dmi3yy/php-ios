// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let env = ProcessInfo.processInfo.environment
let sdkName = env["SDK_NAME"] ?? ""
let effectivePlatform = env["EFFECTIVE_PLATFORM_NAME"] ?? ""
let platformName = env["PLATFORM_NAME"] ?? ""
let isSimulator = sdkName.contains("iphonesimulator")
    || effectivePlatform == "-iphonesimulator"
    || platformName == "iphonesimulator"

let phpLibDir = env["PHP_IOS_LIB_DIR"]
    ?? (isSimulator ? "\(packageDir)/Sources/PhpIOS/lib-sim" : "\(packageDir)/Sources/PhpIOS/lib")

let package = Package(
    name: "PhpIOS",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "PhpIOS",
            targets: ["PhpIOS"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PhpIOSBridge",
            dependencies: [],
            path: "Sources/PhpIOSBridge",
            exclude: ["../PhpIOS/lib", "../PhpIOS/lib-sim"],
            publicHeadersPath: ".",
            cSettings: [
                .unsafeFlags(["-I", "\(phpLibDir)/include/php/Zend"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include/php/TSRM"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include/php/main"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include/php"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include"], .when(platforms: [.iOS]))
            ],
            cxxSettings: [
                .unsafeFlags(["-I", "\(phpLibDir)/include/php/Zend"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include/php/TSRM"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include/php/main"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include/php"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpLibDir)/include"], .when(platforms: [.iOS]))
            ],
            linkerSettings: [
                .linkedLibrary("resolv", .when(platforms: [.iOS])),
                .linkedLibrary("xml2", .when(platforms: [.iOS])),
                .linkedLibrary("php-ios", .when(platforms: [.iOS])),
                .unsafeFlags(["-L", phpLibDir], .when(platforms: [.iOS])),
                .unsafeFlags(["-Xlinker", "-ObjC"], .when(platforms: [.iOS]))
            ]
        ),
        .target(
            name: "PhpIOS",
            dependencies: ["PhpIOSBridge"],
            path: "Sources/PhpIOS",
            exclude: ["lib", "lib-sim"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PhpIOSTests",
            dependencies: ["PhpIOS"],
            path: "Tests/PhpIOSTests"
        ),
    ]
)
