import StrongCloneCore
import SwiftUI
import UniformTypeIdentifiers

/// Écran de déverrouillage : mot de passe + key file optionnel, ou **FaceID** si activé pour la
/// base. À l'ouverture réussie, remonte le `DatabaseDocument` au parent (navigation vers Browse).
struct UnlockView: View {
    let database: DatabaseRef
    let appModel: AppModel
    let onUnlocked: (DatabaseDocument) -> Void

    @State private var password = ""
    @State private var keyFileData: Data?
    @State private var keyFileName: String?
    @State private var showingKeyFilePicker = false
    @State private var errorMessage: String?
    @State private var isUnlocking = false
    @State private var enableBiometricAfterUnlock = false

    private var biometricEnabled: Bool { appModel.isBiometricEnabled(database.id) }
    private var biometricAvailable: Bool { appModel.biometricEvaluator.isAvailable }
    private var biometricLabel: String { appModel.biometricEvaluator.label }

    var body: some View {
        Form {
            if biometricEnabled && biometricAvailable {
                Section {
                    Button {
                        unlockWithBiometrics()
                    } label: {
                        Label("Déverrouiller avec \(biometricLabel)", systemImage: "faceid")
                    }
                    .disabled(isUnlocking)
                }
            }

            Section("Mot de passe") {
                SecureField("Mot de passe maître", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { unlock() }
            }

            Section("Key file (optionnel)") {
                if let name = keyFileName {
                    LabeledContent("Fichier", value: name)
                    Button("Retirer le key file", role: .destructive) {
                        keyFileData = nil
                        keyFileName = nil
                    }
                } else {
                    Button("Choisir un key file…") { showingKeyFilePicker = true }
                }
            }

            if biometricAvailable && !biometricEnabled {
                Section {
                    Toggle("Activer \(biometricLabel) pour cette base", isOn: $enableBiometricAfterUnlock)
                } footer: {
                    Text("La clé sera protégée par \(biometricLabel) et invalidée si la biométrie change.")
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    unlock()
                } label: {
                    if isUnlocking {
                        ProgressView()
                    } else {
                        Text("Déverrouiller")
                    }
                }
                .disabled(isUnlocking || (password.isEmpty && keyFileData == nil))
            }
        }
        .navigationTitle(database.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingKeyFilePicker,
            allowedContentTypes: [.data, .item]
        ) { result in
            switch result {
            case let .success(url):
                loadKeyFile(from: url)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func unlock() {
        guard !isUnlocking else { return }
        errorMessage = nil
        isUnlocking = true
        let credential = DatabaseCredential(
            password: password.isEmpty ? nil : password,
            keyFile: keyFileData
        )
        let provider = appModel.provider(for: database)
        let shouldEnroll = enableBiometricAfterUnlock

        Task {
            do {
                let data = try await provider.load()
                // Ouverture (KDF coûteux) hors du thread principal. On ne matérialise la clé
                // composite (autorité = mot de passe maître) que si l'utilisateur active FaceID.
                let document: DatabaseDocument
                if shouldEnroll {
                    let opened = try await Task.detached {
                        try DatabaseDocument.openReturningCompositeKey(data: data, credentials: credential)
                    }.value
                    // Échec d'enrôlement (ex. pas de code d'appareil) : on n'empêche pas l'ouverture.
                    try? await appModel.enableBiometric(databaseID: database.id, compositeKey: opened.compositeKey)
                    document = opened.document
                } else {
                    document = try await Task.detached {
                        try DatabaseDocument.open(data: data, credentials: credential)
                    }.value
                }
                isUnlocking = false
                onUnlocked(document)
            } catch let error as DatabaseOpenError {
                isUnlocking = false
                errorMessage = Self.message(for: error)
            } catch {
                isUnlocking = false
                errorMessage = "Ouverture impossible : \(error.localizedDescription)"
            }
        }
    }

    private func unlockWithBiometrics() {
        guard !isUnlocking else { return }
        errorMessage = nil
        isUnlocking = true
        let provider = appModel.provider(for: database)
        let databaseID = database.id
        let reason = "Déverrouiller « \(database.displayName) »"

        Task {
            do {
                guard let credential = try await appModel.biometricCredential(databaseID: databaseID, reason: reason)
                else {
                    // `nil` = item Keychain absent/invalidé (biométrie changée) : on nettoie
                    // l'état d'enrôlement obsolète pour masquer le bouton, puis repli saisie.
                    try? await appModel.disableBiometric(databaseID: databaseID)
                    isUnlocking = false
                    errorMessage = "\(biometricLabel) n'est plus disponible pour cette base. Saisissez le mot de passe."
                    return
                }
                let data = try await provider.load()
                let document = try await Task.detached {
                    try DatabaseDocument.open(data: data, credentials: credential)
                }.value
                isUnlocking = false
                onUnlocked(document)
            } catch {
                isUnlocking = false
                errorMessage = "Déverrouillage par \(biometricLabel) impossible. Saisissez le mot de passe."
            }
        }
    }

    private func loadKeyFile(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            keyFileData = try Data(contentsOf: url)
            keyFileName = url.lastPathComponent
        } catch {
            errorMessage = "Key file illisible : \(error.localizedDescription)"
        }
    }

    private static func message(for error: DatabaseOpenError) -> String {
        switch error {
        case .wrongCredentials:
            return "Mot de passe ou key file incorrect."
        case .missingCredentials:
            return "Saisissez un mot de passe ou un key file."
        case let .unsupportedVersion(major, minor):
            return "Version KDBX non supportée (\(major).\(minor))."
        case .invalidKeyFile:
            return "Key file invalide."
        case .corrupted:
            // On n'affiche pas le détail interne (`reason`) : message générique côté UI pour
            // éviter d'exposer un éventuel fragment sensible dans les erreurs de bas niveau.
            return "Fichier corrompu ou illisible."
        }
    }
}
