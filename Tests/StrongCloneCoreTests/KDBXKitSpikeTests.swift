import Foundation
// Spike KDBXKit (kdbx-read §1) : prouve, sur des golden files générés par KeePastXC
// (source de vérité interop), que KDBXKit lit une vraie base .kdbx et qu'on peut en
// extraire un contenu connu. C'est la validation « sur preuve » avant de bâtir l'UI :
// si un cas requis échouait ici, on basculerait sur le repli KeePassKit (CLAUDE.md §6).
//
// Golden files (mots de passe FACTICES documentés) :
//   - demo-password.kdbx  : AES-256 + AES-KDF, mot de passe seul
//   - demo-keyfile.kdbx   : idem + key file binaire brut 32 o (demo-keyfile.key)
//
// Note interop (surfacée par ce spike) : KDBXKit 1.3.0 lit mal les key files XML v2.0
// générés par KeePassXC (il décode le champ <Data> hex comme du base64) → on utilise un
// key file binaire brut de 32 octets, correctement géré par KDBXKit ET KeePassXC.
// Contenu attendu : une entrée « GitHub » (alice@example.com / s3cr3t-P@ss-42).
import KDBXKit
import XCTest

@testable import StrongCloneCore

final class KDBXKitSpikeTests: XCTestCase {
    private static let dbPassword = "correct horse battery staple"
    private static let entryPassword = "s3cr3t-P@ss-42"

    private func fixtureData(_ name: String, ext: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "Golden file \(name).\(ext) introuvable dans le bundle de test"
        )
        return try Data(contentsOf: url)
    }

    /// Cherche une entrée par titre en parcourant l'arbre des groupes.
    private func findEntry(titled title: String, in group: KDBX.Group) -> KDBX.Entry? {
        for entry in group.entries where value(of: "Title", in: entry) == title {
            return entry
        }
        for sub in group.groups {
            if let found = findEntry(titled: title, in: sub) { return found }
        }
        return nil
    }

    private func value(of key: String, in entry: KDBX.Entry) -> String? {
        entry.strings.first { $0.key == key }?.value.revealedString
    }

    func testOpensPasswordOnlyGoldenFileAndReadsKnownEntry() throws {
        let data = try fixtureData("demo-password", ext: "kdbx")
        let content = try KDBXReader.parse(data, unlockData: UnlockData(masterPassword: Self.dbPassword))

        let entry = try XCTUnwrap(findEntry(titled: "GitHub", in: content.database.root.group))
        XCTAssertEqual(value(of: "UserName", in: entry), "alice@example.com")
        XCTAssertEqual(value(of: "Password", in: entry), Self.entryPassword)
        XCTAssertEqual(value(of: "URL", in: entry), "https://example.com")
    }

    func testOpensKeyFileGoldenFile() throws {
        let data = try fixtureData("demo-keyfile", ext: "kdbx")
        let keyFile = try fixtureData("demo-keyfile", ext: "key")
        let unlock = try UnlockData(masterPassword: Self.dbPassword, keyFile: keyFile)
        let content = try KDBXReader.parse(data, unlockData: unlock)

        let entry = try XCTUnwrap(findEntry(titled: "GitHub", in: content.database.root.group))
        XCTAssertEqual(value(of: "Password", in: entry), Self.entryPassword)
    }

    func testWrongPasswordThrowsTypedError() throws {
        let data = try fixtureData("demo-password", ext: "kdbx")
        XCTAssertThrowsError(
            try KDBXReader.parse(data, unlockData: UnlockData(masterPassword: "mauvais"))
        ) { error in
            XCTAssertEqual(error as? KDBXReader.Error, .wrongCredentials)
        }
    }

    /// Valide le chemin FaceID (Option A) : la clé composite 32 octets exposée après un
    /// déverrouillage par mot de passe rouvre la base via `UnlockData(rawKeyData:)`.
    /// C'est exactement ce que `faceid-unlock` stockera en Keychain (voir PR3).
    func testCompositeKeyRoundTripEnablesRawKeyReopen() throws {
        let data = try fixtureData("demo-password", ext: "kdbx")
        let unlock = UnlockData(masterPassword: Self.dbPassword)
        _ = try KDBXReader.parse(data, unlockData: unlock)

        let rawKey = unlock.keyDataBytes.toData()
        XCTAssertEqual(rawKey.count, 32, "La clé composite doit faire 32 octets")

        let content = try KDBXReader.parse(data, unlockData: UnlockData(rawKeyData: rawKey))
        let entry = try XCTUnwrap(findEntry(titled: "GitHub", in: content.database.root.group))
        XCTAssertEqual(value(of: "Password", in: entry), Self.entryPassword)
    }
}
