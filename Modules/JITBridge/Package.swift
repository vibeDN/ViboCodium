// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JITBridge",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "JITBridge",
            targets: ["JITBridge"]
        )
    ],
    targets: [
        // Points directly at the xcframework built by
        // scripts/build-idevice-xcframework.sh, rather than depending on
        // Vendor/idevice/swift/Package.swift as a package: that manifest
        // declares `// swift-tools-version: 5.3` with a space before the
        // version, which newer toolchains (Xcode 26.6+) reject outright
        // ("horizontal whitespace sequence ... supported by only Swift
        // >= 5.4") - a real bug upstream, not something we can fix in a
        // submodule. Binding to the xcframework directly sidesteps their
        // manifest entirely.
        .binaryTarget(
            name: "IDevice",
            path: "../../Vendor/idevice/swift/IDevice.xcframework"
        ),
        .target(
            name: "JITBridge",
            dependencies: ["IDevice"]
        )
    ]
)
