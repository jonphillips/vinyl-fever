// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "VinylFeverCore",
  platforms: [
    .macOS(.v26),
  ],
  products: [
    .library(name: "VinylFeverCore", targets: ["VinylFeverCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.0.0"),
    // App-agnostic model boundary shared across jon-platform apps (Galavant, Yes
    // Chef). Sibling checkout: `jon-platform` lives next to `vinyl-fever`.
    .package(path: "../../jon-platform/packages/LLMClientKit"),
  ],
  targets: [
    .target(
      name: "VinylFeverCore",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "SwiftNavigation", package: "swift-navigation"),
        .product(name: "LLMClientKit", package: "LLMClientKit"),
      ]
    ),
    .testTarget(
      name: "VinylFeverCoreTests",
      dependencies: [
        "VinylFeverCore",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "LLMClientKit", package: "LLMClientKit"),
      ]
    ),
  ]
)
