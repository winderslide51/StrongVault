import Foundation
import StrongCloneCore

/// Fournit les octets d'une base `.kdbx` sélectionnée dans l'app Fichiers, via un
/// **security-scoped bookmark** persistable. Conforme au protocole Core `StorageProvider`
/// (le Core reste agnostique de la provenance). Lecture **et écriture** (change `kdbx-write`).
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

    /// Écrit les octets `.kdbx` **atomiquement** à l'emplacement du bookmark et renvoie des
    /// métadonnées à jour. `expectedRemote` est ignoré en local : pas de concurrence distante
    /// (la détection de conflit vit dans `google-drive-sync`, qui réutilise ce même contrat).
    ///
    /// Atomicité : on écrit d'abord un fichier temporaire dans le **même répertoire** (même volume,
    /// donc remplacement par renommage), puis `replaceItem` le substitue à l'original. En cas
    /// d'échec en cours d'écriture, l'original n'est jamais tronqué.
    func save(_ data: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata {
        try withResolvedURL { url in
            let directory = url.deletingLastPathComponent()
            let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).kdbx.tmp")
            do {
                try data.write(to: tempURL, options: .atomic)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw StorageError.unknown("Écriture impossible : \(error.localizedDescription)")
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return StorageMetadata(
                identifier: identifier,
                displayName: displayName,
                modifiedAt: values?.contentModificationDate ?? Date(),
                sizeBytes: values?.fileSize ?? data.count
            )
        }
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
