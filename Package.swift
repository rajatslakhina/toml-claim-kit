// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TOMLClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "TOMLClaimKit", targets: ["TOMLClaimKit"]),
        .executable(name: "TOMLClaimDemo", targets: ["TOMLClaimDemo"])
    ],
    targets: [
        .target(name: "TOMLClaimKit"),
        .executableTarget(
            name: "TOMLClaimDemo",
            dependencies: ["TOMLClaimKit"]
        ),
        .testTarget(
            name: "TOMLClaimKitTests",
            dependencies: ["TOMLClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
