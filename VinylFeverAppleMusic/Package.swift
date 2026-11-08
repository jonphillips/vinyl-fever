// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "VinylFeverAppleMusic",
  platforms: [.macOS(.v26), .iOS(.v27)],
  products: [
    .library(name: "VinylFeverAppleMusic", targets: ["VinylFeverAppleMusic"]),
    .library(name: "VinylFeverAppleMusicLive", targets: ["VinylFeverAppleMusicLive"]),
  ],
  dependencies: [
    .package(path: "../VinylFeverNotes"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
  ],
  targets: [
    .target(name: "VinylFeverAppleMusic", dependencies: [
      .product(name: "VinylFeverNotes", package: "VinylFeverNotes"),
      .product(name: "Dependencies", package: "swift-dependencies"),
      .product(name: "DependenciesMacros", package: "swift-dependencies"),
    ]),
    .target(name: "VinylFeverAppleMusicLive", dependencies: [
      "VinylFeverAppleMusic",
      .product(name: "VinylFeverNotes", package: "VinylFeverNotes"),
    ]),
    .testTarget(name: "VinylFeverAppleMusicTests", dependencies: ["VinylFeverAppleMusic"]),
  ]
)
