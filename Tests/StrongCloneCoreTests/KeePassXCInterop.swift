import Foundation

/// Pilote headless de `keepassxc-cli` — **source de vérité interop** (CLAUDE.md §4.2).
///
/// Le round-trip interne (`KDBXReader` ↔ `KDBXWriter`) prouve la self-consistance, pas
/// l'interop : trois bugs réels (déclaration `<?xml version>`, séparateur de tags,
/// normalisation key-file) n'ont été attrapés **que** par KeePassXC réel. Les tests d'écriture
/// rouvrent donc les octets produits avec le vrai binaire.
///
/// Gaté sur la présence de `keepassxc-cli` (`isAvailable`) : la CI l'installe via Homebrew ;
/// une machine sans le binaire fait no-op plutôt que d'échouer.
enum KeePassXCInterop {
    /// Emplacements usuels du binaire (Homebrew arm64/x86, app bundle, PATH système).
    private static let candidatePaths = [
        "/opt/homebrew/bin/keepassxc-cli",
        "/usr/local/bin/keepassxc-cli",
        "/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli",
        "/usr/bin/keepassxc-cli"
    ]

    /// Chemin résolu du binaire `keepassxc-cli`, ou `nil` s'il est introuvable.
    static var executablePath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `true` si l'interop peut être exercée sur cette machine.
    static var isAvailable: Bool { executablePath != nil }

    struct CommandFailure: Error, CustomStringConvertible {
        let status: Int32
        let output: String
        var description: String {
            "keepassxc-cli a échoué (status \(status)) : \(output)"
        }
    }

    /// Exécute `keepassxc-cli show -q -s <db> <entry>` en fournissant le mot de passe maître
    /// via stdin, et renvoie la sortie standard (les 5 champs standard + tags).
    ///
    /// Le mot de passe ne transite jamais par `argv` (visible dans `ps`) : uniquement stdin.
    static func showEntry(
        databaseURL: URL,
        password: String,
        entryPath: String
    ) throws -> String {
        try run(
            arguments: ["show", "-q", "-s", databaseURL.path, entryPath],
            password: password
        )
    }

    /// Exécute `keepassxc-cli ls -q -R <db>` (listing récursif) avec mot de passe via stdin.
    static func listRecursive(databaseURL: URL, password: String) throws -> String {
        try run(arguments: ["ls", "-q", "-R", databaseURL.path], password: password)
    }

    private static func run(arguments: [String], password: String) throws -> String {
        guard let executablePath else {
            throw CommandFailure(status: -1, output: "keepassxc-cli introuvable")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // Le prompt de mot de passe attend une ligne sur stdin.
        stdinPipe.fileHandleForWriting.write(Data((password + "\n").utf8))
        try stdinPipe.fileHandleForWriting.close()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(bytes: outData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let stderr = String(bytes: errData, encoding: .utf8) ?? ""
            throw CommandFailure(status: process.terminationStatus, output: stdout + stderr)
        }
        return stdout
    }
}
