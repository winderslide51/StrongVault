import Foundation
import XCTest

@testable import StrongCloneCore

/// Faux `MasterKeyStore` en mémoire pour tester le service sans Keychain/biométrie (CI offline).
/// `failure` simule une erreur device (ex. annulation FaceID) sur la récupération.
private actor FakeMasterKeyStore: MasterKeyStore {
    struct BiometricFailure: Error {}

    private var storage: [String: Data] = [:]
    private var failure: Bool

    init(failing: Bool = false, preload: [String: Data] = [:]) {
        failure = failing
        storage = preload
    }

    func storeSecret(_ secret: Data, forDatabase id: String) async throws {
        storage[id] = secret
    }

    func retrieveSecret(forDatabase id: String, reason: String) async throws -> Data? {
        if failure { throw BiometricFailure() }
        return storage[id]
    }

    func removeSecret(forDatabase id: String) async throws {
        storage[id] = nil
    }

    func contains(_ id: String) -> Bool { storage[id] != nil }
}

final class BiometricUnlockServiceTests: XCTestCase {
    private func makeKey(_ byte: UInt8 = 0xAB) -> Data { Data(repeating: byte, count: 32) }

    func testEnrollThenRetrieveRebuildsRawKeyCredential() async throws {
        let store = FakeMasterKeyStore()
        let service = BiometricUnlockService(store: store)
        let key = makeKey()

        try await service.enroll(databaseID: "db-1", compositeKey: key)
        let credential = try await service.unlockCredential(databaseID: "db-1", reason: "Test")

        XCTAssertEqual(credential?.rawKeyData, key)
        XCTAssertNil(credential?.password)
    }

    func testRetrieveReturnsNilWhenNotEnrolled() async throws {
        let service = BiometricUnlockService(store: FakeMasterKeyStore())
        let credential = try await service.unlockCredential(databaseID: "absent", reason: "Test")
        XCTAssertNil(credential, "Non enrôlé → nil → l'App bascule sur la saisie du mot de passe")
    }

    func testEnrollRejectsNon32ByteKey() async {
        let service = BiometricUnlockService(store: FakeMasterKeyStore())
        do {
            try await service.enroll(databaseID: "db-1", compositeKey: Data(repeating: 1, count: 16))
            XCTFail("Une clé de mauvaise taille doit être refusée")
        } catch {
            XCTAssertEqual(error as? BiometricUnlockError, .invalidStoredKey)
        }
    }

    func testRetrieveRejectsTamperedStoredKey() async {
        // Store préchargé avec une clé de taille invalide (item Keychain altéré).
        let store = FakeMasterKeyStore(preload: ["db-1": Data(repeating: 9, count: 10)])
        let service = BiometricUnlockService(store: store)
        do {
            _ = try await service.unlockCredential(databaseID: "db-1", reason: "Test")
            XCTFail("Une clé stockée de mauvaise taille doit être refusée")
        } catch {
            XCTAssertEqual(error as? BiometricUnlockError, .invalidStoredKey)
        }
    }

    func testBiometricFailurePropagates() async {
        let store = FakeMasterKeyStore(failing: true, preload: ["db-1": makeKey()])
        let service = BiometricUnlockService(store: store)
        do {
            _ = try await service.unlockCredential(databaseID: "db-1", reason: "Test")
            XCTFail("L'échec biométrique doit se propager")
        } catch is FakeMasterKeyStore.BiometricFailure {
            // Attendu : le service ne masque pas l'erreur device.
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    func testDisableRemovesSecret() async throws {
        let store = FakeMasterKeyStore()
        let service = BiometricUnlockService(store: store)
        try await service.enroll(databaseID: "db-1", compositeKey: makeKey())
        try await service.disable(databaseID: "db-1")

        let present = await store.contains("db-1")
        XCTAssertFalse(present)
    }

    /// Purge mémoire au verrouillage : `AutoLockPolicy` décide, le secret déchiffré en mémoire
    /// est libéré. On modélise ici l'invariant testable côté Core (la couche App applique le même
    /// patron sur le `DatabaseDocument` ouvert).
    func testAutoLockPolicyDrivesInMemoryWipe() {
        var revealedSecret: Data? = Data(repeating: 0x01, count: 32)
        let policy = AutoLockPolicy(timeout: 60, lockOnBackground: true)
        let start = Date(timeIntervalSince1970: 0)

        // Passage en arrière-plan → verrouillage → purge.
        if policy.shouldLock(lastActivity: start, now: start, didEnterBackground: true) {
            revealedSecret = nil
        }
        XCTAssertNil(revealedSecret)
    }
}
