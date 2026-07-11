import Foundation
import KDBXKit

/// Erreurs d'ouverture typées, indépendantes de KDBXKit (l'App n'a pas à connaître la lib).
public enum DatabaseOpenError: Error, Equatable, Sendable {
    /// Mot de passe et/ou key file incorrects.
    case wrongCredentials
    /// Aucun identifiant fourni (ni mot de passe, ni key file, ni clé brute).
    case missingCredentials
    /// Version de format non supportée (ex. KDBX antérieur à 3.1).
    case unsupportedVersion(major: Int, minor: Int)
    /// Intégrité compromise (HMAC/en-tête corrompus) ou fichier illisible.
    case corrupted(String)
    /// Key file structurellement invalide.
    case invalidKeyFile
}

/// Instantané **lecture seule** d'une base `.kdbx` ouverte : l'arbre des groupes/entrées mappé
/// vers le modèle domaine. Les secrets (`Entry.password`) sont des `ProtectedSecret` révélés à
/// la demande. Aucune écriture ici (change `kdbx-write` ultérieur).
public struct DatabaseDocument: Sendable, Equatable {
    /// Nom de la base (métadonnée KDBX), si présent.
    public let name: String?
    /// Groupe racine ; tout le contenu est accessible via `root`.
    public let root: Group

    public init(name: String?, root: Group) {
        self.name = name
        self.root = root
    }
}

/// Base ouverte **avec** sa clé composite 32 octets — utilisé pour l'enrôlement biométrique
/// (change `faceid-unlock`) : la clé est stockée en Keychain derrière FaceID pour rouvrir la
/// base sans re-saisir le mot de passe. `compositeKey` accorde la même autorité que le mot de
/// passe : à protéger comme tel (jamais loggée, jamais persistée hors Keychain).
public struct OpenedDatabase: Sendable {
    public let document: DatabaseDocument
    public let compositeKey: Data

    public init(document: DatabaseDocument, compositeKey: Data) {
        self.document = document
        self.compositeKey = compositeKey
    }
}

extension DatabaseDocument {
    /// Ouvre des octets `.kdbx` avec les identifiants fournis et mappe le contenu vers le
    /// modèle domaine. Ne réimplémente aucune crypto : délègue à `KDBXReader.parse` (CLAUDE.md §6).
    public static func open(data: Data, credentials: DatabaseCredential) throws -> DatabaseDocument {
        let (_, content) = try parse(data: data, credentials: credentials)
        return map(content)
    }

    /// Comme `open`, mais renvoie aussi la clé composite 32 o pour l'enrôlement biométrique.
    /// À n'appeler que lorsqu'on veut activer FaceID (le chemin d'ouverture normal utilise `open`).
    public static func openReturningCompositeKey(
        data: Data,
        credentials: DatabaseCredential
    ) throws -> OpenedDatabase {
        let (unlock, content) = try parse(data: data, credentials: credentials)
        return OpenedDatabase(document: map(content), compositeKey: unlock.keyDataBytes.toData())
    }

    private static func parse(
        data: Data,
        credentials: DatabaseCredential
    ) throws -> (UnlockData, KDBXContent) {
        let unlock = try makeUnlockData(credentials)
        do {
            // `parse` a un typed throw `throws(KDBXReader.Error)` : `error` est déjà typé.
            return (unlock, try KDBXReader.parse(data, unlockData: unlock))
        } catch {
            throw mapReaderError(error)
        }
    }

    /// Mappe le contenu KDBXKit vers le modèle domaine — utilisé par `open` **et**
    /// `openReturningCompositeKey` (le déverrouillage FaceID profite du même mapping enrichi).
    private static func map(_ content: KDBXContent) -> DatabaseDocument {
        // Pool de binaires (KDBX 4.x) : les pièces jointes `.ref(index)` pointent ici. On mappe
        // vers les seuls octets, c'est tout ce dont `Attachment` a besoin.
        let binaryPool = content.innerHeader.binaryContent.map(\.data)
        return DatabaseDocument(
            name: content.database.meta.databaseName,
            root: mapGroup(content.database.root.group, binaryPool: binaryPool)
        )
    }

    // MARK: - Construction des identifiants KDBXKit

    private static func makeUnlockData(_ credentials: DatabaseCredential) throws -> UnlockData {
        // La clé brute (chemin FaceID) prime : elle rouvre sans re-dériver.
        if let rawKeyData = credentials.rawKeyData {
            guard rawKeyData.count == 32 else { throw DatabaseOpenError.invalidKeyFile }
            return UnlockData(rawKeyData: rawKeyData)
        }
        do {
            switch (credentials.password, credentials.keyFile) {
            case let (password?, keyFile?):
                return try UnlockData(masterPassword: password, keyFile: keyFile)
            case let (password?, nil):
                return UnlockData(masterPassword: password)
            case let (nil, keyFile?):
                return try UnlockData(keyFile: keyFile)
            case (nil, nil):
                throw DatabaseOpenError.missingCredentials
            }
        } catch is KeyFileError {
            throw DatabaseOpenError.invalidKeyFile
        }
    }

    private static func mapReaderError(_ error: KDBXReader.Error) -> DatabaseOpenError {
        switch error {
        case .wrongCredentials:
            return .wrongCredentials
        case .unlockDataRequired:
            return .missingCredentials
        case let .unsupportedFormatVersion(major, minor):
            return .unsupportedVersion(major: Int(major), minor: Int(minor))
        case let .corruptedHMAC(reason),
            let .corruptedHeader(reason),
            let .corruptedInnerHeader(reason),
            let .corruptedXML(reason),
            let .kdfParametersOutOfRange(reason):
            return .corrupted(reason)
        case .corruptedHeaderDigest, .invalidFileSignature, .unexpectedEOF:
            return .corrupted("\(error)")
        default:
            // Chiffrement/compression/KDF non supportés, payload trop gros, etc.
            return .corrupted("\(error)")
        }
    }

    // MARK: - Mapping KDBXKit → modèle domaine

    /// Champs standard KeePass, mappés vers les propriétés dédiées de `Entry`. Tout autre champ
    /// (hors champs TOTP réservés) devient un `CustomField`.
    static let standardKeys: Set<String> = ["Title", "UserName", "Password", "URL", "Notes"]

    /// `internal` (pas `private`) pour être exerçable directement par les tests unitaires
    /// (`@testable import`) sur des `KDBX.Group` construits en mémoire — KeePassXC ne sait pas
    /// injecter TOTP/pièces jointes en CLI.
    static func mapGroup(_ group: KDBX.Group, binaryPool: [Data]) -> Group {
        Group(
            id: group.uuid,
            name: group.name ?? "",
            iconId: Int(group.iconID),
            entries: group.entries.map { mapEntry($0, binaryPool: binaryPool) },
            subgroups: group.groups.map { mapGroup($0, binaryPool: binaryPool) }
        )
    }

    static func mapEntry(_ entry: KDBX.Entry, binaryPool: [Data]) -> Entry {
        func string(_ key: String) -> String {
            entry.strings.first { $0.key == key }?.value.revealedString ?? ""
        }
        let password = entry.strings.first { $0.key == "Password" }?.value
        // Limite connue : `revealedString` fait transiter le secret par un `String` Swift non
        // zéroïsable avant re-stockage en octets (`ProtectedSecret`). Le secret est de toute
        // façon déjà déchiffré ; le zéroïsage mémoire fort reste du ressort de KDBXKit.
        return Entry(
            id: entry.uuid,
            title: string("Title"),
            username: string("UserName"),
            password: password.map { ProtectedSecret($0.revealedString) } ?? "",
            url: string("URL"),
            notes: string("Notes"),
            iconId: Int(entry.iconID),
            customFields: mapCustomFields(entry),
            totp: mapTotp(entry),
            attachments: mapAttachments(entry, binaryPool: binaryPool),
            created: entry.times?.creationTime ?? Date(timeIntervalSince1970: 0),
            modified: entry.times?.lastModificationTime ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// Tous les champs hors standards et hors champs TOTP consommés. `isProtected` reflète la
    /// protection KDBX (`Protected="True"` sur disque) : seul le cas `.regular` est en clair.
    private static func mapCustomFields(_ entry: KDBX.Entry) -> [CustomField] {
        entry.strings.compactMap { field -> CustomField? in
            guard !standardKeys.contains(field.key), !TotpParser.reservedKeys.contains(field.key) else {
                return nil
            }
            return CustomField(
                key: field.key,
                value: field.value.revealedString,
                isProtected: isProtectedOnDisk(field.value)
            )
        }
    }

    /// Convention `otpauth://` d'abord (champ `otp`), sinon KeePassXC (`TOTP Seed`/`TOTP Settings`).
    private static func mapTotp(_ entry: KDBX.Entry) -> TotpConfig? {
        func value(_ key: String) -> String? {
            entry.strings.first { $0.key == key }?.value.revealedString
        }
        if let otp = value("otp"), let config = TotpParser.fromURI(otp) {
            return config
        }
        if let seed = value("TOTP Seed") {
            return TotpParser.fromKeePassXC(seed: seed, settings: value("TOTP Settings"))
        }
        return nil
    }

    /// Résout les pièces jointes : `.inline` porte les octets ; `.ref(index)` pointe dans le pool
    /// de binaires dédupliqué du fichier. Une référence hors bornes est ignorée (fichier illisible
    /// sur ce point plutôt que de planter l'ouverture entière).
    private static func mapAttachments(_ entry: KDBX.Entry, binaryPool: [Data]) -> [Attachment] {
        entry.binaries.compactMap { binary -> Attachment? in
            switch binary.value {
            case let .inline(data, _):
                return Attachment(name: binary.key, data: data)
            case let .ref(index):
                let slot = Int(index)
                guard slot >= 0, slot < binaryPool.count else {
                    return nil
                }
                return Attachment(name: binary.key, data: binaryPool[slot])
            }
        }
    }

    /// `true` quand la valeur est chiffrée au repos (`Protected="True"`). Le lecteur KDBXKit émet
    /// `.regular` pour le clair et `.lazyInnerCipher` pour un nœud protégé ; `.unprotected` sert au
    /// ré-encodage protégé côté écriture. Seul `.regular` est donc en clair.
    private static func isProtectedOnDisk(_ value: KDBX.ProtectedString.Value) -> Bool {
        switch value {
        case .regular:
            return false
        case .unprotected, .protectedInMemory, .lazyInnerCipher:
            return true
        }
    }
}
