import XCTest
@testable import StrongCloneCore

final class InMemoryStorageProviderTests: XCTestCase {
    func testLoadReturnsStoredData() async throws {
        let provider = InMemoryStorageProvider(data: Data("hello".utf8))
        let data = try await provider.load()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
    }

    func testSaveThenLoadRoundTrip() async throws {
        let provider = InMemoryStorageProvider()
        let meta = try await provider.save(Data("v1".utf8), expectedRemote: nil)
        let loaded = try await provider.load()
        XCTAssertEqual(String(decoding: loaded, as: UTF8.self), "v1")
        XCTAssertEqual(meta.sizeBytes, 2)
    }

    func testConflictWhenExpectedRemoteIsStale() async throws {
        let provider = InMemoryStorageProvider()
        let firstMeta = try await provider.metadata()          // révision 0
        _ = try await provider.save(Data("v1".utf8), expectedRemote: firstMeta)  // -> révision 1

        // On tente d'écrire en s'appuyant sur l'ancienne métadonnée -> conflit attendu.
        do {
            _ = try await provider.save(Data("v2".utf8), expectedRemote: firstMeta)
            XCTFail("Un conflit aurait dû être levé")
        } catch let StorageError.conflict(remote) {
            XCTAssertEqual(remote.sizeBytes, 2)
        }
    }
}

final class AutoLockPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testLocksAfterTimeout() {
        let policy = AutoLockPolicy(timeout: 60, lockOnBackground: false)
        XCTAssertTrue(policy.shouldLock(lastActivity: t0, now: t0.addingTimeInterval(60), didEnterBackground: false))
        XCTAssertFalse(policy.shouldLock(lastActivity: t0, now: t0.addingTimeInterval(59), didEnterBackground: false))
    }

    func testLocksOnBackground() {
        let policy = AutoLockPolicy(timeout: nil, lockOnBackground: true)
        XCTAssertTrue(policy.shouldLock(lastActivity: t0, now: t0, didEnterBackground: true))
    }

    func testNeverLocksWhenDisabled() {
        let policy = AutoLockPolicy(timeout: nil, lockOnBackground: false)
        XCTAssertFalse(policy.shouldLock(lastActivity: t0, now: t0.addingTimeInterval(10_000), didEnterBackground: true))
    }
}
