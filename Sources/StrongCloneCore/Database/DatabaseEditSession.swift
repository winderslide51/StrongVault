import Foundation
import KDBXKit

/// Erreurs des opérations d'édition, indépendantes de KDBXKit.
public enum DatabaseEditError: Error, Equatable, Sendable {
    /// Aucune entrée ne porte cet UUID dans l'arbre.
    case entryNotFound(UUID)
    /// Aucun groupe ne porte cet UUID dans l'arbre.
    case groupNotFound(UUID)
    /// Le groupe racine ne peut être supprimé.
    case cannotRemoveRoot
    /// La ré-sérialisation `KDBXWriter` n'a pas produit d'octets (cas de buffer inattendu).
    case serializationFailed
}

/// Avertissement de migration exposé à l'UI, sans lui faire connaître KDBXKit. Une base au format
/// legacy (KDBX 3.1) sera ré-écrite en 4.1 à la sauvegarde (le writer n'émet que du 4.x).
public enum LegacyMigrationNotice: Equatable, Sendable {
    /// La base ouverte est en `fromVersion` (ex. « 3.1 ») et sera migrée en 4.1 à l'écriture.
    case willMigrate(fromVersion: String)
}

/// Champ standard non secret d'une entrée KeePass.
public enum StandardField: String, Sendable, CaseIterable {
    case title = "Title"
    case username = "UserName"
    case url = "URL"
    case notes = "Notes"
}

/// Session d'édition **mutant le `KDBXContent` parsé en place** (décision d'architecture centrale,
/// design.md) : on ne reconstruit **jamais** un `KDBXContent` depuis le modèle domaine
/// `DatabaseDocument` (projection lossy → perte d'historique, d'icônes, de champs non modélisés).
///
/// Value type `Sendable` : l'App la détient dans un view model `@MainActor @Observable` et la mute
/// par valeur (sémantique de valeur compatible avec `@Observable`). La purger = remettre la
/// variable à `nil` au verrouillage — les secrets déchiffrés (contenu + `UnlockData`) disparaissent
/// avec elle.
///
/// Sécurité : les secrets (mot de passe, champ custom protégé) sont ré-encodés **chiffrés au repos**
/// via `KDBX.ProtectedString.Value.unprotected`, jamais `.protectedInMemory` (clair sur disque).
public struct DatabaseEditSession: Sendable {
    /// Le contenu KDBXKit conservé et muté en place. `internal` (hors API publique) pour
    /// l'inspection et l'injection de données brutes par les tests (`@testable import`).
    var content: KDBXContent

    /// Clé composite obtenue à l'ouverture ; ré-utilisée pour re-chiffrer à la sauvegarde. Secret :
    /// même autorité que le mot de passe, purgée avec la session.
    private let unlockData: UnlockData

    /// Horloge injectable (tests déterministes). `@Sendable` pour rester `Sendable`.
    private let now: @Sendable () -> Date

    init(content: KDBXContent, unlockData: UnlockData, now: @escaping @Sendable () -> Date = { Date() }) {
        self.content = content
        self.unlockData = unlockData
        self.now = now
    }

    /// Ouvre des octets `.kdbx` **pour édition** : conserve l'`UnlockData` et le `KDBXContent`
    /// mutable. Délègue le parsing à `DatabaseDocument.parse` (aucune crypto maison, CLAUDE.md §6).
    public static func open(
        data: Data,
        credentials: DatabaseCredential,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> DatabaseEditSession {
        let (unlock, content) = try DatabaseDocument.parse(data: data, credentials: credentials)
        return DatabaseEditSession(content: content, unlockData: unlock, now: now)
    }

    /// Comme `open`, mais renvoie aussi la clé composite 32 o pour l'enrôlement biométrique
    /// (Option A, change `faceid-unlock`). À n'appeler que lorsqu'on active FaceID : le chemin
    /// d'ouverture normal utilise `open`. La clé accorde la même autorité que le mot de passe.
    public static func openReturningCompositeKey(
        data: Data,
        credentials: DatabaseCredential,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> (session: DatabaseEditSession, compositeKey: Data) {
        let (unlock, content) = try DatabaseDocument.parse(data: data, credentials: credentials)
        let session = DatabaseEditSession(content: content, unlockData: unlock, now: now)
        return (session, unlock.keyDataBytes.toData())
    }

    // MARK: - Projection lecture seule

    /// Projection **lecture seule** vers le modèle domaine, reconstruite depuis le `KDBXContent`
    /// muté (jamais l'inverse). C'est ce que l'UI affiche.
    public var document: DatabaseDocument {
        DatabaseDocument.map(content)
    }

    /// Avertissement de migration à présenter avant écrasement (`nil` si la base est déjà en 4.x).
    public var legacyMigrationNotice: LegacyMigrationNotice? {
        switch content.legacyFormatNotice {
        case let .willMigrate(fromVersion):
            return .willMigrate(fromVersion: fromVersion.description)
        case nil:
            return nil
        }
    }

    // MARK: - Édition de champs

    /// Remplace le mot de passe d'une entrée. La valeur est ré-encodée **chiffrée au repos**
    /// (`.unprotected`). L'état antérieur est snapshoté dans l'historique et
    /// `lastModificationTime` bumpé (via `editEntry`).
    public mutating func setPassword(_ secret: ProtectedSecret, entryID: UUID) throws {
        try editEntry(entryID) { entry in
            secret.withRevealed { plaintext in
                Self.upsertString(key: "Password", value: .unprotected(plaintext), on: &entry)
            }
        }
    }

    /// Édite un champ standard non secret (titre, identifiant, URL, notes) en clair (`.regular`).
    public mutating func setStandardField(_ field: StandardField, value: String, entryID: UUID) throws {
        try editEntry(entryID) { entry in
            Self.upsertString(key: field.rawValue, value: .regular(value), on: &entry)
        }
    }

    /// Ajoute ou remplace un champ custom. `isProtected == true` → `.unprotected` (chiffré au
    /// repos) ; sinon `.regular` (clair). Un champ protégé passe par `ProtectedSecret` : le secret
    /// ne transite pas par un `String` persistant côté API.
    public mutating func setCustomField(
        key: String,
        secret: ProtectedSecret,
        isProtected: Bool,
        entryID: UUID
    ) throws {
        try editEntry(entryID) { entry in
            let value: KDBX.ProtectedString.Value =
                isProtected
                ? secret.withRevealed { .unprotected($0) }
                : secret.withRevealed { .regular($0) }
            Self.upsertString(key: key, value: value, on: &entry)
        }
    }

    /// Supprime un champ custom par clé (no-op si absent, hormis le bump/snapshot systématique).
    public mutating func removeCustomField(key: String, entryID: UUID) throws {
        try editEntry(entryID) { entry in
            entry.strings.removeAll { $0.key == key }
        }
    }

    // MARK: - CRUD entrées

    /// Ajoute une entrée (titre + mot de passe chiffré au repos) dans un groupe. Renvoie l'UUID
    /// de la nouvelle entrée.
    @discardableResult
    public mutating func addEntry(
        title: String,
        password: ProtectedSecret,
        inGroup groupID: UUID
    ) throws -> UUID {
        let timestamp = now()
        let uuid = UUID()
        var entry = KDBX.Entry(
            uuid: uuid,
            times: KDBX.Times(creationTime: timestamp, lastModificationTime: timestamp)
        )
        Self.upsertString(key: "Title", value: .regular(title), on: &entry)
        password.withRevealed { Self.upsertString(key: "Password", value: .unprotected($0), on: &entry) }

        let inserted = Self.mutateGroup(uuid: groupID, in: &content.database.root.group) { parent in
            parent.entries.append(entry)
        }
        guard inserted else { throw DatabaseEditError.groupNotFound(groupID) }
        return uuid
    }

    /// Supprime une entrée par UUID.
    public mutating func removeEntry(_ entryID: UUID) throws {
        let removed = Self.removeEntry(uuid: entryID, in: &content.database.root.group)
        guard removed else { throw DatabaseEditError.entryNotFound(entryID) }
    }

    // MARK: - CRUD groupes

    /// Ajoute un sous-groupe. Renvoie l'UUID du nouveau groupe.
    @discardableResult
    public mutating func addGroup(name: String, inGroup parentID: UUID) throws -> UUID {
        let timestamp = now()
        let uuid = UUID()
        let group = KDBX.Group(
            uuid: uuid,
            name: name,
            times: KDBX.Times(creationTime: timestamp, lastModificationTime: timestamp)
        )
        let inserted = Self.mutateGroup(uuid: parentID, in: &content.database.root.group) { parent in
            parent.groups.append(group)
        }
        guard inserted else { throw DatabaseEditError.groupNotFound(parentID) }
        return uuid
    }

    /// Renomme un groupe et bump son `lastModificationTime`.
    public mutating func renameGroup(_ groupID: UUID, to name: String) throws {
        let timestamp = now()
        let mutated = Self.mutateGroup(uuid: groupID, in: &content.database.root.group) { group in
            group.name = name
            Self.bumpModified(&group.times, now: timestamp)
        }
        guard mutated else { throw DatabaseEditError.groupNotFound(groupID) }
    }

    /// Supprime un groupe (et tout son contenu). Le groupe racine est refusé.
    public mutating func removeGroup(_ groupID: UUID) throws {
        guard content.database.root.group.uuid != groupID else {
            throw DatabaseEditError.cannotRemoveRoot
        }
        let removed = Self.removeGroup(uuid: groupID, in: &content.database.root.group)
        guard removed else { throw DatabaseEditError.groupNotFound(groupID) }
    }

    // MARK: - Sérialisation

    /// Ré-encode le contenu édité en octets `.kdbx` via `KDBXWriter` (buffer mémoire, chemin
    /// testable). `regenerateSalts: true` par défaut (obligation spec KDBX à chaque sauvegarde) ;
    /// `false` seulement pour un round-trip byte-identique de test.
    public func serialize(regenerateSalts: Bool = true) throws -> Data {
        let stream = OutputStream(toMemory: ())
        stream.open()
        let writer = KDBXWriter(to: stream)
        try writer.write(content, unlockData: unlockData, regenerateSalts: regenerateSalts)
        guard let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw DatabaseEditError.serializationFailed  // inatteignable : le buffer mémoire rend toujours Data
        }
        return data
    }

    // MARK: - Helpers de mutation (parcours par UUID, façon TreeMutator KDBXKit — sans importer KDBXCLICore)

    /// Applique `body` à l'entrée ciblée, en lui passant la `Meta` (cap d'historique) et l'instant
    /// courant. Lève `entryNotFound` si l'UUID est absent.
    private mutating func editEntry(
        _ entryID: UUID,
        _ body: (inout KDBX.Entry) -> Void
    ) throws {
        let meta = content.database.meta
        let timestamp = now()
        let found = Self.mutateEntry(uuid: entryID, in: &content.database.root.group) { entry in
            // Snapshot de l'état **antérieur** AVANT la mutation (parité avec `entry set` du CLI
            // KDBXKit : « snapshots the prior state into Entry.history before mutating ») — c'est
            // ce qui rend une édition réversible côté écosystème KeePass.
            Self.snapshotPriorState(&entry, meta: meta)
            body(&entry)
            Self.bumpModified(&entry.times, now: timestamp)
        }
        guard found else { throw DatabaseEditError.entryNotFound(entryID) }
    }

    /// Pousse l'état courant (pré-mutation) de l'entrée dans son historique, borné par
    /// `Meta.historyMaxItems`. Le snapshot hérite des valeurs protégées telles quelles
    /// (`.unprotected`/`.lazyInnerCipher`) : les anciens secrets restent chiffrés au repos.
    private static func snapshotPriorState(_ entry: inout KDBX.Entry, meta: KDBX.Meta) {
        var snapshot = entry
        snapshot.history = []  // les entrées historiques ne portent pas leur propre historique (spec)
        entry.history.append(snapshot)
        trimHistory(&entry.history, against: meta.historyMaxItems)
    }

    private static func trimHistory(_ history: inout [KDBX.Entry], against cap: KDBX.ValueOrUnlimited<UInt32>?) {
        guard case let .value(maxItems) = cap else { return }
        let limit = Int(maxItems)
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }

    private static func bumpModified(_ times: inout KDBX.Times?, now: Date) {
        var value = times ?? KDBX.Times(creationTime: now)
        value.lastModificationTime = now
        times = value
    }

    private static func upsertString(key: String, value: KDBX.ProtectedString.Value, on entry: inout KDBX.Entry) {
        if let index = entry.strings.firstIndex(where: { $0.key == key }) {
            entry.strings[index] = KDBX.ProtectedString(key: key, value: value)
        } else {
            entry.strings.append(KDBX.ProtectedString(key: key, value: value))
        }
    }

    @discardableResult
    private static func mutateEntry(
        uuid: UUID,
        in group: inout KDBX.Group,
        _ body: (inout KDBX.Entry) -> Void
    ) -> Bool {
        for index in group.entries.indices where group.entries[index].uuid == uuid {
            body(&group.entries[index])
            return true
        }
        for index in group.groups.indices where mutateEntry(uuid: uuid, in: &group.groups[index], body) {
            return true
        }
        return false
    }

    @discardableResult
    private static func mutateGroup(
        uuid: UUID,
        in group: inout KDBX.Group,
        _ body: (inout KDBX.Group) -> Void
    ) -> Bool {
        if group.uuid == uuid {
            body(&group)
            return true
        }
        for index in group.groups.indices where mutateGroup(uuid: uuid, in: &group.groups[index], body) {
            return true
        }
        return false
    }

    @discardableResult
    private static func removeEntry(uuid: UUID, in group: inout KDBX.Group) -> Bool {
        if let index = group.entries.firstIndex(where: { $0.uuid == uuid }) {
            group.entries.remove(at: index)
            return true
        }
        for index in group.groups.indices where removeEntry(uuid: uuid, in: &group.groups[index]) {
            return true
        }
        return false
    }

    @discardableResult
    private static func removeGroup(uuid: UUID, in group: inout KDBX.Group) -> Bool {
        if let index = group.groups.firstIndex(where: { $0.uuid == uuid }) {
            group.groups.remove(at: index)
            return true
        }
        for index in group.groups.indices where removeGroup(uuid: uuid, in: &group.groups[index]) {
            return true
        }
        return false
    }
}
