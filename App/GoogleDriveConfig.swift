import Foundation
import GoogleDriveClient

/// Configuration OAuth Google Drive. **Build only** : les valeurs réelles (`clientID`,
/// `redirectURI`) proviennent d'un client OAuth Google Cloud à provisionner, injectées via
/// l'Info.plist (clés non secrètes pour une app iOS/PKCE — jamais commitées). Tant qu'elles
/// sont vides, l'UI Drive s'affiche mais la connexion réelle est inactive.
enum GoogleDriveConfig {
    /// Scope lecture seule : suffisant pour récupérer une base `.kdbx` existante.
    static let scope = "https://www.googleapis.com/auth/drive.readonly"

    static func make() -> Config {
        let info = Bundle.main.infoDictionary
        let clientID = info?["GoogleDriveClientID"] as? String ?? ""
        let redirectURI = info?["GoogleDriveRedirectURI"] as? String ?? ""
        return Config(clientID: clientID, authScope: scope, redirectURI: redirectURI)
    }

    /// `true` si un client OAuth a été configuré (sinon on masque/désactive la connexion réelle).
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary
        let clientID = info?["GoogleDriveClientID"] as? String ?? ""
        return !clientID.isEmpty
    }
}
