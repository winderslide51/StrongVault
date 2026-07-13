import Foundation

/// Métadonnées d'un fichier de base distant/local, utiles à la détection de conflit.
public struct StorageMetadata: Sendable, Equatable {
    public var identifier: String  // chemin local, ou fileId Drive
    public var displayName: String
    public var modifiedAt: Date?
    public var sizeBytes: Int?
    /// Jeton de révision **opaque** du côté distant (ex. `headRevisionId`/`modifiedTime` Drive),
    /// capturé au chargement et comparé avant écriture pour détecter un conflit. `nil` en local
    /// (pas de concurrence distante). Le Core ne l'interprète pas : il se contente de l'égalité.
    public var revisionToken: String?

    public init(
        identifier: String,
        displayName: String,
        modifiedAt: Date? = nil,
        sizeBytes: Int? = nil,
        revisionToken: String? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes
        self.revisionToken = revisionToken
    }
}

public enum StorageError: Error, Equatable, Sendable {
    case notFound
    case accessDenied
    case conflict(remote: StorageMetadata)  // la version distante a changé
    case network(String)
    case unknown(String)
}

/// Abstraction d'un emplacement de base `.kdbx`. Deux implémentations prévues :
/// `LocalStorageProvider` (Fichiers/sandbox) et `GoogleDriveProvider` (change `google-drive`).
/// Le Core reste agnostique de la source ; l'app injecte l'implémentation concrète.
public protocol StorageProvider: Sendable {
    /// Métadonnées courantes du fichier (pour comparer avant écrasement).
    func metadata() async throws -> StorageMetadata

    /// Télécharge/lit les octets bruts de la base `.kdbx`.
    func load() async throws -> Data

    /// Écrit les octets. `expectedRemote` permet une écriture conditionnelle :
    /// si la version distante diffère, l'implémentation doit lever `StorageError.conflict`.
    func save(_ data: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata
}
