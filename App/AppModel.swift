import Foundation
import StrongCloneCore

/// Provenance des octets d'une base : fichier local (security-scoped bookmark) ou fichier
/// Google Drive (identifié par son `fileId`).
enum DatabaseSource: Sendable {
    case local(bookmark: Data)
    case drive(fileId: String)
}

/// Référence à une base connue de l'app (métadonnées + provenance). En v1 les bases ajoutées
/// vivent le temps de la session (la persistance arrive plus tard).
struct DatabaseRef: Identifiable, Sendable {
    let id: String
    let displayName: String
    let source: DatabaseSource
}

/// État applicatif observable : les bases connues, l'accès Google Drive et les actions de haut
/// niveau. `@MainActor` car pilote l'UI ; le travail CPU (KDF) est délégué hors du thread
/// principal par les vues.
@MainActor
@Observable
final class AppModel {
    private(set) var databases: [DatabaseRef] = []

    /// Client Drive (SDK). Construit avec la config Info.plist ; inactif tant qu'aucun `clientID`
    /// OAuth n'est fourni (« build only »). Sert aussi de `DriveClient` pour `GoogleDriveProvider`.
    private let driveClient = GoogleDriveClientLive(config: GoogleDriveConfig.make())

    /// `true` si un client OAuth Google est configuré (pour afficher/activer la connexion réelle).
    var isDriveConfigured: Bool { GoogleDriveConfig.isConfigured }

    /// Construit le `StorageProvider` adapté à la provenance d'une base.
    func provider(for ref: DatabaseRef) -> any StorageProvider {
        switch ref.source {
        case let .local(bookmark):
            return LocalStorageProvider(identifier: ref.id, displayName: ref.displayName, bookmark: bookmark)
        case let .drive(fileId):
            return GoogleDriveProvider(client: driveClient, fileId: fileId)
        }
    }

    // MARK: - Ajout de bases

    /// Enregistre une base `.kdbx` locale choisie via le sélecteur de fichiers (bookmark scoped).
    func addLocalDatabase(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(options: [])
        let name = url.deletingPathExtension().lastPathComponent
        appendUnique(DatabaseRef(id: UUID().uuidString, displayName: name, source: .local(bookmark: bookmark)))
    }

    /// Enregistre une base `.kdbx` Google Drive (identifiée par son `fileId`).
    func addDriveDatabase(fileId: String, displayName: String) {
        let name = (displayName as NSString).deletingPathExtension
        appendUnique(DatabaseRef(id: fileId, displayName: name, source: .drive(fileId: fileId)))
    }

    private func appendUnique(_ ref: DatabaseRef) {
        if !databases.contains(where: { $0.id == ref.id || $0.displayName == ref.displayName }) {
            databases.append(ref)
        }
    }

    // MARK: - Google Drive (passerelle vers le SDK)

    func isDriveSignedIn() async -> Bool { await driveClient.isSignedIn() }
    func driveSignIn() async { await driveClient.signIn() }
    func handleDriveRedirect(_ url: URL) async { _ = try? await driveClient.handleRedirect(url) }
    func driveSignOut() async { await driveClient.signOut() }
    func listDriveKdbxFiles() async throws -> [DriveFile] { try await driveClient.listKdbxFiles() }
}
