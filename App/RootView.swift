import StrongCloneCore
import SwiftUI
import UniformTypeIdentifiers

/// Écran racine : liste des bases connues + ajout d'une base `.kdbx` locale. Sélectionner une
/// base ouvre l'écran de déverrouillage, puis la navigation (change `kdbx-read`). L'ajout depuis
/// Google Drive et le déverrouillage FaceID arrivent avec `google-drive` / `faceid-unlock`.
struct RootView: View {
    @State private var model = AppModel()
    @State private var showingImporter = false
    @State private var showingDrivePicker = false
    @State private var importError: String?

    /// Type `.kdbx` (non enregistré au système) : on le dérive de l'extension, avec repli `.data`.
    private static let kdbxTypes: [UTType] = [UTType(filenameExtension: "kdbx") ?? .data, .data]

    var body: some View {
        NavigationStack {
            Group {
                if model.databases.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune base", systemImage: "lock.rectangle.stack")
                    } description: {
                        Text("Ajoutez une base .kdbx locale pour commencer.")
                    } actions: {
                        Button("Ajouter une base locale") { showingImporter = true }
                            .buttonStyle(.borderedProminent)
                        Button("Ajouter depuis Google Drive") { showingDrivePicker = true }
                    }
                } else {
                    List {
                        Section("Bases") {
                            ForEach(model.databases) { database in
                                NavigationLink(value: database.id) {
                                    Label(database.displayName, systemImage: "lock.doc")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("StrongClone")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Base locale…", systemImage: "folder")
                        }
                        Button {
                            showingDrivePicker = true
                        } label: {
                            Label("Google Drive…", systemImage: "cloud")
                        }
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: String.self) { databaseID in
                if let database = model.databases.first(where: { $0.id == databaseID }) {
                    UnlockGate(database: database, appModel: model)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.kdbxTypes) { result in
                switch result {
                case let .success(url):
                    do {
                        try model.addLocalDatabase(from: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                case let .failure(error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import impossible", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .sheet(isPresented: $showingDrivePicker) {
                AddDriveDatabaseView(appModel: model) { fileId, name in
                    model.addDriveDatabase(fileId: fileId, displayName: name)
                }
            }
            .onOpenURL { url in
                // Redirection OAuth Google (schéma d'URL de l'app) → échange de jeton via le SDK.
                Task { await model.handleDriveRedirect(url) }
            }
        }
    }
}

/// Relie l'écran Unlock à l'écran Browse : tant que la base n'est pas ouverte, on affiche
/// `UnlockView` ; une fois la session obtenue, on bascule sur `BrowseView`.
///
/// Verrouillage/purge (CLAUDE.md §4.4) : au passage en arrière-plan, on détruit la session
/// (`sessionModel = nil`). Cela purge le `KDBXContent` déchiffré, la clé composite **et l'état
/// d'édition non sauvegardé** — aucun secret édité résiduel. L'utilisateur repasse par Unlock.
private struct UnlockGate: View {
    let database: DatabaseRef
    let appModel: AppModel
    @State private var sessionModel: DatabaseSessionModel?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let sessionModel {
                BrowseView(model: sessionModel)
            } else {
                UnlockView(database: database, appModel: appModel) { session in
                    sessionModel = DatabaseSessionModel(
                        session: session,
                        provider: appModel.provider(for: database)
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                sessionModel = nil
            }
        }
    }
}

#Preview {
    RootView()
}
