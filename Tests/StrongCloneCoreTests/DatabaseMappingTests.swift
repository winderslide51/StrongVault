import Foundation
import KDBXKit
import XCTest

@testable import StrongCloneCore

/// Mapping enrichi `KDBX.Entry` → `Entry` (kdbx-read §2.2) : champs custom (protégés/non), TOTP
/// branché, pièces jointes inline et par référence. Construit des entrées KeePass en mémoire —
/// `keepassxc-cli` ne sait pas injecter de champ TOTP/pièce jointe, d'où le mapping exercé
/// directement (point d'entrée interne `mapEntry`).
final class DatabaseMappingTests: XCTestCase {
    private func string(_ key: String, _ value: KDBX.ProtectedString.Value) -> KDBX.ProtectedString {
        KDBX.ProtectedString(key: key, value: value)
    }

    func testMapsCustomFieldsWithProtectionFlag() {
        let entry = KDBX.Entry(
            uuid: UUID(),
            strings: [
                string("Title", .regular("Acme")),
                string("UserName", .regular("bob")),
                string("Password", .unprotected("pw")),
                string("Note publique", .regular("visible")),
                string("Clé API", .unprotected("secret-key"))
            ]
        )
        let mapped = DatabaseDocument.mapEntry(entry, binaryPool: [])

        XCTAssertEqual(mapped.title, "Acme")
        XCTAssertEqual(mapped.username, "bob")
        XCTAssertEqual(mapped.password.reveal(), "pw")

        // Les champs standard ne sont pas dupliqués dans customFields.
        let keys = mapped.customFields.map(\.key).sorted()
        XCTAssertEqual(keys, ["Clé API", "Note publique"])

        let plain = try? XCTUnwrap(mapped.customFields.first { $0.key == "Note publique" })
        XCTAssertEqual(plain?.value, "visible")
        XCTAssertEqual(plain?.isProtected, false)

        let secret = try? XCTUnwrap(mapped.customFields.first { $0.key == "Clé API" })
        XCTAssertEqual(secret?.value, "secret-key")
        XCTAssertEqual(secret?.isProtected, true)
    }

    func testMapsTotpFromKeePassXCFields() {
        let entry = KDBX.Entry(
            uuid: UUID(),
            strings: [
                string("Title", .regular("Acme")),
                string("TOTP Seed", .unprotected("JBSWY3DPEHPK3PXP")),
                string("TOTP Settings", .regular("30;6"))
            ]
        )
        let mapped = DatabaseDocument.mapEntry(entry, binaryPool: [])

        XCTAssertEqual(mapped.totp?.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(mapped.totp?.digits, 6)
        XCTAssertEqual(mapped.totp?.period, 30)
        // Les champs TOTP sont consommés : absents des champs custom.
        XCTAssertTrue(mapped.customFields.isEmpty)
    }

    func testMapsTotpFromOtpauthURI() {
        let entry = KDBX.Entry(
            uuid: UUID(),
            strings: [
                string("Title", .regular("Acme")),
                string(
                    "otp",
                    .unprotected("otpauth://totp/Acme?secret=JBSWY3DPEHPK3PXP&algorithm=SHA512&digits=8&period=60"))
            ]
        )
        let mapped = DatabaseDocument.mapEntry(entry, binaryPool: [])

        XCTAssertEqual(mapped.totp?.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(mapped.totp?.algorithm, .sha512)
        XCTAssertEqual(mapped.totp?.digits, 8)
        XCTAssertEqual(mapped.totp?.period, 60)
        XCTAssertTrue(mapped.customFields.isEmpty)
    }

    func testMapsInlineAndReferencedAttachments() {
        let pooledBytes = Data("pooled-bytes".utf8)
        let entry = KDBX.Entry(
            uuid: UUID(),
            strings: [string("Title", .regular("Acme"))],
            binaries: [
                KDBX.ProtectedBinary(key: "inline.txt", value: .inline(Data("hello".utf8), protected: false)),
                KDBX.ProtectedBinary(key: "pooled.bin", value: .ref(0)),
                KDBX.ProtectedBinary(key: "dangling.bin", value: .ref(9))
            ]
        )
        let mapped = DatabaseDocument.mapEntry(entry, binaryPool: [pooledBytes])

        // La référence hors bornes (9) est ignorée sans planter.
        XCTAssertEqual(mapped.attachments.count, 2)
        let inline = try? XCTUnwrap(mapped.attachments.first { $0.name == "inline.txt" })
        XCTAssertEqual(inline?.data, Data("hello".utf8))
        let pooled = try? XCTUnwrap(mapped.attachments.first { $0.name == "pooled.bin" })
        XCTAssertEqual(pooled?.data, pooledBytes)
    }

    func testProtectedCustomFieldCarriesIsProtectedFlag() {
        let entry = KDBX.Entry(
            uuid: UUID(),
            strings: [
                string("Title", .regular("Acme")),
                string("Clé API", .unprotected("top-secret-value"))
            ]
        )
        let mapped = DatabaseDocument.mapEntry(entry, binaryPool: [])
        let field = try? XCTUnwrap(mapped.customFields.first)
        // Le modèle garde `value: String` (l'UI masque via isProtected) — on vérifie au moins que
        // le flag de protection est bien porté pour permettre ce masquage.
        XCTAssertEqual(field?.isProtected, true)
    }

    /// Symétrique au test du mot de passe (§4.4) : le seed TOTP est un secret et ne doit pas
    /// être matérialisé en clair via `description`/`reflecting` sur une `Entry`.
    func testTotpSeedNotExposedByDescription() {
        let seed = "JBSWY3DPEHPK3PXP"
        let entry = KDBX.Entry(
            uuid: UUID(),
            strings: [
                string("Title", .regular("Acme")),
                string("TOTP Seed", .unprotected(seed)),
                string("TOTP Settings", .regular("30;6"))
            ]
        )
        let mapped = DatabaseDocument.mapEntry(entry, binaryPool: [])
        XCTAssertEqual(mapped.totp?.secret, seed)  // toujours accessible via l'API explicite

        XCTAssertFalse(String(describing: mapped).contains(seed))
        XCTAssertFalse(String(reflecting: mapped).contains(seed))
        XCTAssertFalse(String(describing: mapped.totp).contains(seed))
        XCTAssertFalse(String(reflecting: mapped.totp).contains(seed))
    }
}
