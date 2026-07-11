import Foundation
import StrongCloneCore

/// Référence à une base connue de l'app (métadonnées + bookmark d'accès). En v1 (tranche
/// minimale) les bases ajoutées vivent le temps de la session ; la persistance des bookmarks
/// et l'ajout depuis Google Drive arrivent avec leurs changes respectifs.
struct DatabaseRef: Identifiable, Sendable {
    let id: String
    let displayName: String
    let bookmark: Data

    var provider: LocalStorageProvider {
        LocalStorageProvider(identifier: id, displayName: displayName, bookmark: bookmark)
    }
}

/// État applicatif observable : la liste des bases connues et les actions de haut niveau.
/// `@MainActor` car pilote directement l'UI ; le travail CPU (KDF d'ouverture) est délégué
/// hors du thread principal par les vues.
@MainActor
@Observable
final class AppModel {
    private(set) var databases: [DatabaseRef] = []

    /// Enregistre une base `.kdbx` choisie via le sélecteur de fichiers, sous forme de
    /// security-scoped bookmark. L'URL fournie par `fileImporter` est déjà scoped.
    func addLocalDatabase(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(options: [])
        let ref = DatabaseRef(
            id: UUID().uuidString,
            displayName: url.deletingPathExtension().lastPathComponent,
            bookmark: bookmark
        )
        // Évite les doublons visuels si le même fichier est ré-importé dans la session.
        if !databases.contains(where: { $0.displayName == ref.displayName }) {
            databases.append(ref)
        }
    }
}
