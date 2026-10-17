// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "TranMac",
  platforms: [.macOS(.v26)],
  targets: [
    .executableTarget(name: "TranMac", path: "Sources/TranMac", swiftSettings: [.swiftLanguageMode(.v5)])
  ]
)
