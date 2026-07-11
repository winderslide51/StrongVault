import Foundation

/// Erreurs typées du déverrouillage biométrique côté Core (les erreurs device — FaceID
/// indisponible, non enrôlé, annulé — remontent telles quelles depuis le `MasterKeyStore`).
public enum BiometricUnlockError: Error, Equatable, Sendable {
    /// La clé stockée n'a pas la taille attendue (32 o) — item Keychain corrompu/altéré.
    case invalidStoredKey
}

/// Coordonne le déverrouillage biométrique **sans dépendance device** : toute la logique
/// (enrôlement, récupération vs repli mot de passe, désactivation) s'exprime sur le protocole
/// Core `MasterKeyStore`, donc testable avec un faux store (`swift test`, sans simulateur).
///
/// Modèle retenu (spike KDBXKit, Option A) : on stocke la **clé composite 32 o** obtenue après
/// un déverrouillage manuel réussi (`OpenedDatabase.compositeKey`), jamais le mot de passe. À la
/// récupération, on reconstruit un `DatabaseCredential(rawKeyData:)` qui rouvre la base.
///
/// La clé de base (`databaseID`) est l'`identifier` du `StorageProvider` — uniforme local/Drive.
public struct BiometricUnlockService<Store: MasterKeyStore>: Sendable {
    private let store: Store

    public init(store: Store) {
        self.store = store
    }

    /// Active FaceID pour une base : mémorise la clé composite (32 o) derrière la biométrie.
    /// À appeler après un déverrouillage manuel réussi. Le store applique `.biometryCurrentSet`.
    public func enroll(databaseID: String, compositeKey: Data) async throws {
        guard compositeKey.count == 32 else { throw BiometricUnlockError.invalidStoredKey }
        try await store.storeSecret(compositeKey, forDatabase: databaseID)
    }

    /// Tente de récupérer les identifiants via biométrie. Renvoie :
    /// - un `DatabaseCredential(rawKeyData:)` prêt pour `DatabaseDocument.open` si enrôlé,
    /// - `nil` si aucun secret n'est enregistré pour cette base → l'App bascule sur la saisie.
    /// Propage les erreurs biométriques du store (annulation, biométrie indisponible).
    public func unlockCredential(databaseID: String, reason: String) async throws -> DatabaseCredential? {
        guard let key = try await store.retrieveSecret(forDatabase: databaseID, reason: reason) else {
            return nil
        }
        guard key.count == 32 else { throw BiometricUnlockError.invalidStoredKey }
        return DatabaseCredential(rawKeyData: key)
    }

    /// Désactive FaceID pour cette base (suppression du secret).
    public func disable(databaseID: String) async throws {
        try await store.removeSecret(forDatabase: databaseID)
    }
}
