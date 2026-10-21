// swift-tools-version: 5.9
import Foundation
import PackageDescription

let sdkVersion = "3.4.0-dev.1034"
// Same choice as scripts/mentraos-sdk-path.cjs: MENTRA_BLUETOOTH_SDK_PUBLISHED=1 forces
// the published SDK, then MENTRA_BLUETOOTH_SDK_PACKAGE_PATH, then the MentraOS mobile
// workspace next to this repository (../mentraos/mobile).
let env = ProcessInfo.processInfo.environment
let siblingMobile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../../mentraos/mobile").standardized.path
let siblingSdk: String? = FileManager.default.fileExists(atPath: siblingMobile + "/package.json")
    && FileManager.default.fileExists(atPath: siblingMobile + "/modules/bluetooth-sdk/Package.swift")
    ? siblingMobile + "/modules/bluetooth-sdk" : nil
let sdk: Package.Dependency
let sdkIdentity: String
if env["MENTRA_BLUETOOTH_SDK_PUBLISHED"] != "1",
   let localPath = env["MENTRA_BLUETOOTH_SDK_PACKAGE_PATH"].flatMap({ $0.isEmpty ? nil : $0 }) ?? siblingSdk {
    sdk = .package(path: localPath)
    sdkIdentity = URL(fileURLWithPath: localPath).lastPathComponent.lowercased()
} else {
    sdk = .package(url: "https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios.git", exact: Version(sdkVersion)!)
    sdkIdentity = "mentra-bluetooth-sdk-ios"
}

let package = Package(
    name: "MentraMacExample",
    platforms: [.macOS(.v13)],
    dependencies: [sdk],
    targets: [.executableTarget(name: "MentraMacExample", dependencies: [
        .product(name: "MentraBluetoothSDK", package: sdkIdentity),
    ])]
)
