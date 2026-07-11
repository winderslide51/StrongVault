import SwiftUI

/// Ajout d'une base depuis Google Drive : connexion OAuth (SDK), liste des `.kdbx`, sélection.
/// « Build only » : tant qu'aucun client OAuth n'est configuré, l'écran l'indique. La connexion
/// réelle s'appuie sur le navigateur système + la redirection gérée par `AppModel`.
struct AddDriveDatabaseView: View {
    let appModel: AppModel
    let onPicked: (_ fileId: String, _ name: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var signedIn = false
    @State private var files: [DriveFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Google Drive")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
                .task { await refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !appModel.isDriveConfigured {
            ContentUnavailableView {
                Label("Google Drive non configuré", systemImage: "cloud.slash")
            } description: {
                Text("Un client OAuth Google (clientID + redirect) doit être fourni pour se connecter.")
            }
        } else if !signedIn {
            connectView
        } else {
            fileList
        }
    }

    private var connectView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Se connecter à Google Drive", systemImage: "cloud")
            } description: {
                Text("Autorisez l'accès en lecture pour choisir une base .kdbx.")
            }
            Button("Se connecter") {
                Task {
                    await appModel.driveSignIn()
                    await refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            Button("J'ai terminé la connexion") {
                Task { await refresh() }
            }
        }
        .padding()
    }

    private var fileList: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if isLoading {
                HStack {
                    ProgressView(); Text("Chargement…")
                }
            } else if files.isEmpty {
                ContentUnavailableView("Aucun .kdbx trouvé", systemImage: "tray")
            } else {
                ForEach(files) { file in
                    Button {
                        onPicked(file.id, file.name)
                        dismiss()
                    } label: {
                        Label(file.name, systemImage: "doc")
                    }
                }
            }
        }
        .refreshable { await loadFiles() }
    }

    private func refresh() async {
        signedIn = await appModel.isDriveSignedIn()
        if signedIn { await loadFiles() }
    }

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            files = try await appModel.listDriveKdbxFiles()
        } catch {
            errorMessage = "Liste indisponible : \(error.localizedDescription)"
        }
        isLoading = false
    }
}
