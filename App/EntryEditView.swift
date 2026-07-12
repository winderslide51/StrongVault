import StrongCloneCore
import SwiftUI

/// Formulaire d'édition d'une entrée : champs standard, mot de passe, et champs personnalisés
/// (ajout/suppression, bascule protégé/clair). À la validation, applique les modifications à la
/// session Core via `applyEntryEdits` (mot de passe et champs protégés → chiffrés au repos).
///
/// Le mot de passe est matérialisé en clair le temps de l'édition (inévitable à ce point) puis
/// re-encapsulé en `ProtectedSecret` ; il n'est jamais affiché en clair sans action explicite.
struct EntryEditView: View {
    let model: DatabaseSessionModel
    let entry: Entry

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var username: String
    @State private var password: String
    @State private var revealPassword = false
    @State private var url: String
    @State private var notes: String
    @State private var customFields: [DraftCustomField]
    private let originalCustomKeys: [String]

    init(model: DatabaseSessionModel, entry: Entry) {
        self.model = model
        self.entry = entry
        _title = State(initialValue: entry.title)
        _username = State(initialValue: entry.username)
        _password = State(initialValue: entry.password.reveal())
        _url = State(initialValue: entry.url)
        _notes = State(initialValue: entry.notes)
        _customFields = State(initialValue: entry.customFields.map(DraftCustomField.init))
        originalCustomKeys = entry.customFields.map(\.key)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") {
                    TextField("Titre", text: $title)
                }
                Section("Identifiant") {
                    TextField("Identifiant", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Mot de passe") {
                    HStack {
                        if revealPassword {
                            TextField("Mot de passe", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Mot de passe", text: $password)
                        }
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("URL") {
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                customFieldsSection
            }
            .navigationTitle("Modifier l'entrée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { commit() }
                }
            }
        }
    }

    private var customFieldsSection: some View {
        Section("Champs personnalisés") {
            ForEach($customFields) { $field in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Clé", text: $field.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if field.isProtected {
                        SecureField("Valeur", text: $field.value)
                    } else {
                        TextField("Valeur", text: $field.value)
                    }
                    Toggle("Protégé", isOn: $field.isProtected)
                        .font(.caption)
                }
            }
            .onDelete { customFields.remove(atOffsets: $0) }

            Button {
                customFields.append(DraftCustomField(key: "", value: "", isProtected: false))
            } label: {
                Label("Ajouter un champ", systemImage: "plus.circle")
            }
        }
    }

    private func commit() {
        // Champs custom valides (clé non vide), dédupliqués par clé (la dernière gagne).
        let valid = customFields.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        let currentKeys = Set(valid.map(\.key))
        // Clés d'origine disparues du formulaire → à retirer de l'entrée.
        let removedKeys = originalCustomKeys.filter { !currentKeys.contains($0) }

        model.applyEntryEdits(
            entryID: entry.id,
            EntryEdits(
                title: title,
                username: username,
                url: url,
                notes: notes,
                password: ProtectedSecret(password),
                customFields: valid.map { CustomField(key: $0.key, value: $0.value, isProtected: $0.isProtected) },
                removedCustomKeys: removedKeys
            )
        )
        dismiss()
    }
}

/// Brouillon éditable d'un champ personnalisé (identifiable pour `ForEach`).
private struct DraftCustomField: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var isProtected: Bool

    init(key: String, value: String, isProtected: Bool) {
        self.key = key
        self.value = value
        self.isProtected = isProtected
    }

    init(_ field: CustomField) {
        key = field.key
        value = field.value
        isProtected = field.isProtected
    }
}
