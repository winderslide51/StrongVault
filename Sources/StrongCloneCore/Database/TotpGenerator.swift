import CryptoKit
import Foundation

/// Génération de mots de passe à usage unique **HOTP/TOTP** (RFC 4226 / RFC 6238) à partir
/// d'une `TotpConfig`, plus le décodage **Base32** (RFC 4648) du secret.
///
/// Ce n'est pas de la « crypto maison » (CLAUDE.md §4.1, qui vise le format `.kdbx`) : le HMAC
/// est délégué à **CryptoKit** (`HMAC`), primitive système standard. Le secret Base32 n'est
/// jamais journalisé/imprimé.
public enum TotpGenerator {
    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Décode une chaîne **Base32** (RFC 4648). Tolérant au padding `=`, aux espaces et à la
    /// casse (souvent copiée depuis un QR code ou saisie à la main). Renvoie `nil` dès qu'un
    /// caractère hors alphabet Base32 apparaît.
    public static func base32Decode(_ input: String) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var output: [UInt8] = []
        for character in input.uppercased() {
            if character == "=" || character.isWhitespace {
                continue
            }
            guard let symbol = base32Alphabet.firstIndex(of: character) else {
                return nil
            }
            accumulator = (accumulator << 5) | symbol
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((accumulator >> bits) & 0xFF))
                accumulator &= (1 << bits) - 1
            }
        }
        return output
    }

    /// Bornes acceptées pour `digits`. Le maximum (8) couvre tous les vecteurs RFC 4226/6238 ;
    /// au-delà, le modulo `10^digits` déborderait un `UInt32` (trap) — or `digits` provient de la
    /// base (attaquant : `TOTP Settings = "30;10"` ou `otpauth ...&digits=10`). On refuse plutôt
    /// que de crasher, ce qui protège aussi le `TimelineView` qui rappelle ce code chaque seconde.
    private static let supportedDigits = 1...8

    /// Code TOTP courant pour `config` à l'instant `date`. Renvoie `nil` si la configuration
    /// est invalide (secret Base32 illisible ou vide, `period` non positif, `digits` hors 1...8).
    public static func code(for config: TotpConfig, at date: Date = Date()) -> String? {
        guard supportedDigits.contains(config.digits), config.period > 0 else { return nil }
        guard let secret = base32Decode(config.secret), !secret.isEmpty else { return nil }
        let seconds = date.timeIntervalSince1970
        guard seconds >= 0 else { return nil }
        let counter = UInt64(seconds.rounded(.down)) / UInt64(config.period)
        return hotp(secret: secret, counter: counter, algorithm: config.algorithm, digits: config.digits)
    }

    /// Secondes restant avant le basculement vers la fenêtre TOTP suivante (compte à rebours UI).
    public static func remainingSeconds(period: Int, at date: Date = Date()) -> Int {
        guard period > 0 else { return 0 }
        let seconds = Int(date.timeIntervalSince1970.rounded(.down))
        return period - (seconds % period)
    }

    // MARK: - Cœur HOTP (RFC 4226)

    private static func hotp(
        secret: [UInt8],
        counter: UInt64,
        algorithm: TotpConfig.Algorithm,
        digits: Int
    ) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Array($0) }
        let mac = authenticationCode(algorithm, key: secret, message: message)
        // Troncature dynamique (RFC 4226 §5.3).
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary =
            (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulo: UInt32 = 1
        for _ in 0..<digits {
            modulo *= 10
        }
        return String(format: "%0\(digits)u", binary % modulo)
    }

    private static func authenticationCode(
        _ algorithm: TotpConfig.Algorithm,
        key: [UInt8],
        message: [UInt8]
    ) -> [UInt8] {
        let symmetricKey = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            return Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        case .sha256:
            return Array(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case .sha512:
            return Array(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        }
    }
}
