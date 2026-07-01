import Foundation

/// Implémentation en mémoire de `StorageProvider`, utile pour les tests et les previews.
/// Simule la détection de conflit via un compteur de révision reflété dans `modifiedAt`.
public actor InMemoryStorageProvider: StorageProvider {
    private var data: Data
    private var name: String
    private var revision: Int

    public init(data: Data = Data(), name: String = "test.kdbx") {
        self.data = data
        self.name = name
        self.revision = 0
    }

    private func currentMetadata() -> StorageMetadata {
        StorageMetadata(
            identifier: "memory://\(name)",
            displayName: name,
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(revision)),
            sizeBytes: data.count
        )
    }

    public func metadata() async throws -> StorageMetadata {
        currentMetadata()
    }

    public func load() async throws -> Data {
        data
    }

    public func save(_ newData: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata {
        if let expected = expectedRemote, expected.modifiedAt != currentMetadata().modifiedAt {
            throw StorageError.conflict(remote: currentMetadata())
        }
        data = newData
        revision += 1
        return currentMetadata()
    }
}
