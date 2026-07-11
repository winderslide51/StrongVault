import StrongCloneCore
import SwiftUI

/// Navigation en **arbre** : chaque niveau liste les sous-groupes (navigables) puis les entrées
/// du groupe courant. Sélectionner une entrée ouvre `EntryDetailView` (détail complet + TOTP).
struct BrowseView: View {
    let document: DatabaseDocument

    var body: some View {
        GroupListView(group: document.root, title: document.name ?? document.root.name)
    }
}

/// Un niveau de l'arborescence : sous-groupes en tête (navigation récursive), entrées ensuite.
private struct GroupListView: View {
    // Qualifié : `Group` est ambigu avec `SwiftUI.Group`.
    let group: StrongCloneCore.Group
    let title: String

    private var subgroups: [StrongCloneCore.Group] {
        group.subgroups.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var entries: [Entry] {
        group.entries.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if subgroups.isEmpty, entries.isEmpty {
                ContentUnavailableView("Groupe vide", systemImage: "tray")
            }

            if !subgroups.isEmpty {
                Section("Groupes") {
                    ForEach(subgroups) { subgroup in
                        NavigationLink {
                            GroupListView(group: subgroup, title: name(of: subgroup))
                        } label: {
                            Label(name(of: subgroup), systemImage: "folder")
                        }
                    }
                }
            }

            if !entries.isEmpty {
                Section("Entrées") {
                    ForEach(entries) { entry in
                        NavigationLink {
                            EntryDetailView(entry: entry)
                        } label: {
                            EntryRowLabel(entry: entry)
                        }
                    }
                }
            }
        }
        .navigationTitle(title.isEmpty ? "Base" : title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func name(of group: StrongCloneCore.Group) -> String {
        group.name.isEmpty ? "(sans nom)" : group.name
    }
}

/// Ligne d'entrée : titre + identifiant en sous-titre. Aucun secret affiché ici (le mot de passe
/// n'est révélé que dans le détail, sur action explicite).
private struct EntryRowLabel: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title.isEmpty ? "(sans titre)" : entry.title)
                .font(.body)
            if !entry.username.isEmpty {
                Text(entry.username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
