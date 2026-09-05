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
    dependencies: [
        // Built from Vendor/idevice. IDevice.xcframework must exist before this
        // resolves - see Vendor/idevice/swift/README (run `just xcframework`
        // from Vendor/idevice on macOS; this cannot be built from Linux/CI
        // without a Mac). See Modules/JITBridge/README.md.
        .package(path: "../../Vendor/idevice/swift")
    ],
    targets: [
        .target(
            name: "JITBridge",
            dependencies: [
                .product(name: "IDevice", package: "swift")
            ]
        )
    ]
)
