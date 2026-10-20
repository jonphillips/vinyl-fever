// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "VinylFeverListening",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .library(name: "VinylFeverListening", targets: ["VinylFeverListening"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "VinylFeverListening",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "VinylFeverListeningTests",
      dependencies: [
        "VinylFeverListening",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
  ]
)
