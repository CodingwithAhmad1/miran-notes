// swift-tools-version: 6.0
import PackageDescription

let swift6Settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "MiranNotes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MiranNotes", targets: ["MiranNotesApp"])
    ],
    targets: [
        .target(
            name: "MiranNotesCore",
            path: "Sources/MiranNotesCore",
            swiftSettings: swift6Settings
        ),
        .executableTarget(
            name: "MiranNotesApp",
            dependencies: ["MiranNotesCore"],
            path: "Sources/MiranNotesApp",
            swiftSettings: swift6Settings
        ),
        .testTarget(
            name: "MiranNotesTests",
            dependencies: ["MiranNotesCore"],
            path: "Tests/MiranNotesTests",
            swiftSettings: swift6Settings
        ),
        .testTarget(
            name: "MiranNotesAppTests",
            dependencies: ["MiranNotesApp", "MiranNotesCore"],
            path: "Tests/MiranNotesAppTests",
            swiftSettings: swift6Settings
        )
    ]
)
