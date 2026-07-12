import StrongCloneCore
import SwiftUI

/// Feuille de création d'une entrée : titre + mot de passe. Le mot de passe est saisi dans un
/// `SecureField` et transmis en `ProtectedSecret` (chiffré au repos par la session Core).
struct NewEntryView: View {
    let model: DatabaseSessionModel
    let groupID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") {
                    TextField("Titre de l'entrée", text: $title)
                        .textInputAutocapitalization(.words)
                }
                Section("Mot de passe") {
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.newPassword)
                }
            }
            .navigationTitle("Nouvelle entrée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        model.addEntry(
                            title: title.trimmingCharacters(in: .whitespaces),
                            password: ProtectedSecret(password),
                            inGroup: groupID
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
