import Foundation

/// Identifiants d'ouverture d'une base `.kdbx`. C'est **le point de couplage** entre les
/// trois premières capacités produit :
///
/// - Produit par l'écran Unlock (saisie manuelle : `password` + `keyFile` optionnel) ou par
///   le service de déverrouillage biométrique (`rawKeyData`, change `faceid-unlock`).
/// - Consommé par `DatabaseDocument.open(data:credentials:)`.
///
/// `rawKeyData` est la clé composite 32 octets pré-hachée (le « R » de la spec KDBX). Le spike
/// a confirmé que KDBXKit l'expose (`UnlockData.keyDataBytes`) et l'accepte en entrée
/// (`UnlockData(rawKeyData:)`) → c'est ce que FaceID stockera en Keychain (Option A). Elle
/// accorde la même autorité que le mot de passe : à protéger comme tel (jamais loggée).
public struct DatabaseCredential: Sendable {
    public var password: String?
    public var keyFile: Data?
    public var rawKeyData: Data?

    public init(password: String? = nil, keyFile: Data? = nil, rawKeyData: Data? = nil) {
        self.password = password
        self.keyFile = keyFile
        self.rawKeyData = rawKeyData
    }

    /// `true` si aucun facteur d'authentification n'est fourni.
    public var isEmpty: Bool {
        (password?.isEmpty ?? true) && keyFile == nil && rawKeyData == nil
    }
}
