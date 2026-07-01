import Foundation

// Modèles domaine indépendants du format de fichier. Le wrapper KDBXKit (change
// `kdbx-read`) convertira les entités KeePass vers/depuis ces types. Aucun secret n'est
// journalisé : `password` et champs protégés ne doivent jamais être imprimés/loggés.

/// Pièce jointe stockée dans une entrée KeePass.
public struct Attachment: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var data: Data

    public init(id: UUID = UUID(), name: String, data: Data) {
        self.id = id
        self.name = name
        self.data = data
    }
}

/// Champ personnalisé clé/valeur, éventuellement « protégé » (masqué).
public struct CustomField: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var key: String
    public var value: String
    public var isProtected: Bool

    public init(id: UUID = UUID(), key: String, value: String, isProtected: Bool = false) {
        self.id = id
        self.key = key
        self.value = value
        self.isProtected = isProtected
    }
}

/// Configuration TOTP (mot de passe à usage unique basé sur le temps).
public struct TotpConfig: Sendable, Equatable {
    public enum Algorithm: String, Sendable, CaseIterable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    public var secret: String        // secret Base32
    public var algorithm: Algorithm
    public var digits: Int
    public var period: Int           // secondes

    public init(secret: String, algorithm: Algorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
}

/// Entrée KeePass (un « compte »).
public struct Entry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var username: String
    public var password: String
    public var url: String
    public var notes: String
    public var iconId: Int
    public var customFields: [CustomField]
    public var totp: TotpConfig?
    public var attachments: [Attachment]
    public var created: Date
    public var modified: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        username: String = "",
        password: String = "",
        url: String = "",
        notes: String = "",
        iconId: Int = 0,
        customFields: [CustomField] = [],
        totp: TotpConfig? = nil,
        attachments: [Attachment] = [],
        created: Date = Date(),
        modified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.notes = notes
        self.iconId = iconId
        self.customFields = customFields
        self.totp = totp
        self.attachments = attachments
        self.created = created
        self.modified = modified
    }
}

/// Groupe (dossier) KeePass, arborescent.
public struct Group: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var iconId: Int
    public var entries: [Entry]
    public var subgroups: [Group]

    public init(
        id: UUID = UUID(),
        name: String = "",
        iconId: Int = 0,
        entries: [Entry] = [],
        subgroups: [Group] = []
    ) {
        self.id = id
        self.name = name
        self.iconId = iconId
        self.entries = entries
        self.subgroups = subgroups
    }
}

extension Group {
    /// Toutes les entrées du groupe et de ses sous-groupes (parcours en profondeur).
    public var allEntriesRecursive: [Entry] {
        entries + subgroups.flatMap(\.allEntriesRecursive)
    }
}
