import Foundation
import LocalAuthentication
import Security
import StrongCloneCore

/// Implémentation device de `MasterKeyStore` : stocke la clé composite dans le **Keychain**,
/// protégée par la biométrie via `SecAccessControlCreateWithFlags(..., .biometryCurrentSet, ...)`.
///
/// Garanties (CLAUDE.md §4) :
/// - `.biometryCurrentSet` → l'item est **invalidé automatiquement** si l'ensemble biométrique
///   enregistré change (nouveau visage/empreinte). Pas de fallback code PIN.
/// - `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` → nécessite un code d'appareil, non
///   synchronisé iCloud, ne quitte jamais l'appareil.
/// - Le secret n'existe en clair que le temps du transfert vers/depuis le Keychain.
struct KeychainMasterKeyStore: MasterKeyStore {
    /// Service Keychain (namespacing des items de l'app).
    let service: String

    init(service: String = "dev.strongclone.masterkey") {
        self.service = service
    }

    enum KeychainError: Error, Equatable {
        case accessControlCreationFailed
        case userCancelled
        case unhandled(OSStatus)
    }

    func storeSecret(_ secret: Data, forDatabase id: String) async throws {
        // Remplacement : on retire un éventuel item existant (SecItemAdd échoue sur doublon).
        try? await removeSecret(forDatabase: id)

        var accessError: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                &accessError
            )
        else {
            throw KeychainError.accessControlCreationFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: secret,
            kSecAttrAccessControl as String: access
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func retrieveSecret(forDatabase id: String, reason: String) async throws -> Data? {
        // Un contexte dédié porte l'invite biométrique ; `SecItemCopyMatching` déclenche le
        // prompt car l'item est protégé par `SecAccessControl`.
        let context = LAContext()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: reason
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled:
            throw KeychainError.userCancelled
        default:
            throw KeychainError.unhandled(status)
        }
    }

    func removeSecret(forDatabase id: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
