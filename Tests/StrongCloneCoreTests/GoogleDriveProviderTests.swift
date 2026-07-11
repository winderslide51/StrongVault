import Foundation
import XCTest

@testable import StrongCloneCore

/// Faux `DriveClient` en mémoire : sert les octets/métadonnées d'un ensemble de fichiers, ou
/// lève une `StorageError` configurée (simulation absent/réseau). Permet de prouver
/// `GoogleDriveProvider` en CI, sans SDK Drive ni réseau.
private struct FakeDriveClient: DriveClient {
    var files: [String: (data: Data, meta: StorageMetadata)] = [:]
    var downloadError: StorageError?

    func metadata(fileId: String) async throws -> StorageMetadata {
        guard let file = files[fileId] else { throw StorageError.notFound }
        return file.meta
    }

    func download(fileId: String) async throws -> Data {
        if let downloadError { throw downloadError }
        guard let file = files[fileId] else { throw StorageError.notFound }
        return file.data
    }
}

final class GoogleDriveProviderTests: XCTestCase {
    private func meta(_ fileId: String, name: String) -> StorageMetadata {
        StorageMetadata(
            identifier: fileId,
            displayName: name,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sizeBytes: nil
        )
    }

    func testLoadReturnsFileBytes() async throws {
        let bytes = Data("kdbx-bytes".utf8)
        let client = FakeDriveClient(files: ["file-1": (bytes, meta("file-1", name: "coffre.kdbx"))])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let loaded = try await provider.load()
        XCTAssertEqual(loaded, bytes)
    }

    func testMetadataUsesFileIdAsIdentifier() async throws {
        let client = FakeDriveClient(files: ["file-1": (Data(), meta("file-1", name: "coffre.kdbx"))])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")

        let metadata = try await provider.metadata()
        XCTAssertEqual(metadata.identifier, "file-1")
        XCTAssertEqual(metadata.displayName, "coffre.kdbx")
        XCTAssertEqual(metadata.modifiedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testLoadMissingFileMapsToNotFound() async {
        let provider = GoogleDriveProvider(client: FakeDriveClient(), fileId: "absent")
        await assertThrowsStorageError(.notFound) { try await provider.load() }
    }

    func testLoadNetworkErrorPropagates() async {
        let client = FakeDriveClient(downloadError: .network("timeout"))
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")
        await assertThrowsStorageError(.network("timeout")) { try await provider.load() }
    }

    func testSaveIsReadOnly() async {
        let client = FakeDriveClient(files: ["file-1": (Data(), meta("file-1", name: "x.kdbx"))])
        let provider = GoogleDriveProvider(client: client, fileId: "file-1")
        do {
            _ = try await provider.save(Data(), expectedRemote: nil)
            XCTFail("Drive est en lecture seule en v1")
        } catch let error as StorageError {
            guard case .unknown = error else {
                return XCTFail("Erreur inattendue : \(error)")
            }
        } catch {
            XCTFail("Type d'erreur inattendu : \(error)")
        }
    }

    /// Le key file optionnel est un **fetch distinct** : deux providers sur deux `fileId`
    /// renvoient chacun leurs octets indépendamment (base vs key file).
    func testDatabaseAndKeyFileAreFetchedIndependently() async throws {
        let dbBytes = Data("db".utf8)
        let keyBytes = Data("key".utf8)
        let client = FakeDriveClient(files: [
            "db-file": (dbBytes, meta("db-file", name: "coffre.kdbx")),
            "key-file": (keyBytes, meta("key-file", name: "coffre.key"))
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
