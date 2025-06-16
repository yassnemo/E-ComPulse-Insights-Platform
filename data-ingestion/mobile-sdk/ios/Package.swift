// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EComPulseAnalytics",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "EComPulseAnalytics",
            targets: ["EComPulseAnalytics"]
        ),
    ],
    dependencies: [
        // No external dependencies to keep the SDK lightweight
    ],
    targets: [
        .target(
            name: "EComPulseAnalytics",
            dependencies: [],
            path: "Sources",
            sources: [
                "EComPulseAnalytics.swift",
                "Supporting Classes.swift"
            ]
        ),
        .testTarget(
            name: "EComPulseAnalyticsTests",
            dependencies: ["EComPulseAnalytics"],
            path: "Tests"
        ),
    ]
)
