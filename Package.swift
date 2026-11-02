// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProductiveHours",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProductiveHours", targets: ["ProductiveHours"]),
        .executable(name: "CallProbe", targets: ["CallProbe"]),
        .executable(name: "PlatformProbe", targets: ["PlatformProbe"]),
        .executable(name: "CrashHarness", targets: ["CrashHarness"])
    ],
    targets: [
        .target(name: "ActivityCore"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "Persistence", dependencies: ["ActivityCore", "CSQLite"]),
        .target(name: "PlatformCollectors", dependencies: ["ActivityCore"]),
        .executableTarget(name: "ProductiveHours", dependencies: ["PlatformCollectors", "Persistence"]),
        .executableTarget(name: "CrashHarness", dependencies: ["ActivityCore", "Persistence"]),
        .executableTarget(name: "CallProbe", dependencies: ["PlatformCollectors"]),
        .executableTarget(name: "PlatformProbe", dependencies: ["PlatformCollectors"]),
        .testTarget(name: "ActivityCoreTests", dependencies: ["ActivityCore"]),
        .testTarget(name: "PlatformCollectorsTests", dependencies: ["PlatformCollectors"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "ActivityCore"])
    ]
)
