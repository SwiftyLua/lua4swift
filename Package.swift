// swift-tools-version:6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "lua4swift",
  products: [
    .library(
      name: "lua4swift",
      targets: ["lua4swift"]),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftyLua/CLua", branch: "main"),
  ],
  targets: [
    .target(
      name: "lua4swift",
      dependencies: [
        "CLua"
      ]),
    .testTarget(
      name: "lua4swiftTests",
      dependencies: [
        "lua4swift",
      ]),
  ]
)
