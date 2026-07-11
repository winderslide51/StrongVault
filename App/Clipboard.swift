import UIKit
import UniformTypeIdentifiers

/// Copie presse-papier avec **auto-effacement** (CLAUDE.md §5) : l'item expire après un délai
/// via l'API native `UIPasteboard`. `localOnly` empêche la propagation du secret vers les autres
/// appareils du compte iCloud (Handoff / Universal Clipboard), hors du contrôle de l'expiration.
///
/// Type partagé : réutilisé par toute copie de l'app (identifiant, mot de passe, code TOTP,
/// champ custom). Aucun secret n'est journalisé.
enum Clipboard {
    static let clearDelay: TimeInterval = 30

    static func copy(_ value: String) {
        let item = [UTType.utf8PlainText.identifier: value]
        let expiry = Date(timeIntervalSinceNow: clearDelay)
        UIPasteboard.general.setItems([item], options: [.expirationDate: expiry, .localOnly: true])
    }
}
