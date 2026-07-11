import Foundation
import XCTest

@testable import StrongCloneCore

/// Tests du mapping `.kdbx` → modèle domaine et des erreurs typées (kdbx-read §2/§4).
/// S'appuie sur les golden files KeePassXC (cf. `KDBXKitSpikeTests`).
final class DatabaseDocumentTests: XCTestCase {
    private static let dbPassword = "correct horse battery staple"
    private static let entryPassword = "s3cr3t-P@ss-42"

    private func fixture(_ name: String, ext: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "Golden file \(name).\(ext) introuvable"
        )
        return try Data(contentsOf: url)
    }

    private func githubEntry(in doc: DatabaseDocument) throws -> Entry {
        try XCTUnwrap(doc.root.allEntriesRecursive.first { $0.title == "GitHub" }, "Entrée GitHub absente")
    }

    func testOpensPasswordDatabaseAndMapsStandardFields() throws {
        let data = try fixture("demo-password", ext: "kdbx")
        let doc = try DatabaseDocument.open(
            data: data,
            credentials: DatabaseCredential(password: Self.dbPassword)
        )
        let entry = try githubEntry(in: doc)
        XCTAssertEqual(entry.username, "alice@example.com")
        XCTAssertEqual(entry.url, "https://example.com")
        XCTAssertEqual(entry.notes, "note de demo")
        XCTAssertEqual(entry.password.reveal(), Self.entryPassword)
    }

    func testOpensWithKeyFile() throws {
        let data = try fixture("demo-keyfile", ext: "kdbx")
        let keyFile = try fixture("demo-keyfile", ext: "key")
        let doc = try DatabaseDocument.open(
            data: data,
            credentials: DatabaseCredential(password: Self.dbPassword, keyFile: keyFile)
        )
        XCTAssertEqual(try githubEntry(in: doc).password.reveal(), Self.entryPassword)
    }

    func testWrongPasswordMapsToTypedError() throws {
        let data = try fixture("demo-password", ext: "kdbx")
        XCTAssertThrowsError(
            try DatabaseDocument.open(data: data, credentials: DatabaseCredential(password: "faux"))
        ) { error in
            XCTAssertEqual(error as? DatabaseOpenError, .wrongCredentials)
        }
    }

    func testMissingCredentialsMapsToTypedError() throws {
        let data = try fixture("demo-password", ext: "kdbx")
        XCTAssertThrowsError(
            try DatabaseDocument.open(data: data, credentials: DatabaseCredential())
        ) { error in
            XCTAssertEqual(error as? DatabaseOpenError, .missingCredentials)
        }
    }

    /// « Secret non exposé » (§4.4) : le mot de passe n'apparaît pas en clair dans le modèle
    /// (ni via `description`/`debugDescription`, ni via une propriété `String`).
    func testPasswordNotExposedInCleartext() throws {
        let data = try fixture("demo-password", ext: "kdbx")
        let doc = try DatabaseDocument.open(
            data: data,
            credentials: DatabaseCredential(password: Self.dbPassword)
        )
        let entry = try githubEntry(in: doc)

        XCTAssertFalse(String(describing: entry).contains(Self.entryPassword))
        XCTAssertFalse(String(reflecting: entry).contains(Self.entryPassword))
        XCTAssertEqual("\(entry.password)", "••••••")
        // Le clair n'est accessible que par un appel explicite.
        XCTAssertEqual(entry.password.reveal(), Self.entryPassword)
    }
}
