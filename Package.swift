// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArgoCDMenubar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ArgoCDMenubar",
            path: "ArgoCDMenubar",
            exclude: ["Info.plist"]
        ),
    ]
)
