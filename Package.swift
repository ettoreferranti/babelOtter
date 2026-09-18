// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "babelOtter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BabelOtterKit", targets: ["BabelOtterKit"]),
        .executable(name: "babelotter-eval", targets: ["babelotter-eval"]),
    ],
    // No dependencies. Adding one requires an entry in
    // Config/dependency-allowlist.txt — see Task 7 and NFR-P6.
    targets: [
        .target(name: "BabelOtterKit"),
        .executableTarget(name: "BabelOtterApp", dependencies: ["BabelOtterKit"]),
        .executableTarget(name: "babelotter-eval", dependencies: ["BabelOtterKit"]),
        .testTarget(name: "BabelOtterKitTests", dependencies: ["BabelOtterKit"]),
    ]
)
