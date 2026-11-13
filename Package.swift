// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCFDeadline",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CCFDeadline", targets: ["CCFDeadline"])],
    targets: [
        .target(name: "DeadlineCore"),
        .executableTarget(name: "CCFDeadline", dependencies: ["DeadlineCore"],
                          resources: [.copy("Resources/seed.json")]),
        .testTarget(name: "DeadlineCoreTests", dependencies: ["DeadlineCore"])
    ]
)
