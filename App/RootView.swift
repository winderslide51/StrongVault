import StrongCloneCore
import SwiftUI
import UniformTypeIdentifiers

/// Écran racine : liste des bases connues + ajout d'une base `.kdbx` locale. Sélectionner une
/// base ouvre l'écran de déverrouillage, puis la navigation (change `kdbx-read`). L'ajout depuis
/// Google Drive et le déverrouillage FaceID arrivent avec `google-drive` / `faceid-unlock`.
struct RootView: View {
    @State private var model = AppModel()
    @State private var showingImporter = false
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
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: String.self) { databaseID in
                if let database = model.databases.first(where: { $0.id == databaseID }) {
                    UnlockGate(database: database)
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
        }
    }
}

/// Relie l'écran Unlock à l'écran Browse : tant que la base n'est pas ouverte, on affiche
/// `UnlockView` ; une fois le document obtenu, on bascule sur `BrowseView`.
private struct UnlockGate: View {
    let database: DatabaseRef
    @State private var document: DatabaseDocument?

    var body: some View {
        if let document {
            BrowseView(document: document)
        } else {
            UnlockView(database: database) { opened in
                document = opened
            }
        }
    }
}

#Preview {
    RootView()
}
