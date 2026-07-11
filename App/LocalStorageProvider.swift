import Foundation
import StrongCloneCore

/// Fournit les octets d'une base `.kdbx` sélectionnée dans l'app Fichiers, via un
/// **security-scoped bookmark** persistable. Conforme au protocole Core `StorageProvider`
/// (le Core reste agnostique de la provenance). Lecture seule en v1 (`kdbx-write` plus tard).
struct LocalStorageProvider: StorageProvider {
    /// Identifiant stable de la base (servira aussi de clé Keychain pour FaceID, change `faceid-unlock`).
    let identifier: String
    let displayName: String
    /// Bookmark security-scoped résolu à chaque `load()` (jamais le chemin en dur).
    let bookmark: Data

    func metadata() async throws -> StorageMetadata {
        try withResolvedURL { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return StorageMetadata(
                identifier: identifier,
                displayName: displayName,
                modifiedAt: values?.contentModificationDate,
                sizeBytes: values?.fileSize
            )
        }
    }

    func load() async throws -> Data {
        try withResolvedURL { url in
            do {
                return try Data(contentsOf: url)
            } catch {
                throw StorageError.unknown("Lecture du fichier impossible : \(error.localizedDescription)")
            }
        }
    }

    func save(_ data: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata {
        // Écriture hors périmètre v1 (lecture seule). Le vrai chemin arrive avec `kdbx-write`.
        throw StorageError.unknown("Base en lecture seule (écriture : change kdbx-write)")
    }

    /// Résout le bookmark, ouvre l'accès security-scoped le temps du bloc, puis le referme.
    private func withResolvedURL<R>(_ body: (URL) throws -> R) throws -> R {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw StorageError.notFound
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw StorageError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}
