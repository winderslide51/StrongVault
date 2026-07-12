import Foundation
import XCTest

@testable import StrongCloneCore

/// Interop **lecture** (kdbx-read §5.1) : prouve que les golden files de lecture s'ouvrent
/// **headless dans KeePassXC réel** (`keepassxc-cli`, mot de passe via stdin), en complément de
/// l'interop d'écriture (`KDBXWriteSpikeTests`). Gaté sur la présence du binaire (la CI l'installe).
final class KDBXReadInteropTests: XCTestCase {
    private static let dbPassword = "correct horse battery staple"
    private static let entryPassword = "s3cr3t-P@ss-42"

    private func fixtureURL(_ name: String, ext: String = "kdbx") throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "Golden file \(name).\(ext) introuvable"
        )
    }

    func testPasswordGoldenFileOpensInKeePassXC() throws {
        try XCTSkipUnless(KeePassXCInterop.isAvailable, "keepassxc-cli introuvable (CI Homebrew)")
        let output = try KeePassXCInterop.showEntry(
            databaseURL: try fixtureURL("demo-password"),
            password: Self.dbPassword,
            entryPath: "GitHub"
        )
        XCTAssertTrue(output.contains("Password: \(Self.entryPassword)"), "Sortie : \(output)")
        XCTAssertTrue(output.contains("UserName: alice@example.com"), "Sortie : \(output)")
    }

    func testModern4xGoldenFileOpensInKeePassXC() throws {
        try XCTSkipUnless(KeePassXCInterop.isAvailable, "keepassxc-cli introuvable (CI Homebrew)")
        let output = try KeePassXCInterop.showEntry(
            databaseURL: try fixtureURL("demo-modern-4x"),
            password: Self.dbPassword,
            entryPath: "GitHub"
        )
        XCTAssertTrue(output.contains("Password: \(Self.entryPassword)"), "Sortie : \(output)")
    }
}
