import Foundation
import StrongCloneCore

/// View model d'une base **ouverte et éditable** : détient la `DatabaseEditSession` Core (qui
/// mute le `KDBXContent` en place), expose la projection lecture seule pour l'UI, applique les
/// éditions et sauvegarde via le `StorageProvider`.
///
/// `@MainActor @Observable` (CLAUDE.md §5). Aucune logique de format ici : tout passe par la
/// session Core. La sérialisation (KDF coûteux) est déportée hors du thread principal.
///
/// Purge au verrouillage : cet objet est détenu par la vue ; le remettre à `nil` (arrière-plan)
/// détruit la session et donc tous les secrets déchiffrés + la clé composite (aucun résiduel).
/// Regroupe les champs édités d'une entrée transmis en bloc à `applyEntryEdits`. Le mot de passe
/// et les champs protégés restent des secrets (`ProtectedSecret` / `isProtected`).
struct EntryEdits {
    var title: String
    var username: String
    var url: String
    var notes: String
    var password: ProtectedSecret
    var customFields: [CustomField]
    var removedCustomKeys: [String]
}

@MainActor
@Observable
final class DatabaseSessionModel {
    /// Session Core mutée en place. `private` : l'UI ne voit que la projection `document`.
    private var session: DatabaseEditSession
    private let provider: any StorageProvider

    /// Révision distante attendue à la prochaine écriture, **capturée au chargement** puis
    /// rafraîchie après chaque sauvegarde réussie. Sert de `expectedRemote` pour la détection de
    /// conflit Drive (`nil` en local, où elle est ignorée). Change `google-drive-sync`.
    private var expectedRemote: StorageMetadata?

    /// `true` pour une source distante (Drive) : la sauvegarde y **exige** une baseline de
    /// révision (`expectedRemote` avec jeton). Si la capture a échoué au chargement, on refuse
    /// d'uploader à l'aveugle (risque d'écraser une version plus récente sans le savoir) et on
    /// invite à recharger. En local, aucune baseline requise.
    private let requiresRevisionBaseline: Bool

    /// Modifications non sauvegardées en attente.
    private(set) var hasUnsavedChanges = false
    private(set) var isSaving = false
    /// `true` si la dernière sauvegarde a été refusée car la base a changé sur Drive depuis le
    /// chargement (l'UI propose alors de recharger). Aucun octet n'a été écrit.
    var hasConflict = false
    /// Fermeture déclenchée par « Recharger » après conflit : re-télécharge la base en repassant
    /// par l'écran de déverrouillage (fixée par la couche de navigation). Jamais un secret.
    var reloadHandler: (@MainActor () -> Void)?
    /// Message d'erreur non sensible pour l'UI (jamais de secret).
    var errorMessage: String?

    init(
        session: DatabaseEditSession,
        provider: any StorageProvider,
        expectedRemote: StorageMetadata? = nil,
        requiresRevisionBaseline: Bool = false
    ) {
        self.session = session
        self.provider = provider
        self.expectedRemote = expectedRemote
        self.requiresRevisionBaseline = requiresRevisionBaseline
    }

    /// Projection lecture seule courante (reconstruite depuis le `KDBXContent` muté).
    var document: DatabaseDocument { session.document }

    /// Avertissement de migration 3.1→4.1 à présenter avant écrasement (`nil` si déjà en 4.x).
    var migrationNotice: LegacyMigrationNotice? { session.legacyMigrationNotice }

    // MARK: - Édition (délègue à la session Core, marque l'état modifié)

    /// Applique en bloc les champs édités d'une entrée (formulaire d'édition). Les champs
    /// standard sont écrits en clair ; le mot de passe et les champs custom protégés en
    /// `.unprotected` (chiffré au repos) via `ProtectedSecret`.
    func applyEntryEdits(entryID: UUID, _ edits: EntryEdits) {
        perform {
            try session.setStandardField(.title, value: edits.title, entryID: entryID)
            try session.setStandardField(.username, value: edits.username, entryID: entryID)
            try session.setStandardField(.url, value: edits.url, entryID: entryID)
            try session.setStandardField(.notes, value: edits.notes, entryID: entryID)
            try session.setPassword(edits.password, entryID: entryID)
            for key in edits.removedCustomKeys {
                try session.removeCustomField(key: key, entryID: entryID)
            }
            for field in edits.customFields {
                try session.setCustomField(
                    key: field.key,
                    secret: ProtectedSecret(field.value),
                    isProtected: field.isProtected,
                    entryID: entryID
                )
            }
        }
    }

    @discardableResult
    func addEntry(title: String, password: ProtectedSecret, inGroup groupID: UUID) -> UUID? {
        var newID: UUID?
        perform { newID = try session.addEntry(title: title, password: password, inGroup: groupID) }
        return newID
    }

    func removeEntry(_ entryID: UUID) {
        perform { try session.removeEntry(entryID) }
    }

    @discardableResult
    func addGroup(name: String, inGroup parentID: UUID) -> UUID? {
        var newID: UUID?
        perform { newID = try session.addGroup(name: name, inGroup: parentID) }
        return newID
    }

    func renameGroup(_ groupID: UUID, to name: String) {
        perform { try session.renameGroup(groupID, to: name) }
    }

    func removeGroup(_ groupID: UUID) {
        perform { try session.removeGroup(groupID) }
    }

    /// Exécute une mutation, marque l'état modifié, capture toute erreur (message non sensible).
    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            hasUnsavedChanges = true
        } catch {
            errorMessage = "Modification impossible."
        }
    }

    // MARK: - Sauvegarde

    /// Ré-sérialise la base et l'écrit via le provider. La sérialisation (KDF) est déportée hors
    /// du thread principal. À l'issue, `hasUnsavedChanges` repasse à `false`.
    func save() async {
        guard !isSaving else { return }
        // Source distante sans baseline de révision (capture échouée au chargement) : uploader
        // écraserait sans détection une éventuelle version plus récente. On refuse et on invite
        // à recharger — même issue qu'un conflit avéré, aucun octet écrit.
        if requiresRevisionBaseline, expectedRemote?.revisionToken == nil {
            hasConflict = true
            return
        }
        isSaving = true
        errorMessage = nil
        hasConflict = false
        // Copie de valeur `Sendable` pour traverser l'isolation vers la tâche détachée.
        let snapshot = session
        let provider = provider
        let expected = expectedRemote
        do {
            let data = try await Task.detached { try snapshot.serialize() }.value
            // `expectedRemote` porte la révision distante attendue : le provider Drive refuse
            // d'écraser si elle a changé (conflit). Ignoré en local.
            let updated = try await provider.save(data, expectedRemote: expected)
            expectedRemote = updated  // nouvelle révision de référence pour la prochaine écriture
            hasUnsavedChanges = false
        } catch let error as StorageError {
            // La base a changé sur Drive : aucun octet écrit, on invite à recharger (pas d'écrasement).
            if case .conflict = error {
                hasConflict = true
            } else {
                errorMessage = "Sauvegarde impossible."
            }
        } catch {
            errorMessage = "Sauvegarde impossible."
        }
        isSaving = false
    }
}
