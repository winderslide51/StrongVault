import StrongCloneCore
import SwiftUI

/// Navigation en **arbre** éditable : chaque niveau liste les sous-groupes (navigables) puis les
/// entrées du groupe courant. On peut ajouter/supprimer/renommer groupes et entrées, éditer une
/// entrée (`EntryDetailView`), et sauvegarder (avec avertissement de migration 3.1→4.1).
struct BrowseView: View {
    let model: DatabaseSessionModel

    var body: some View {
        let root = model.document.root
        GroupListView(model: model, groupID: root.id, title: model.document.name ?? root.name)
    }
}

/// Un niveau de l'arborescence : sous-groupes en tête (navigation récursive), entrées ensuite.
private struct GroupListView: View {
    let model: DatabaseSessionModel
    let groupID: UUID
    let title: String

    @State private var showingAddEntry = false
    @State private var showingAddGroup = false
    @State private var renameTarget: StrongCloneCore.Group?

    // Groupe courant recalculé depuis la projection lecture seule (reflète les éditions).
    private var group: StrongCloneCore.Group? {
        model.document.root.findSubgroup(id: groupID)
    }

    private var subgroups: [StrongCloneCore.Group] {
        (group?.subgroups ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var entries: [Entry] {
        (group?.entries ?? []).sorted {
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
                            GroupListView(model: model, groupID: subgroup.id, title: name(of: subgroup))
                        } label: {
                            Label(name(of: subgroup), systemImage: "folder")
                        }
                        .swipeActions {
                            Button("Supprimer", role: .destructive) { model.removeGroup(subgroup.id) }
                            Button("Renommer") { renameTarget = subgroup }
                                .tint(.blue)
                        }
                    }
                }
            }

            if !entries.isEmpty {
                Section("Entrées") {
                    ForEach(entries) { entry in
                        NavigationLink {
                            EntryDetailView(model: model, entryID: entry.id)
                        } label: {
                            EntryRowLabel(entry: entry)
                        }
                        .swipeActions {
                            Button("Supprimer", role: .destructive) { model.removeEntry(entry.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle(title.isEmpty ? "Base" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Nouvelle entrée", systemImage: "key")
                    }
                    Button {
                        showingAddGroup = true
                    } label: {
                        Label("Nouveau groupe", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                SaveButton(model: model)
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            NewEntryView(model: model, groupID: groupID)
        }
        .alert("Nouveau groupe", isPresented: $showingAddGroup) {
            NewGroupAlert(model: model, parentID: groupID)
        }
        .alert(
            "Renommer le groupe",
            isPresented: .init(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            if let target = renameTarget {
                RenameGroupAlert(model: model, group: target) { renameTarget = nil }
            }
        }
        .alert(
            "Erreur",
            isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func name(of group: StrongCloneCore.Group) -> String {
        group.name.isEmpty ? "(sans nom)" : group.name
    }
}

/// Bouton de sauvegarde : si la base est en KDBX 3.1, prévient de la migration 3.1→4.1 **avant**
/// d'écraser l'original (CLAUDE.md — l'utilisateur confirme avant écriture destructive).
private struct SaveButton: View {
    let model: DatabaseSessionModel
    @State private var showingMigrationConfirm = false

    var body: some View {
        Button {
            if model.migrationNotice != nil {
                showingMigrationConfirm = true
            } else {
                Task { await model.save() }
            }
        } label: {
            if model.isSaving {
                ProgressView()
            } else {
                Text("Enregistrer")
            }
        }
        .disabled(!model.hasUnsavedChanges || model.isSaving)
        .confirmationDialog(
            migrationMessage,
            isPresented: $showingMigrationConfirm,
            titleVisibility: .visible
        ) {
            Button("Migrer et enregistrer") { Task { await model.save() } }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var migrationMessage: String {
        if case let .willMigrate(fromVersion) = model.migrationNotice {
            return "Cette base est au format KDBX \(fromVersion). L'enregistrement la migrera "
                + "définitivement en KDBX 4.1 avant d'écraser le fichier."
        }
        return "Enregistrer"
    }
}

/// Ligne d'entrée : titre + identifiant en sous-titre. Aucun secret affiché ici.
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

/// Champ texte de l'alerte « Nouveau groupe » + action de création.
private struct NewGroupAlert: View {
    let model: DatabaseSessionModel
    let parentID: UUID
    @State private var name = ""

    var body: some View {
        TextField("Nom du groupe", text: $name)
        Button("Créer") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { model.addGroup(name: trimmed, inGroup: parentID) }
            name = ""
        }
        Button("Annuler", role: .cancel) { name = "" }
    }
}

/// Champ texte de l'alerte de renommage de groupe.
private struct RenameGroupAlert: View {
    let model: DatabaseSessionModel
    let group: StrongCloneCore.Group
    let onDone: () -> Void
    @State private var name: String

    init(model: DatabaseSessionModel, group: StrongCloneCore.Group, onDone: @escaping () -> Void) {
        self.model = model
        self.group = group
        self.onDone = onDone
        _name = State(initialValue: group.name)
    }

    var body: some View {
        TextField("Nom du groupe", text: $name)
        Button("Renommer") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { model.renameGroup(group.id, to: trimmed) }
            onDone()
        }
        Button("Annuler", role: .cancel) { onDone() }
    }
}

extension StrongCloneCore.Group {
    /// Recherche récursive d'un (sous-)groupe par identifiant, `self` inclus.
    func findSubgroup(id: UUID) -> StrongCloneCore.Group? {
        if self.id == id { return self }
        for child in subgroups {
            if let found = child.findSubgroup(id: id) { return found }
        }
        return nil
    }
}
