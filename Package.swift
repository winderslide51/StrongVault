// swift-tools-version: 6.2
import PackageDescription

// StrongClone Core — logique métier en Swift pur, sans UIKit/SwiftUI ni dépendance device.
// Testable via `swift test` sur l'hôte macOS (pas de simulateur requis).
//
// NB: la dépendance KDBXKit (parsing/écriture .kdbx) sera ajoutée dans le change
// OpenSpec `kdbx-read` (après le spike de validation). Le scaffolding reste hors-ligne
// pour que `swift test` passe sans accès réseau.
let package = Package(
    name: "StrongCloneCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "StrongCloneCore", targets: ["StrongCloneCore"]),
    ],
    targets: [
        .target(
            name: "StrongCloneCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StrongCloneCoreTests",
            dependencies: ["StrongCloneCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
