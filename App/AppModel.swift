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

    /// Évaluateur biométrique (disponibilité + libellé) pour piloter l'affichage FaceID.
    let biometricEvaluator: BiometricEvaluator = SystemBiometricEvaluator()

    private let biometricService = BiometricUnlockService(store: KeychainMasterKeyStore())
    private let enabledIDsKey = "biometricEnabledDatabaseIDs"

    /// Ids des bases pour lesquelles FaceID est activé. Info **non secrète** (le secret est en
    /// Keychain) : persistée en `UserDefaults` pour afficher le bouton sans prompt biométrique.
    private(set) var biometricEnabledIDs: Set<String>

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: enabledIDsKey) ?? []
        biometricEnabledIDs = Set(stored)
    }

    func isBiometricEnabled(_ databaseID: String) -> Bool {
        biometricEnabledIDs.contains(databaseID)
    }

    /// Active FaceID pour une base : mémorise la clé composite 32 o derrière la biométrie.
    func enableBiometric(databaseID: String, compositeKey: Data) async throws {
        try await biometricService.enroll(databaseID: databaseID, compositeKey: compositeKey)
        biometricEnabledIDs.insert(databaseID)
        persistEnabledIDs()
    }

    /// Désactive FaceID pour une base (suppression du secret Keychain).
    func disableBiometric(databaseID: String) async throws {
        try await biometricService.disable(databaseID: databaseID)
        biometricEnabledIDs.remove(databaseID)
        persistEnabledIDs()
    }

    /// Récupère les identifiants via biométrie (`nil` si non enrôlé → repli saisie).
    func biometricCredential(databaseID: String, reason: String) async throws -> DatabaseCredential? {
        try await biometricService.unlockCredential(databaseID: databaseID, reason: reason)
    }

    private func persistEnabledIDs() {
        UserDefaults.standard.set(Array(biometricEnabledIDs), forKey: enabledIDsKey)
    }

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
