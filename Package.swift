// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F28",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: focus resolution, shake detection, mask rendering. No AppKit.
        .target(name: "F28Core"),
        // The menu bar app.
        .executableTarget(
            name: "F28",
            dependencies: ["F28Core"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Dependency-free test runner (the Command Line Tools ship without XCTest).
        .executableTarget(name: "F28SelfTest", dependencies: ["F28Core"]),
    ]
)
