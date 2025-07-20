// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "WinDock",
            targets: ["WinDock"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/orchetect/SettingsAccess",
            from: "2.1.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "WinDock",
            dependencies: [
                "SettingsAccess"
            ],
            path: "WinDock"
        ),
        .testTarget(
            name: "WinDockTests",
            dependencies: ["WinDock"],
            path: "WinDockTests"
        )
    ]
)
