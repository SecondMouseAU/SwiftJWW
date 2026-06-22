// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftJWW",
    products: [
        .library(name: "SwiftJWW", targets: ["SwiftJWW"]),
        .executable(name: "jww2dxf", targets: ["jww2dxf"]),
    ],
    targets: [
        .target(name: "SwiftJWW"),
        .executableTarget(name: "jww2dxf", dependencies: ["SwiftJWW"]),
        .testTarget(name: "SwiftJWWTests", dependencies: ["SwiftJWW"]),
    ]
)
