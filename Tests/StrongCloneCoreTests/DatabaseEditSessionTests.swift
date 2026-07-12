import Foundation
import KDBXKit
import XCTest

@testable import StrongCloneCore

/// Tests du moteur d'édition (`database-editing`) et de la sérialisation (`database-saving`).
/// Chaque exigence des specs porte ≥1 scénario. La preuve interop `keepassxc-cli` vit dans
/// `KDBXWriteSpikeTests` (spike) et l'étape CI ; ici on prouve la mécanique Core en Swift pur.
///
/// Mots de passe FACTICES documentés : base `correct horse battery staple`.
final class DatabaseEditSessionTests: XCTestCase {
    private static let dbPassword = "correct horse battery staple"

    // Horloge déterministe très postérieure aux dates des fixtures : garantit qu'un bump de
    // `lastModificationTime` est strictement postérieur à la valeur d'origine.
    private static let fixedNow = Date(timeIntervalSince1970: 4_000_000_000)

    private func fixtureData(_ name: String, ext: String = "kdbx") throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "Golden file \(name).\(ext) introuvable"
        )
        return try Data(contentsOf: url)
    }

    private func makeSession(
        _ fixture: String = "demo-password",
        now: @escaping @Sendable () -> Date = { DatabaseEditSessionTests.fixedNow }
    ) throws -> DatabaseEditSession {
        try DatabaseEditSession.open(
            data: try fixtureData(fixture),
            credentials: DatabaseCredential(password: Self.dbPassword),
            now: now
        )
    }

    private func credential() -> DatabaseCredential { DatabaseCredential(password: Self.dbPassword) }

    /// UUID de l'entrée « GitHub » du fixture, via la projection domaine.
    private func gitHubEntryID(_ session: DatabaseEditSession) throws -> UUID {
        let entry = try XCTUnwrap(
            session.document.root.allEntriesRecursive.first { $0.title == "GitHub" },
            "Entrée GitHub introuvable"
        )
        return entry.id
    }

    /// Reparse des octets produits vers un `KDBXContent` (pour asserter round-trip + protection).
    private func reparse(_ data: Data) throws -> KDBXContent {
        try KDBXReader.parse(data, unlockData: UnlockData(masterPassword: Self.dbPassword))
    }

    private func entry(titled title: String, in content: KDBXContent) -> KDBX.Entry? {
        var match: KDBX.Entry?
        content.database.visitEntries(in: content.database.root.group) { entry in
            if entry.strings.first(where: { $0.key == "Title" })?.value.revealedString == title {
                match = entry
            }
        }
        return match
    }

    private func field(_ key: String, in entry: KDBX.Entry) -> KDBX.ProtectedString.Value? {
        entry.strings.first { $0.key == key }?.value
    }

    /// `true` si la valeur est chiffrée au repos. Après round-trip, `.unprotected` revient en
    /// `.lazyInnerCipher` (protégé) ; `.regular` reste en clair.
    private func isProtectedOnDisk(_ value: KDBX.ProtectedString.Value) -> Bool {
        switch value {
        case .regular: return false
        case .unprotected, .protectedInMemory, .lazyInnerCipher: return true
        }
    }

    // MARK: - 6.1 Édition mot de passe

    func testSetPasswordUsesUnprotectedBumpsModifiedAndSnapshotsHistory() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)

        let before = try XCTUnwrap(entry(titled: "GitHub", in: session.content))
        let modifiedBefore = before.times?.lastModificationTime
        let historyBefore = before.history.count

        try session.setPassword("N3w-P@ssw0rd", entryID: entryID)

        let after = try XCTUnwrap(entry(titled: "GitHub", in: session.content))
        // Le mot de passe édité est porté en `.unprotected` (chiffré au repos), jamais `.regular`
        // ni `.protectedInMemory`.
        let value = try XCTUnwrap(field("Password", in: after))
        guard case .unprotected = value else {
            return XCTFail("Le mot de passe édité doit être `.unprotected`, obtenu : \(value)")
        }
        XCTAssertEqual(value.revealedString, "N3w-P@ssw0rd")

        // lastModificationTime postérieur + un snapshot historique de plus.
        let modifiedAfter = try XCTUnwrap(after.times?.lastModificationTime)
        XCTAssertEqual(modifiedAfter, Self.fixedNow)
        if let modifiedBefore {
            XCTAssertGreaterThan(modifiedAfter, modifiedBefore)
        }
        XCTAssertEqual(after.history.count, historyBefore + 1)

        // Le snapshot capture l'état ANTÉRIEUR (parité `entry set` du CLI KDBXKit) : l'ancien
        // mot de passe est dans l'historique — c'est ce qui rend l'édition réversible — et il
        // y reste protégé (jamais `.regular`).
        let snapshot = try XCTUnwrap(after.history.last)
        let oldValue = try XCTUnwrap(field("Password", in: snapshot))
        XCTAssertEqual(oldValue.revealedString, field("Password", in: before)?.revealedString)
        XCTAssertNotEqual(oldValue.revealedString, "N3w-P@ssw0rd")
        XCTAssertTrue(snapshot.history.isEmpty, "Une entrée historique ne porte pas son propre historique")
        if case .regular = oldValue {
            XCTFail("L'ancien mot de passe doit rester protégé dans l'historique")
        }

        // Round-trip : la valeur reste protégée sur disque après ré-ouverture.
        let reparsed = try reparse(try session.serialize())
        let reEntry = try XCTUnwrap(entry(titled: "GitHub", in: reparsed))
        let reValue = try XCTUnwrap(field("Password", in: reEntry))
        XCTAssertTrue(isProtectedOnDisk(reValue), "Le mot de passe doit rester protégé sur disque")
        XCTAssertEqual(reValue.revealedString, "N3w-P@ssw0rd")
    }

    // MARK: - 6.2 Champs standard + custom protégé / non protégé

    func testSetStandardFieldUpdatesValueAndBumpsModified() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)

        try session.setStandardField(.title, value: "GitHub Pro", entryID: entryID)

        let reparsed = try reparse(try session.serialize())
        let reEntry = try XCTUnwrap(entry(titled: "GitHub Pro", in: reparsed))
        XCTAssertEqual(field("Title", in: reEntry)?.revealedString, "GitHub Pro")
        XCTAssertEqual(reEntry.times?.lastModificationTime, Self.fixedNow)
    }

    func testCustomFieldProtectedVsRegular() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)

        try session.setCustomField(key: "Recovery", secret: "code-42", isProtected: true, entryID: entryID)
        try session.setCustomField(key: "Environment", secret: "prod", isProtected: false, entryID: entryID)

        // En mémoire : `.unprotected` pour le protégé, `.regular` pour le clair.
        let inMemory = try XCTUnwrap(entry(titled: "GitHub", in: session.content))
        guard case .unprotected = try XCTUnwrap(field("Recovery", in: inMemory)) else {
            return XCTFail("Champ custom protégé doit être `.unprotected`")
        }
        guard case .regular = try XCTUnwrap(field("Environment", in: inMemory)) else {
            return XCTFail("Champ custom non protégé doit être `.regular`")
        }

        // Round-trip : le protégé reste chiffré sur disque, le non protégé en clair.
        let reparsed = try reparse(try session.serialize())
        let reEntry = try XCTUnwrap(entry(titled: "GitHub", in: reparsed))
        XCTAssertTrue(isProtectedOnDisk(try XCTUnwrap(field("Recovery", in: reEntry))))
        XCTAssertFalse(isProtectedOnDisk(try XCTUnwrap(field("Environment", in: reEntry))))
        XCTAssertEqual(field("Recovery", in: reEntry)?.revealedString, "code-42")
        XCTAssertEqual(field("Environment", in: reEntry)?.revealedString, "prod")
    }

    func testRemoveCustomField() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)
        try session.setCustomField(key: "Temp", secret: "x", isProtected: false, entryID: entryID)
        try session.removeCustomField(key: "Temp", entryID: entryID)

        let reparsed = try reparse(try session.serialize())
        let reEntry = try XCTUnwrap(entry(titled: "GitHub", in: reparsed))
        XCTAssertNil(field("Temp", in: reEntry))
    }

    // MARK: - 6.3 CRUD entrées & groupes

    func testAddAndRemoveEntry() throws {
        var session = try makeSession()
        let rootID = session.document.root.id

        let newID = try session.addEntry(title: "New Login", password: "s3kr3t", inGroup: rootID)
        var reparsed = try reparse(try session.serialize())
        let added = try XCTUnwrap(entry(titled: "New Login", in: reparsed))
        XCTAssertEqual(added.uuid, newID)
        XCTAssertTrue(isProtectedOnDisk(try XCTUnwrap(field("Password", in: added))))
        XCTAssertEqual(field("Password", in: added)?.revealedString, "s3kr3t")

        try session.removeEntry(newID)
        reparsed = try reparse(try session.serialize())
        XCTAssertNil(entry(titled: "New Login", in: reparsed))
    }

    func testRemoveEntryUnknownThrows() throws {
        var session = try makeSession()
        XCTAssertThrowsError(try session.removeEntry(UUID())) { error in
            guard case .entryNotFound = error as? DatabaseEditError else {
                return XCTFail("Attendu entryNotFound, obtenu \(error)")
            }
        }
    }

    func testAddRenameAndRemoveGroup() throws {
        var session = try makeSession()
        let rootID = session.document.root.id

        let groupID = try session.addGroup(name: "Banking", inGroup: rootID)
        try session.renameGroup(groupID, to: "Finance")
        try session.addEntry(title: "Bank", password: "pw", inGroup: groupID)

        var reparsed = try reparse(try session.serialize())
        var doc = DatabaseDocument.map(reparsed)
        let finance = try XCTUnwrap(doc.root.subgroups.first { $0.name == "Finance" })
        XCTAssertNil(doc.root.subgroups.first { $0.name == "Banking" })
        XCTAssertTrue(finance.entries.contains { $0.title == "Bank" })

        try session.removeGroup(groupID)
        reparsed = try reparse(try session.serialize())
        doc = DatabaseDocument.map(reparsed)
        XCTAssertNil(doc.root.subgroups.first { $0.name == "Finance" })
        // Le contenu du groupe supprimé disparaît aussi.
        XCTAssertNil(entry(titled: "Bank", in: reparsed))
    }

    func testRemoveRootRejected() throws {
        var session = try makeSession()
        let rootID = session.document.root.id
        XCTAssertThrowsError(try session.removeGroup(rootID)) { error in
            XCTAssertEqual(error as? DatabaseEditError, .cannotRemoveRoot)
        }
    }

    // MARK: - 6.4 Préservation des données non modélisées

    func testUnmodeledFieldPreservedAcrossEdit() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)

        // Injecte un champ propriétaire inconnu du modèle domaine directement dans l'arbre KDBX,
        // pour simuler une base produite par un autre client.
        let proprietaryKey = "X-Proprietary-Flag"
        let proprietaryValue = "vendor-specific-0xCAFE"
        Self.injectRawField(key: proprietaryKey, value: proprietaryValue, entryUUID: entryID, into: &session)

        // On édite un AUTRE champ (le titre) puis on ré-sérialise.
        try session.setStandardField(.title, value: "GitHub Edited", entryID: entryID)

        let reparsed = try reparse(try session.serialize())
        let reEntry = try XCTUnwrap(entry(titled: "GitHub Edited", in: reparsed))
        // Le champ non modélisé est toujours présent, à l'identique : preuve de la mutation en
        // place vs. reconstruction lossy depuis le domaine.
        XCTAssertEqual(field(proprietaryKey, in: reEntry)?.revealedString, proprietaryValue)
    }

    // MARK: - 6.5 Migration 3.1 → 4.1

    func testLegacy31ReportsMigrationNotice() throws {
        let session = try makeSession("demo-legacy-3x")
        XCTAssertEqual(session.legacyMigrationNotice, .willMigrate(fromVersion: "3.1"))
    }

    func testModern4xReportsNoMigrationNotice() throws {
        let session = try makeSession("demo-modern-4x")
        XCTAssertNil(session.legacyMigrationNotice)
    }

    func testLegacy31MigratesToModernOnSaveAndKeepsData() throws {
        var session = try makeSession("demo-legacy-3x")
        let entryID = try gitHubEntryID(session)
        try session.setStandardField(.notes, value: "migrated", entryID: entryID)

        let bytes = try session.serialize()
        // Après écriture, le fichier est en 4.x → plus d'avertissement à la ré-ouverture.
        let reparsed = try reparse(bytes)
        XCTAssertFalse(reparsed.header.formatVersion.isLegacy3x)
        XCTAssertNil(reparsed.legacyFormatNotice)
        let reEntry = try XCTUnwrap(entry(titled: "GitHub", in: reparsed))
        XCTAssertEqual(field("Notes", in: reEntry)?.revealedString, "migrated")
    }

    // MARK: - 6.6 Sécurité — aucun secret en clair dans les descriptions

    func testEditedSecretNotExposedInModelDescription() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)
        let secret = "ultra-secret-XYZ-987"
        try session.setPassword(ProtectedSecret(secret), entryID: entryID)

        let entry = try XCTUnwrap(session.document.root.allEntriesRecursive.first { $0.title == "GitHub" })
        // Ni description, ni debugDescription du modèle ne matérialisent le secret en clair.
        XCTAssertFalse(String(describing: entry).contains(secret))
        XCTAssertFalse(String(reflecting: entry).contains(secret))
        XCTAssertFalse(String(describing: entry.password).contains(secret))
        XCTAssertFalse(String(reflecting: entry.password).contains(secret))
        // Le secret n'est accessible que par révélation explicite.
        XCTAssertEqual(entry.password.reveal(), secret)
    }

    // MARK: - database-saving : round-trip & régénération des sels

    func testRoundTripReadWriteReadPreservesEdit() throws {
        var session = try makeSession()
        let entryID = try gitHubEntryID(session)
        try session.setStandardField(.username, value: "bob@example.com", entryID: entryID)

        let reopened = try DatabaseEditSession.open(
            data: try session.serialize(),
            credentials: credential()
        )
        let entry = try XCTUnwrap(reopened.document.root.allEntriesRecursive.first { $0.title == "GitHub" })
        XCTAssertEqual(entry.username, "bob@example.com")
    }

    func testRegenerateSaltsByDefaultProducesDifferentBytes() throws {
        let session = try makeSession()
        let first = try session.serialize()
        let second = try session.serialize()
        // Sels/nonce régénérés par défaut → octets différents à chaque sauvegarde.
        XCTAssertNotEqual(first, second)
    }

    // MARK: - 5.2 Round-trip byte-identique (regenerateSalts: false)

    func testByteIdenticalRoundTripWithoutSaltRegeneration() throws {
        let session = try makeSession()
        let first = try session.serialize(regenerateSalts: false)
        let second = try session.serialize(regenerateSalts: false)
        // Sans régénération de sels, le sérialiseur est déterministe.
        XCTAssertEqual(first, second)
    }

    // MARK: - Helper d'injection d'un champ brut (données non modélisées)

    /// Insère un `<String>` arbitraire dans l'entrée ciblée en muant directement le `KDBXContent`
    /// conservé (`content` interne, visible via `@testable`). Simule un champ propriétaire produit
    /// par un autre client.
    private static func injectRawField(
        key: String,
        value: String,
        entryUUID: UUID,
        into session: inout DatabaseEditSession
    ) {
        func inject(into group: inout KDBX.Group) -> Bool {
            for index in group.entries.indices where group.entries[index].uuid == entryUUID {
                group.entries[index].strings.append(KDBX.ProtectedString(key: key, value: .regular(value)))
                return true
            }
            for index in group.groups.indices where inject(into: &group.groups[index]) { return true }
            return false
        }
        _ = inject(into: &session.content.database.root.group)
    }
}
