import StrongCloneCore
import SwiftUI

/// Écran racine — squelette de la liste des bases (change `scaffolding`).
/// Les écrans réels (ajout de base locale/Drive, déverrouillage, navigation) arrivent
/// dans les changes `kdbx-read`, `faceid-unlock`, etc.
struct RootView: View {
    // Données de démonstration prouvant le câblage App → StrongCloneCore.
    private let sampleGroup = Group(
        name: "Démo",
        entries: [Entry(title: "Exemple", username: "moi@exemple.fr")]
    )

    var body: some View {
        NavigationStack {
            List {
                Section("Bases") {
                    ContentUnavailableView(
                        "Aucune base",
                        systemImage: "lock.rectangle.stack",
                        description: Text("Ajoutez une base .kdbx locale ou depuis Google Drive.")
                    )
                }
                Section("Aperçu domaine (démo)") {
                    ForEach(sampleGroup.allEntriesRecursive) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.title).font(.headline)
                            Text(entry.username).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("StrongClone")
        }
    }
}

#Preview {
    RootView()
}
