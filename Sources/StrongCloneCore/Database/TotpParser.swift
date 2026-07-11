import Foundation

/// Extraction d'une `TotpConfig` depuis les champs d'une entrée KeePass. Deux conventions
/// coexistent dans l'écosystème :
///
/// - une **URI `otpauth://totp/...`** stockée dans un champ nommé `otp` (KeePass 2, plugins) ;
/// - les champs **`TOTP Seed`** (secret Base32) + **`TOTP Settings`** (`"period;digits"`) de
///   KeePassXC.
///
/// Aucun secret n'est journalisé : le seed reste dans la `TotpConfig` (modèle domaine), révélé
/// uniquement au moment de générer le code via `TotpGenerator`.
enum TotpParser {
    /// Noms de champs réservés au TOTP : consommés par le mapping, donc exclus des champs custom.
    static let reservedKeys: Set<String> = ["otp", "TOTP Seed", "TOTP Settings"]

    /// Parse une URI `otpauth://totp/Label?secret=...&algorithm=SHA1&digits=6&period=30`.
    /// Renvoie `nil` si le schéma/host ne correspond pas ou si le secret manque.
    static func fromURI(_ uri: String) -> TotpConfig? {
        guard let components = URLComponents(string: uri),
            components.scheme?.lowercased() == "otpauth",
            components.host?.lowercased() == "totp"
        else {
            return nil
        }
        let items = components.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        guard let secret = query("secret"), !secret.isEmpty else {
            return nil
        }
        let algorithm = query("algorithm").flatMap { TotpConfig.Algorithm(rawValue: $0.uppercased()) } ?? .sha1
        let digits = query("digits").flatMap(Int.init) ?? 6
        let period = query("period").flatMap(Int.init) ?? 30
        return TotpConfig(secret: secret, algorithm: algorithm, digits: digits, period: period)
    }

    /// Parse la convention KeePassXC : `seed` (Base32) + `settings` (`"period;digits"`, ex.
    /// `"30;6"`). Les réglages avancés de KeePassXC (encodeur Steam, etc.) retombent sur les
    /// valeurs par défaut lorsque le champ `digits` n'est pas un entier. Renvoie `nil` si le
    /// seed est vide.
    static func fromKeePassXC(seed: String, settings: String?) -> TotpConfig? {
        let trimmedSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSeed.isEmpty else {
            return nil
        }
        var period = 30
        var digits = 6
        if let settings {
            let parts = settings.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = parts.first, let parsedPeriod = Int(first), parsedPeriod > 0 {
                period = parsedPeriod
            }
            if parts.count >= 2, let parsedDigits = Int(parts[1]), parsedDigits > 0 {
                digits = parsedDigits
            }
        }
        return TotpConfig(secret: trimmedSeed, algorithm: .sha1, digits: digits, period: period)
    }
}
