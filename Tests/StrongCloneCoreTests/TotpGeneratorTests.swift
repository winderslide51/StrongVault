import Foundation
import XCTest

@testable import StrongCloneCore

/// Known-Answer Tests TOTP (kdbx-read §2.5 / §4.3) : vecteurs RFC 6238 Annexe B + décodage
/// Base32 RFC 4648, plus le parsing des deux conventions TOTP KeePass.
final class TotpGeneratorTests: XCTestCase {
    // MARK: - Base32 (RFC 4648 §10)

    /// Encode des octets en Base32 (scaffolding de test uniquement) pour dériver les seeds ASCII
    /// des vecteurs RFC 6238 vers la forme Base32 attendue par `TotpConfig`.
    private func base32Encode(_ bytes: [UInt8]) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var output = ""
        var accumulator = 0
        var bits = 0
        for byte in bytes {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(accumulator >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            output.append(alphabet[(accumulator << (5 - bits)) & 0x1F])
        }
        return output
    }

    func testBase32DecodeRFC4648Vectors() {
        let cases: [(String, String)] = [
            ("", ""),
            ("MY======", "f"),
            ("MZXQ====", "fo"),
            ("MZXW6===", "foo"),
            ("MZXW6YQ=", "foob"),
            ("MZXW6YTB", "fooba"),
            ("MZXW6YTBOI======", "foobar")
        ]
        for (encoded, expected) in cases {
            let decoded = TotpGenerator.base32Decode(encoded)
            XCTAssertEqual(decoded.map { Data($0) }, Data(expected.utf8), "Base32 \(encoded)")
        }
    }

    func testBase32DecodeIsCaseAndWhitespaceTolerant() {
        let expected = Data("fooba".utf8)
        XCTAssertEqual(TotpGenerator.base32Decode("mzxw6ytb").map { Data($0) }, expected)
        XCTAssertEqual(TotpGenerator.base32Decode("MZXW 6YTB").map { Data($0) }, expected)
        XCTAssertEqual(TotpGenerator.base32Decode("MZ XW 6Y TB\n").map { Data($0) }, expected)
    }

    func testBase32DecodeRejectsInvalidInput() {
        XCTAssertNil(TotpGenerator.base32Decode("0189"))  // 0/1/8/9 hors alphabet Base32
        XCTAssertNil(TotpGenerator.base32Decode("MZXW6YT!"))
    }

    // MARK: - TOTP KAT (RFC 6238 Annexe B), digits = 8

    private func totpCode(seedASCII: String, algorithm: TotpConfig.Algorithm, unixTime: TimeInterval) -> String? {
        let secret = base32Encode(Array(seedASCII.utf8))
        let config = TotpConfig(secret: secret, algorithm: algorithm, digits: 8, period: 30)
        return TotpGenerator.code(for: config, at: Date(timeIntervalSince1970: unixTime))
    }

    func testRFC6238SHA1Vectors() {
        let seed = "12345678901234567890"  // 20 octets ASCII
        let vectors: [(TimeInterval, String)] = [
            (59, "94287082"),
            (1_111_111_109, "07081804"),
            (1_111_111_111, "14050471"),
            (1_234_567_890, "89005924"),
            (2_000_000_000, "69279037"),
            (20_000_000_000, "65353130")
        ]
        for (time, expected) in vectors {
            XCTAssertEqual(totpCode(seedASCII: seed, algorithm: .sha1, unixTime: time), expected, "SHA1 @\(time)")
        }
    }

    func testRFC6238SHA256Vectors() {
        let seed = "12345678901234567890123456789012"  // 32 octets ASCII
        let vectors: [(TimeInterval, String)] = [
            (59, "46119246"),
            (1_111_111_109, "68084774"),
            (1_111_111_111, "67062674"),
            (1_234_567_890, "91819424"),
            (2_000_000_000, "90698825"),
            (20_000_000_000, "77737706")
        ]
        for (time, expected) in vectors {
            XCTAssertEqual(totpCode(seedASCII: seed, algorithm: .sha256, unixTime: time), expected, "SHA256 @\(time)")
        }
    }

    func testRFC6238SHA512Vectors() {
        let seed = "1234567890123456789012345678901234567890123456789012345678901234"  // 64 octets
        let vectors: [(TimeInterval, String)] = [
            (59, "90693936"),
            (1_111_111_109, "25091201"),
            (1_111_111_111, "99943326"),
            (1_234_567_890, "93441116"),
            (2_000_000_000, "38618901"),
            (20_000_000_000, "47863826")
        ]
        for (time, expected) in vectors {
            XCTAssertEqual(totpCode(seedASCII: seed, algorithm: .sha512, unixTime: time), expected, "SHA512 @\(time)")
        }
    }

    /// Vérifie le décodeur Base32 embarqué contre la valeur canonique bien connue du seed SHA1.
    func testCanonicalSHA1SeedBase32() {
        let config = TotpConfig(secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", algorithm: .sha1, digits: 8, period: 30)
        XCTAssertEqual(TotpGenerator.code(for: config, at: Date(timeIntervalSince1970: 59)), "94287082")
    }

    func testInvalidConfigYieldsNilCode() {
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "not base32 !!")))
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "")))
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", digits: 0)))
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", period: 0)))
    }

    /// `digits` provient de la base (attaquant-contrôlé via `TOTP Settings = "30;10"` ou
    /// `otpauth ...&digits=10`). Le modulo `10^digits` déborderait un `UInt32` (trap) au-delà de 8.
    /// On refuse plutôt que de crasher — sinon `TimelineView` redéclencherait le trap chaque seconde.
    func testOutOfRangeDigitsYieldNilNotCrash() {
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", digits: 10)))
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", digits: 100)))
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", digits: -1)))
        XCTAssertNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", digits: 9)))
        // La borne haute supportée (8) reste valide.
        XCTAssertNotNil(TotpGenerator.code(for: TotpConfig(secret: "JBSWY3DPEHPK3PXP", digits: 8)))
    }

    // MARK: - Compte à rebours

    func testRemainingSeconds() {
        // À t=0 → fenêtre pleine (30 s restantes) ; à t=29 → 1 s ; à t=30 → 30 s (nouvelle fenêtre).
        XCTAssertEqual(TotpGenerator.remainingSeconds(period: 30, at: Date(timeIntervalSince1970: 0)), 30)
        XCTAssertEqual(TotpGenerator.remainingSeconds(period: 30, at: Date(timeIntervalSince1970: 29)), 1)
        XCTAssertEqual(TotpGenerator.remainingSeconds(period: 30, at: Date(timeIntervalSince1970: 30)), 30)
        XCTAssertEqual(TotpGenerator.remainingSeconds(period: 30, at: Date(timeIntervalSince1970: 45)), 15)
    }

    // MARK: - Parsing des conventions KeePass

    func testParseOtpauthURI() {
        let config = TotpParser.fromURI(
            "otpauth://totp/ACME:bob?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60&issuer=ACME"
        )
        XCTAssertEqual(config?.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(config?.algorithm, .sha256)
        XCTAssertEqual(config?.digits, 8)
        XCTAssertEqual(config?.period, 60)
    }

    func testParseOtpauthURIDefaults() {
        let config = TotpParser.fromURI("otpauth://totp/Label?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(config?.algorithm, .sha1)
        XCTAssertEqual(config?.digits, 6)
        XCTAssertEqual(config?.period, 30)
    }

    func testParseOtpauthURIRejectsNonOTP() {
        XCTAssertNil(TotpParser.fromURI("https://example.com?secret=JBSWY3DPEHPK3PXP"))
        XCTAssertNil(TotpParser.fromURI("otpauth://hotp/Label?secret=JBSWY3DPEHPK3PXP"))
        XCTAssertNil(TotpParser.fromURI("otpauth://totp/Label"))
    }

    func testParseKeePassXCSeedAndSettings() {
        let config = TotpParser.fromKeePassXC(seed: "JBSWY3DPEHPK3PXP", settings: "60;8")
        XCTAssertEqual(config?.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(config?.period, 60)
        XCTAssertEqual(config?.digits, 8)
    }

    func testParseKeePassXCDefaultsAndInvalid() {
        let defaulted = TotpParser.fromKeePassXC(seed: "JBSWY3DPEHPK3PXP", settings: nil)
        XCTAssertEqual(defaulted?.period, 30)
        XCTAssertEqual(defaulted?.digits, 6)
        // Encodeur Steam ("30;S") : digits non entier → valeur par défaut conservée.
        XCTAssertEqual(TotpParser.fromKeePassXC(seed: "JBSWY3DPEHPK3PXP", settings: "30;S")?.digits, 6)
        XCTAssertNil(TotpParser.fromKeePassXC(seed: "   ", settings: "30;6"))
    }
}
