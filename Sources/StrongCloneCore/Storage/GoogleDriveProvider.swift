import Foundation

/// `StorageProvider` adossé à Google Drive : enveloppe un `DriveClient` injecté et un `fileId`.
/// Le Core reste agnostique du transport — l'`identifier` de la base est le `fileId` Drive
/// (uniforme avec le local : sert aussi de clé Keychain pour FaceID, change `faceid-unlock`).
///
/// Écriture **avec détection de conflit** (change `google-drive-sync`) : `save` relit la révision
/// distante et refuse d'écraser si elle a changé depuis le chargement, plutôt que d'écraser à
/// l'aveugle (CLAUDE.md §4).
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

    /// Téléverse la base vers Drive **après** vérification de non-régression :
    /// - `expectedRemote` fourni : on relit la révision distante courante et on la compare à
    ///   `expectedRemote.revisionToken`. Divergence ⇒ `StorageError.conflict(remote:)`, **aucun
    ///   octet écrit** (les métadonnées distantes courantes sont jointes pour l'UI).
    /// - `expectedRemote` absent (création / pas de référence) : upload direct.
    ///
    /// Concordance ⇒ upload puis retour d'un `StorageMetadata` au **nouveau** jeton de révision.
    /// Limite v1 assumée : fenêtre de course entre la relecture et l'upload (détection best-effort,
    /// pas de verrou distant transactionnel — voir design.md).
    public func save(_ data: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata {
        if let expected = expectedRemote {
            let current = try await client.metadata(fileId: fileId)
            if expected.revisionToken != current.revisionToken {
                throw StorageError.conflict(remote: current)
            }
        }
        return try await client.upload(fileId: fileId, data: data)
    }
}
