// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AppLockerCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AppLockerCore", targets: ["AppLockerCore"])],
    targets: [
        .target(name: "AppLockerCore", path: "AppLocker/Models", exclude: ["ProtectedApp.swift"], sources: ["LockSession.swift", "WindowVisibility.swift"]),
        .testTarget(name: "AppLockerCoreTests", dependencies: ["AppLockerCore"], path: "Tests/AppLockerCoreTests")
    ]
)
