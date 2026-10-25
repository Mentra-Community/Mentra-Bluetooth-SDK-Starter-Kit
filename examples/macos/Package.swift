// swift-tools-version: 5.9
import PackageDescription

// Uses the published Mentra Bluetooth SDK Swift package.
let sdkVersion = "3.4.0-dev.1113"

let package = Package(
    name: "MentraMacExample",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios.git", exact: Version(sdkVersion)!),
    ],
    targets: [.executableTarget(name: "MentraMacExample", dependencies: [
        .product(name: "MentraBluetoothSDK", package: "mentra-bluetooth-sdk-ios"),
    ])]
)
