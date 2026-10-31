// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "VinylFeverNotes",
  platforms: [.macOS(.v15), .iOS(.v27)],
  products: [.library(name: "VinylFeverNotes", targets: ["VinylFeverNotes"])],
  targets: [
    .target(name: "VinylFeverNotes"),
    .testTarget(name: "VinylFeverNotesTests", dependencies: ["VinylFeverNotes"]),
  ]
)
