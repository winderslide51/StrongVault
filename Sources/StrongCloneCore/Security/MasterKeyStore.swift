import Foundation

/// Stockage de la clé/mot de passe maître protégé par biométrie.
///
/// L'implémentation concrète vit dans la couche App (Keychain + `SecAccessControl` avec
/// `.biometryCurrentSet`, récupération via `LAContext`) car elle dépend du device.
/// Le Core ne connaît que ce contrat, ce qui le garde testable et sans dépendance
/// `Security`/`LocalAuthentication`. Voir le change OpenSpec `faceid-unlock`.
///
/// Règles (CLAUDE.md §4) : jamais de secret en clair hors Keychain, invalidation si la
/// biométrie change, pas de fallback code trivial.
public protocol MasterKeyStore: Sendable {
    /// Enregistre le secret maître pour une base donnée, protégé par biométrie.
    func storeSecret(_ secret: Data, forDatabase id: String) async throws

    /// Récupère le secret après authentification biométrique réussie. `nil` si absent.
    func retrieveSecret(forDatabase id: String, reason: String) async throws -> Data?

    /// Supprime le secret (ex: désactivation FaceID, invalidation biométrique).
    func removeSecret(forDatabase id: String) async throws
}
