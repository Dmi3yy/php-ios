// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let phpIncludeDir = "\(packageDir)/Sources/PhpIOS/lib/include"

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
        .binaryTarget(
            name: "PhpIOSCore",
            path: "Sources/PhpIOS/libphp-ios.xcframework"
        ),
        .target(
            name: "PhpIOSBridge",
            dependencies: ["PhpIOSCore"],
            path: "Sources/PhpIOSBridge",
            exclude: ["../PhpIOS/lib", "../PhpIOS/lib-sim"],
            publicHeadersPath: ".",
            cSettings: [
                .unsafeFlags(["-I", "\(phpIncludeDir)/php/Zend"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)/php/TSRM"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)/php/main"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)/php"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)"], .when(platforms: [.iOS]))
            ],
            cxxSettings: [
                .unsafeFlags(["-I", "\(phpIncludeDir)/php/Zend"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)/php/TSRM"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)/php/main"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)/php"], .when(platforms: [.iOS])),
                .unsafeFlags(["-I", "\(phpIncludeDir)"], .when(platforms: [.iOS]))
            ],
            linkerSettings: [
                .linkedLibrary("resolv", .when(platforms: [.iOS])),
                .linkedLibrary("sqlite3", .when(platforms: [.iOS])),
                .linkedLibrary("xml2", .when(platforms: [.iOS])),
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
