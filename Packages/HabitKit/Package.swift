// swift-tools-version:6.0
import PackageDescription

// Everything the app and the widget share. It also builds for macOS, so `swift test` runs on a Mac
// without Xcode: the domain rules and the database are checked before any screen exists.
let package = Package(
    name: "HabitKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "HabitDomain", targets: ["HabitDomain"]),
        .library(name: "HabitData", targets: ["HabitData"]),
        .library(name: "HabitDesign", targets: ["HabitDesign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
    ],
    targets: [
        // Pure rules: days, schedules, streaks, task repeats, CSV. No Foundation dates, no UI.
        .target(name: "HabitDomain"),
        // SQLite through GRDB, with the Android app's exact schema so backups move between phones.
        .target(name: "HabitData", dependencies: ["HabitDomain", .product(name: "GRDB", package: "GRDB.swift")]),
        // Colors, type, radii and the drawings (check, dots, confetti) the app and the widget both use.
        .target(name: "HabitDesign", dependencies: ["HabitDomain"]),
        .testTarget(name: "HabitDomainTests", dependencies: ["HabitDomain"]),
        .testTarget(name: "HabitDataTests", dependencies: ["HabitData"]),
    ]
)
