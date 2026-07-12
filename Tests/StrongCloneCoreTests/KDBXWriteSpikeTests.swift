import Foundation
import KDBXKit
import XCTest

@testable import StrongCloneCore

/// Spike d'écriture **bloquant** (kdbx-write §1) : prouve, sur le golden file interop
/// `demo-password.kdbx`, qu'une base éditée puis ré-encodée par `KDBXWriter` se rouvre
/// **dans KeePassXC réel** (`keepassxc-cli`), pas seulement dans notre propre reader.
///
/// C'est la validation « sur preuve » avant tout code d'édition : si l'interop échouait ici,
/// on repenserait l'approche (pièges connus : déclaration `<?xml version>`, séparateur de tags,
/// key-file). Le round-trip interne (read → write → read) ne prouve que la self-consistance.
///
/// Mot de passe FACTICE documenté : `correct horse battery staple`.
final class KDBXWriteSpikeTests: XCTestCase {
    private static let dbPassword = "correct horse battery staple"
    private static let newPassword = "N3w-Sp1ke-P@ss!"

    private func fixtureData(_ name: String, ext: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "Golden file \(name).\(ext) introuvable dans le bundle de test"
        )
        return try Data(contentsOf: url)
    }

    private func findEntry(titled title: String, in group: KDBX.Group) -> KDBX.Entry? {
        for entry in group.entries
        where entry.strings.first(where: { $0.key == "Title" })?.value.revealedString == title {
            return entry
        }
        for sub in group.groups {
            if let found = findEntry(titled: title, in: sub) { return found }
        }
        return nil
    }

    /// Ré-encode un `KDBXContent` en octets `.kdbx` via `KDBXWriter.write` (buffer mémoire).
    private func serialize(_ content: KDBXContent, password: String) throws -> Data {
        let stream = OutputStream(toMemory: ())
        stream.open()
        let writer = KDBXWriter(to: stream)
        try writer.write(content, unlockData: UnlockData(masterPassword: password))
        return try XCTUnwrap(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
    }

    /// SPIKE : mute le mot de passe d'une entrée en `.unprotected`, ré-encode, écrit dans un
    /// fichier temporaire, puis ouvre avec `keepassxc-cli` réel et vérifie que la modification
    /// est lue. Gaté sur la présence du binaire (no-op sinon — la CI l'installe).
    func testEditedPasswordReopensInKeePassXC() throws {
        try XCTSkipUnless(
            KeePassXCInterop.isAvailable,
            "keepassxc-cli introuvable — spike interop exécuté en CI (Homebrew)"
        )

        // 1.1 Charger et muter en mémoire l'arbre KDBX.Entry.
        let data = try fixtureData("demo-password", ext: "kdbx")
        var content = try KDBXReader.parse(data, unlockData: UnlockData(masterPassword: Self.dbPassword))
        let target = try XCTUnwrap(findEntry(titled: "GitHub", in: content.database.root.group))

        var found = false
        TreeMutatorProbe.mutateEntry(uuid: target.uuid, in: &content.database) { entry in
            if let idx = entry.strings.firstIndex(where: { $0.key == "Password" }) {
                entry.strings[idx].value = .unprotected(Self.newPassword)
            }
            found = true
        }
        XCTAssertTrue(found, "L'entrée cible doit être trouvée dans l'arbre")

        // 1.2 Ré-encoder via KDBXWriter vers un buffer, écrire dans un fichier temporaire.
        let bytes = try serialize(content, password: Self.dbPassword)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spike-\(UUID().uuidString).kdbx")
        try bytes.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // 1.3 Ouvrir avec keepassxc-cli réel et asserter que la modification est lue.
        let output = try KeePassXCInterop.showEntry(
            databaseURL: tmpURL,
            password: Self.dbPassword,
            entryPath: "GitHub"
        )
        XCTAssertTrue(
            output.contains("Password: \(Self.newPassword)"),
            "keepassxc-cli doit lire le nouveau mot de passe. Sortie : \(output)"
        )
    }
}

/// Mini-sonde de mutation utilisée par le seul spike (le vrai moteur d'édition Core arrive en
/// §2). Duplique volontairement le parcours par UUID de `TreeMutator` du CLI KDBXKit pour ne
/// dépendre que de `KDBXKit` (Core n'importe jamais `KDBXCLICore`).
private enum TreeMutatorProbe {
    static func mutateEntry(uuid: UUID, in db: inout KDBX, _ body: (inout KDBX.Entry) -> Void) {
        mutate(uuid: uuid, in: &db.root.group, body)
    }

    @discardableResult
    private static func mutate(uuid: UUID, in group: inout KDBX.Group, _ body: (inout KDBX.Entry) -> Void) -> Bool {
        for index in group.entries.indices where group.entries[index].uuid == uuid {
            body(&group.entries[index])
            return true
        }
        for index in group.groups.indices where mutate(uuid: uuid, in: &group.groups[index], body) {
            return true
        }
        return false
    }
}
