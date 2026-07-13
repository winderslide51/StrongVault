import Foundation
import GoogleDriveClient
import StrongCloneCore

/// Un fichier `.kdbx` listé sur Google Drive (id + nom), pour la sélection dans l'UI.
struct DriveFile: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
}

/// Implémentation device de `DriveClient` : enveloppe le SDK `swift-google-drive-client`
/// (darrarski), qui parle directement à l'API HTTP Drive (pas de SDK Google). L'OAuth (PKCE,
/// sans secret client) et le refresh des jetons sont gérés par le SDK ; les jetons sont
/// persistés dans le Keychain via `DriveTokenKeychain` (`...ThisDeviceOnly`, **non-iCloud**),
/// jamais dans le repo (CLAUDE.md §4/§6).
///
/// La connexion réelle devient effective dès qu'un vrai `clientID`/`redirectURI` Google Cloud
/// est fourni (voir `GoogleDriveConfig`) ; le provisioning reste une tâche device.
struct GoogleDriveClientLive: DriveClient {
    private let client: Client

    init(config: Config) {
        // Keychain custom : les jetons OAuth ne doivent pas être synchronisés iCloud (le keychain
        // par défaut du SDK utilise `kSecAttrSynchronizable = true` — lève la réserve §5.5).
        client = .live(config: config, keychain: DriveTokenKeychain.make())
    }

    // MARK: - DriveClient (Core)

    func metadata(fileId: String) async throws -> StorageMetadata {
        do {
            let file = try await client.getFile(fileId: fileId)
            return Self.metadata(from: file)
        } catch let error as GetFile.Error {
            throw Self.mapResponseError(notAuthorized: error.isNotAuthorized, statusCode: error.statusCode, error)
        } catch {
            throw Self.mapTransport(error)
        }
    }

    func download(fileId: String) async throws -> Data {
        do {
            return try await client.getFileData(fileId: fileId)
        } catch let error as GetFileData.Error {
            throw Self.mapResponseError(notAuthorized: error.isNotAuthorized, statusCode: error.statusCode, error)
        } catch {
            throw Self.mapTransport(error)
        }
    }

    func upload(fileId: String, data: Data) async throws -> StorageMetadata {
        do {
            // `updateFileData` (multipart PATCH) remplace le contenu d'un fichier existant et
            // renvoie ses métadonnées à jour (nouveau `modifiedTime` ⇒ nouveau jeton de révision).
            let file = try await client.updateFileData(fileId: fileId, data: data, mimeType: Self.kdbxMimeType)
            return Self.metadata(from: file)
        } catch let error as UpdateFileData.Error {
            throw Self.mapResponseError(notAuthorized: error.isNotAuthorized, statusCode: error.statusCode, error)
        } catch {
            throw Self.mapTransport(error)
        }
    }

    /// Type MIME neutre pour un `.kdbx` (conteneur binaire opaque). Le SDK exige un `mimeType`
    /// dans le multipart d'upload ; on ne cherche pas à préserver celui d'origine (cosmétique).
    private static let kdbxMimeType = "application/octet-stream"

    /// Mappe un `File` Drive vers `StorageMetadata`. Le SDK darrarski n'expose **pas**
    /// `headRevisionId` (voir `File.apiFields` : `id,mimeType,name,createdTime,modifiedTime`) :
    /// on dérive donc le **jeton de révision opaque** de `modifiedTime` (ISO 8601, précision
    /// milliseconde). Une écriture change `modifiedTime`, donc le jeton — suffisant pour la
    /// détection best-effort de conflit (design.md).
    private static func metadata(from file: File) -> StorageMetadata {
        StorageMetadata(
            identifier: file.id,
            displayName: file.name,
            modifiedAt: file.modifiedTime,
            sizeBytes: nil,  // l'API `files.get`/`files.update` de ce chemin n'expose pas la taille
            revisionToken: revisionToken(for: file.modifiedTime)
        )
    }

    private static func revisionToken(for date: Date) -> String {
        // `ISO8601DateFormatter` n'est pas `Sendable` : on l'instancie localement (pas d'état
        // mutable partagé, concurrency stricte OK). Coût négligeable sur les chemins save/metadata.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - Authentification (passerelle SDK, consommée par l'App)

    func isSignedIn() async -> Bool { await client.auth.isSignedIn() }
    func signIn() async { await client.auth.signIn() }
    func handleRedirect(_ url: URL) async throws -> Bool { try await client.auth.handleRedirect(url) }
    func signOut() async { await client.auth.signOut() }

    /// Liste les fichiers `.kdbx` non supprimés du Drive de l'utilisateur.
    func listKdbxFiles() async throws -> [DriveFile] {
        let params = ListFiles.Params(
            query: "name contains '.kdbx' and trashed = false",
            spaces: [.drive]
        )
        do {
            let list = try await client.listFiles(params)
            return list.files.map { DriveFile(id: $0.id, name: $0.name) }
        } catch let error as ListFiles.Error {
            // Cohérence avec metadata/download : on ne laisse jamais remonter le corps de
            // réponse Drive brut (noms/métadonnées) — traduction en `StorageError`.
            throw Self.mapResponseError(notAuthorized: error.isNotAuthorized, statusCode: error.statusCode, error)
        } catch {
            throw Self.mapTransport(error)
        }
    }

    // MARK: - Traduction d'erreurs SDK → StorageError

    private static func mapResponseError(notAuthorized: Bool, statusCode: Int?, _ error: Error) -> StorageError {
        if notAuthorized { return .accessDenied }
        switch statusCode {
        case 404: return .notFound
        case .some(let code): return .network("HTTP \(code)")
        case nil: return .network(error.localizedDescription)
        }
    }

    private static func mapTransport(_ error: Error) -> StorageError {
        if error is URLError { return .network(error.localizedDescription) }
        return .unknown(error.localizedDescription)
    }
}

// Petits accès uniformes aux cas d'erreur du SDK (mêmes formes pour GetFile/GetFileData).
extension GetFile.Error {
    fileprivate var isNotAuthorized: Bool { if case .notAuthorized = self { return true } else { return false } }
    fileprivate var statusCode: Int? { if case let .response(code, _) = self { return code } else { return nil } }
}

extension GetFileData.Error {
    fileprivate var isNotAuthorized: Bool { if case .notAuthorized = self { return true } else { return false } }
    fileprivate var statusCode: Int? { if case let .response(code, _) = self { return code } else { return nil } }
}

extension ListFiles.Error {
    fileprivate var isNotAuthorized: Bool { if case .notAuthorized = self { return true } else { return false } }
    fileprivate var statusCode: Int? { if case let .response(code, _) = self { return code } else { return nil } }
}

extension UpdateFileData.Error {
    fileprivate var isNotAuthorized: Bool { if case .notAuthorized = self { return true } else { return false } }
    fileprivate var statusCode: Int? { if case let .response(code, _) = self { return code } else { return nil } }
}
