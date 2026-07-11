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

    public var secret: String  // secret Base32
    public var algorithm: Algorithm
    public var digits: Int
    public var period: Int  // secondes

    public init(secret: String, algorithm: Algorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
}

/// Secret révélé **à la demande** (CLAUDE.md §4 : pas de secret en clair persistant dans le
/// modèle). Le mot de passe n'est jamais stocké comme `String` : on garde les octets UTF-8 et
/// on ne matérialise le texte que sur appel explicite `reveal()` / `withRevealed`. Le type
/// refuse de se décrire en clair (`description` masquée) pour éviter toute fuite via logs/print.
///
/// Note honnête : ceci discipline l'API et l'affichage ; le zéroïsage mémoire fort vit dans
/// KDBXKit (`SecureBytes`). Le modèle domaine est un instantané déchiffré en lecture seule,
/// purgé au verrouillage par la couche App (change `faceid-unlock`).
public struct ProtectedSecret: Sendable, Equatable, ExpressibleByStringLiteral {
    private let bytes: [UInt8]

    public init(_ string: String) {
        bytes = Array(string.utf8)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// Reconstruit un secret depuis des octets UTF-8 (mapping depuis KDBXKit).
    public init(utf8Bytes: [UInt8]) {
        bytes = utf8Bytes
    }

    public var isEmpty: Bool { bytes.isEmpty }

    /// Matérialise le texte en clair. À n'appeler qu'au moment de l'affichage/copie explicite.
    /// Les octets proviennent toujours d'un `String` UTF-8 valide (construction) → jamais nil.
    public func reveal() -> String {
        String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// Révélation à portée limitée : le clair ne vit que le temps de `body`.
    public func withRevealed<R>(_ body: (String) throws -> R) rethrows -> R {
        try body(reveal())
    }
}

extension ProtectedSecret: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { bytes.isEmpty ? "" : "••••••" }
    public var debugDescription: String { "ProtectedSecret(\(description))" }
}

/// Entrée KeePass (un « compte »).
public struct Entry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var username: String
    /// Mot de passe protégé, révélé à la demande (jamais `String` en clair, cf. `ProtectedSecret`).
    public var password: ProtectedSecret
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
        password: ProtectedSecret = "",
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
