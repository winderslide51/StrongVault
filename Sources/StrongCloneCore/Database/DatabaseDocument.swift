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

extension DatabaseDocument {
    /// Ouvre des octets `.kdbx` avec les identifiants fournis et mappe le contenu vers le
    /// modèle domaine. Ne réimplémente aucune crypto : délègue à `KDBXReader.parse` (CLAUDE.md §6).
    public static func open(data: Data, credentials: DatabaseCredential) throws -> DatabaseDocument {
        let unlock = try makeUnlockData(credentials)
        let content: KDBXContent
        do {
            // `parse` a un typed throw `throws(KDBXReader.Error)` : `error` est déjà typé.
            content = try KDBXReader.parse(data, unlockData: unlock)
        } catch {
            throw mapReaderError(error)
        }
        let root = mapGroup(content.database.root.group)
        return DatabaseDocument(name: content.database.meta.databaseName, root: root)
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

    /// Champs standard KeePass, mappés vers les propriétés dédiées de `Entry`.
    private static let standardKeys: Set<String> = ["Title", "UserName", "Password", "URL", "Notes"]

    private static func mapGroup(_ group: KDBX.Group) -> Group {
        Group(
            id: group.uuid,
            name: group.name ?? "",
            iconId: Int(group.iconID),
            entries: group.entries.map(mapEntry),
            subgroups: group.groups.map(mapGroup)
        )
    }

    private static func mapEntry(_ entry: KDBX.Entry) -> Entry {
        func string(_ key: String) -> String {
            entry.strings.first { $0.key == key }?.value.revealedString ?? ""
        }
        let password = entry.strings.first { $0.key == "Password" }?.value
        return Entry(
            id: entry.uuid,
            title: string("Title"),
            username: string("UserName"),
            password: password.map { ProtectedSecret($0.revealedString) } ?? "",
            url: string("URL"),
            notes: string("Notes"),
            iconId: Int(entry.iconID),
            // TOTP, champs custom et pièces jointes : mappés dans le change de suivi (tranche
            // minimale = champs standard + révéler/copier le mot de passe).
            customFields: [],
            totp: nil,
            attachments: [],
            created: entry.times?.creationTime ?? Date(timeIntervalSince1970: 0),
            modified: entry.times?.lastModificationTime ?? Date(timeIntervalSince1970: 0)
        )
    }
}
