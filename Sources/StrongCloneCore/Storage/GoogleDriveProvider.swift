import Foundation

/// `StorageProvider` adossé à Google Drive : enveloppe un `DriveClient` injecté et un `fileId`.
/// Le Core reste agnostique du transport — l'`identifier` de la base est le `fileId` Drive
/// (uniforme avec le local : sert aussi de clé Keychain pour FaceID, change `faceid-unlock`).
///
/// Lecture seule en v1 : `save` est un stub typé (l'écriture arrive avec `kdbx-write`).
public struct GoogleDriveProvider<Client: DriveClient>: StorageProvider {
    private let client: Client
    private let fileId: String

    public init(client: Client, fileId: String) {
        self.client = client
        self.fileId = fileId
    }

    public func metadata() async throws -> StorageMetadata {
        try await client.metadata(fileId: fileId)
    }

    public func load() async throws -> Data {
        try await client.download(fileId: fileId)
    }

    public func save(_ data: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata {
        throw StorageError.unknown("Base Google Drive en lecture seule (écriture : change kdbx-write)")
    }
}
