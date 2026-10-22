// swift-tools-version:5.9
// DisciplineCore: the platform-independent logic of the Discipline app.
// It builds and tests on Linux and macOS (`swift test`). The iOS app and the
// optional packet-tunnel extension (see project.yml) link against it.
import PackageDescription

let package = Package(
    name: "DisciplineCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DisciplineCore", targets: ["DisciplineCore"]),
    ],
    targets: [
        .target(name: "DisciplineCore", path: "Sources/DisciplineCore"),
        .testTarget(name: "DisciplineCoreTests", dependencies: ["DisciplineCore"], path: "Tests/DisciplineCoreTests",
                    resources: [.copy("Fixtures")]),
    ]
)
