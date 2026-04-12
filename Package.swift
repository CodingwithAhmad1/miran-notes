// swift-tools-version: 5.10
import PackageDescription

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
            path: "Sources/MiranNotesCore"
        ),
        .executableTarget(
            name: "MiranNotesApp",
            dependencies: ["MiranNotesCore"],
            path: "Sources/MiranNotesApp"
        ),
        .testTarget(
            name: "MiranNotesTests",
            dependencies: ["MiranNotesCore"],
            path: "Tests/MiranNotesTests"
        ),
        .testTarget(
            name: "MiranNotesAppTests",
            dependencies: ["MiranNotesApp", "MiranNotesCore"],
            path: "Tests/MiranNotesAppTests"
        )
    ]
)
