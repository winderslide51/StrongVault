import Foundation
import GoogleDriveClient
import Security

/// Keychain custom pour les **jetons OAuth Google Drive**. Le keychain par défaut du SDK darrarski
/// stocke les identifiants avec `kSecAttrSynchronizable = true` (donc **synchronisés iCloud**) et
/// sans `kSecAttrAccessible` restrictif — inacceptable pour des jetons d'accès (CLAUDE.md §4.3,
/// réserve §5.5 de `google-drive`).
///
/// Cette implémentation adosse la persistance au framework `Security` avec
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` et **sans** synchronisation iCloud
/// (`kSecAttrSynchronizable = false`). Aucun jeton n'est journalisé ni imprimé.
enum DriveTokenKeychain {
    private static let service = "com.strongclone.googledrive.oauth"
    private static let account = "credentials"

    /// Construit un `GoogleDriveClient.Keychain` injectable dans `Client.live(config:keychain:)`.
    static func make() -> GoogleDriveClient.Keychain {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let decoder = JSONDecoder()

        return GoogleDriveClient.Keychain(
            loadCredentials: {
                guard let data = load(),
                    let credentials = try? decoder.decode(Credentials.self, from: data)
                else { return nil }
                return credentials
            },
            saveCredentials: { credentials in
                guard let data = try? encoder.encode(credentials) else { return }
                store(data)
            },
            deleteCredentials: {
                delete()
            }
        )
    }

    // MARK: - Accès Keychain (generic password, hors iCloud, déverrouillé seulement)

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Jamais synchronisé iCloud : les jetons restent sur cet appareil.
            kSecAttrSynchronizable as String: false
        ]
    }

    private static func load() -> Data? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func store(_ data: Data) {
        // Remplacement idempotent : on supprime l'éventuel item existant avant l'ajout, pour
        // garantir l'accessibilité `...ThisDeviceOnly` sur la nouvelle valeur.
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
