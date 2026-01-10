// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OrionEmailApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OrionEmailApp",
            targets: ["OrionEmailApp"]
        ),
    ],
    dependencies: [
        // Clerk iOS SDK for authentication
        .package(url: "https://github.com/clerk/clerk-ios.git", from: "1.0.0"),
        // Keychain access for secure storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .target(
            name: "OrionEmailApp",
            dependencies: [
                .product(name: "ClerkSDK", package: "clerk-ios"),
                "KeychainAccess",
            ],
            path: "EmailApp"
        ),
        .testTarget(
            name: "OrionEmailAppTests",
            dependencies: ["OrionEmailApp"],
            path: "Tests"
        ),
    ]
)
