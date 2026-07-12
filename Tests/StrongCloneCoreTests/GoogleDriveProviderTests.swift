import Foundation
import XCTest

@testable import StrongCloneCore

/// Faux `DriveClient` en mémoire : sert les octets/métadonnées d'un ensemble de fichiers avec une
/// **révision programmable**, simule l'upload (qui incrémente la révision), ou lève une
/// `StorageError` configurée (absent/réseau/révocation). Permet de prouver `GoogleDriveProvider`
/// en CI, sans SDK Drive ni réseau.
///
/// `actor` : l'upload mute l'état (révision), et l'isolation garantit `Sendable`.
private actor FakeDriveClient: DriveClient {
    struct Entry {
        var data: Data
        var name: String
        var revision: Int
    }

    private var files: [String: Entry]
    private let downloadError: StorageError?
    /// Erreur levée par `metadata`/`download`/`upload` (ex. révocation d'autorisation).
    private let accessError: StorageError?

    init(files: [String: Entry] = [:], downloadError: StorageError? = nil, accessError: StorageError? = nil) {
        self.files = files
        self.downloadError = downloadError
        self.accessError = accessError
    }

    /// Force la révision distante d'un fichier (simule une modification par un autre appareil).
    func bumpRevision(_ fileId: String) {
        files[fileId]?.revision += 1
    }

    private func makeMetadata(fileId: String, entry: Entry) -> StorageMetadata {
        StorageMetadata(
            identifier: fileId,
            displayName: entry.name,
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + entry.revision)),
            sizeBytes: nil,
            revisionToken: "rev-\(entry.revision)"
        )
    }

    func metadata(fileId: String) async throws -> StorageMetadata {
        if let accessError { throw accessError }
        guard let entry = files[fileId] else { throw StorageError.notFound }
        return makeMetadata(fileId: fileId, entry: entry)
    }

    func download(fileId: String) async throws -> Data {
        if let accessError { throw accessError }
        if let downloadError { throw downloadError }
        guard let entry = files[fileId] else { throw StorageError.notFound }
        return entry.data
    }

    func upload(fileId: String, data: Data) async throws -> StorageMetadata {
        if let accessError { throw accessError }
        guard var entry = files[fileId] else { throw StorageError.notFound }
        entry.data = data
        entry.revision += 1
        files[fileId] = entry
        return makeMetadata(fileId: fileId, entry: entry)
    }
}

final class GoogleDriveProviderTests: XCTestCase {
    func testLoadReturnsFileBytes() async throws {
        let bytes = Data("kdbx-bytes".utf8)
        let client = FakeDriveClient(files: ["file-1": .init(data: bytes, name: "coffre.kdbx", revision: 0)])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let loaded = try await provider.load()
        XCTAssertEqual(loaded, bytes)
    }

    func testMetadataUsesFileIdAsIdentifier() async throws {
        let client = FakeDriveClient(files: ["file-1": .init(data: Data(), name: "coffre.kdbx", revision: 0)])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let metadata = try await provider.metadata()
        XCTAssertEqual(metadata.identifier, "file-1")
        XCTAssertEqual(metadata.displayName, "coffre.kdbx")
    }

    /// §4.1 — les métadonnées mappées portent un `revisionToken` non nul reflétant la révision.
    func testMetadataCarriesNonNilRevisionToken() async throws {
        let client = FakeDriveClient(files: ["file-1": .init(data: Data(), name: "coffre.kdbx", revision: 3)])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let metadata = try await provider.metadata()
        XCTAssertNotNil(metadata.revisionToken)
        XCTAssertEqual(metadata.revisionToken, "rev-3")
    }

    func testLoadMissingFileMapsToNotFound() async {
        let provider = GoogleDriveProvider(client: FakeDriveClient(), fileId: "absent")
        await assertThrowsStorageError(.notFound) { _ = try await provider.load() }
    }

    func testLoadNetworkErrorPropagates() async {
        let client = FakeDriveClient(downloadError: .network("timeout"))
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")
        await assertThrowsStorageError(.network("timeout")) { _ = try await provider.load() }
    }

    /// §4.2 — le jeton capturé au chargement (via `metadata()`) est réutilisable comme
    /// `expectedRemote` d'un `save` : ici l'upload passe car la révision n'a pas bougé.
    func testCapturedRevisionTokenIsReusableAsExpectedRemote() async throws {
        let client = FakeDriveClient(files: ["file-1": .init(data: Data("v0".utf8), name: "x.kdbx", revision: 0)])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        _ = try await provider.load()
        let captured = try await provider.metadata()  // capture au chargement

        let updated = try await provider.save(Data("v1".utf8), expectedRemote: captured)
        XCTAssertNotEqual(updated.revisionToken, captured.revisionToken)
    }

    /// §4.3 — un upload réussi renvoie un `revisionToken` distinct de celui fourni, et les octets
    /// distants sont bien remplacés.
    func testSuccessfulUploadReturnsDistinctRevisionToken() async throws {
        let client = FakeDriveClient(files: ["file-1": .init(data: Data("old".utf8), name: "x.kdbx", revision: 0)])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let before = try await provider.metadata()
        let newBytes = Data("new".utf8)
        let after = try await provider.save(newBytes, expectedRemote: before)

        XCTAssertNotEqual(after.revisionToken, before.revisionToken)
        let reloaded = try await provider.load()
        XCTAssertEqual(reloaded, newBytes)
    }

    /// §4.4 — la révision distante a changé depuis la capture ⇒ `conflict`, aucun octet écrit.
    func testConflictWhenRemoteRevisionChanged() async throws {
        let original = Data("original".utf8)
        let client = FakeDriveClient(files: ["file-1": .init(data: original, name: "x.kdbx", revision: 0)])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let captured = try await provider.metadata()
        // Un autre appareil modifie la base entre-temps.
        await client.bumpRevision("file-1")

        do {
            _ = try await provider.save(Data("mine".utf8), expectedRemote: captured)
            XCTFail("Un conflit était attendu")
        } catch let error as StorageError {
            guard case let .conflict(remote) = error else {
                return XCTFail("Erreur inattendue : \(error)")
            }
            XCTAssertEqual(remote.revisionToken, "rev-1")
        }
        // Aucun écrasement : les octets distants restent ceux de la révision distante.
        let remaining = try await provider.load()
        XCTAssertEqual(remaining, original)
    }

    /// §4.5 — autorisation révoquée ⇒ `accessDenied` (aucun jeton n'est journalisé).
    func testRevokedAuthorizationMapsToAccessDenied() async {
        let client = FakeDriveClient(accessError: .accessDenied)
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")
        await assertThrowsStorageError(.accessDenied) { _ = try await provider.load() }
        await assertThrowsStorageError(.accessDenied) {
            _ = try await provider.save(Data(), expectedRemote: nil)
        }
    }

    /// Le key file optionnel est un **fetch distinct** : deux providers sur deux `fileId`
    /// renvoient chacun leurs octets indépendamment (base vs key file).
    func testDatabaseAndKeyFileAreFetchedIndependently() async throws {
        let dbBytes = Data("db".utf8)
        let keyBytes = Data("key".utf8)
        let client = FakeDriveClient(files: [
            "db-file": .init(data: dbBytes, name: "coffre.kdbx", revision: 0),
            "key-file": .init(data: keyBytes, name: "coffre.key", revision: 0)
        ])
        let dbProvider = GoogleDriveProvider(client: client, fileId: "db-file")
        let keyProvider = GoogleDriveProvider(client: client, fileId: "key-file")

        let db = try await dbProvider.load()
        let key = try await keyProvider.load()
        XCTAssertEqual(db, dbBytes)
        XCTAssertEqual(key, keyBytes)
        XCTAssertNotEqual(db, key)
    }

    private func assertThrowsStorageError(
        _ expected: StorageError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Une erreur était attendue", file: file, line: line)
        } catch let error as StorageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Type d'erreur inattendu : \(error)", file: file, line: line)
        }
    }
}
