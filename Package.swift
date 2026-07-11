// swift-tools-version: 6.2
import PackageDescription

// StrongClone Core — logique métier en Swift pur, sans UIKit/SwiftUI ni dépendance device.
// Testable via `swift test` sur l'hôte macOS (pas de simulateur requis).
//
// KDBXKit (lecture/écriture .kdbx standard) est ajouté dans le change OpenSpec `kdbx-read`.
// C'est du Swift pur (pas d'UIKit) → Core reste testable sans simulateur. On ne réimplémente
// jamais la crypto à la main (CLAUDE.md §6).
let package = Package(
    name: "StrongCloneCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "StrongCloneCore", targets: ["StrongCloneCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/shadone/KDBXKit.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "StrongCloneCore",
            dependencies: [
                .product(name: "KDBXKit", package: "KDBXKit")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StrongCloneCoreTests",
            dependencies: ["StrongCloneCore"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
