// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoyuBrowser",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "MoyuBrowser", path: "Sources/MoyuBrowser")
    ]
)
