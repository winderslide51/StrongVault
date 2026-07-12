import StrongCloneCore
import SwiftUI

/// Détail complet d'une entrée : identifiant, mot de passe (masqué par défaut), URL, notes, code
/// **TOTP** avec compte à rebours, champs personnalisés (masqués si protégés) et liste des pièces
/// jointes (nom + taille). Toute copie passe par `Clipboard` (auto-effacement + `localOnly`).
///
/// Éditable : le bouton « Modifier » présente `EntryEditView`. L'entrée est relue depuis la
/// projection lecture seule du modèle (elle reflète les éditions déjà appliquées).
struct EntryDetailView: View {
    let model: DatabaseSessionModel
    let entryID: UUID

    @State private var showingEdit = false

    /// Entrée courante, reprojetée depuis la session (reflète une édition précédente).
    private var entry: Entry? {
        model.document.root.allEntriesRecursive.first { $0.id == entryID }
    }

    var body: some View {
        Group {
            if let entry {
                content(for: entry)
                    .navigationTitle(entry.title.isEmpty ? "(sans titre)" : entry.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Modifier") { showingEdit = true }
                        }
                    }
                    .sheet(isPresented: $showingEdit) {
                        EntryEditView(model: model, entry: entry)
                    }
            } else {
                // L'entrée a été supprimée (ou la base verrouillée) : rien à afficher.
                ContentUnavailableView("Entrée indisponible", systemImage: "key.slash")
            }
        }
    }

    private func content(for entry: Entry) -> some View {
        List {
            if !entry.username.isEmpty {
                Section("Identifiant") {
                    CopyableRow(text: entry.username, accessibilityLabel: "Copier l'identifiant")
                }
            }

            if !entry.password.isEmpty {
                Section("Mot de passe") {
                    PasswordRow(password: entry.password)
                }
            }

            if let totp = entry.totp {
                Section("Code à usage unique") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        TotpRow(config: totp, date: context.date)
                    }
                }
            }

            if !entry.url.isEmpty {
                Section("URL") {
                    if let url = URL(string: entry.url) {
                        Link(entry.url, destination: url)
                    } else {
                        Text(entry.url)
                    }
                }
            }

            if !entry.notes.isEmpty {
                Section("Notes") {
                    Text(entry.notes)
                        .textSelection(.enabled)
                }
            }

            customFieldsAndAttachments(for: entry)
        }
    }

    @ViewBuilder
    private func customFieldsAndAttachments(for entry: Entry) -> some View {
        if !entry.customFields.isEmpty {
            Section("Champs personnalisés") {
                ForEach(entry.customFields) { field in
                    CustomFieldRow(field: field)
                }
            }
        }

        if !entry.attachments.isEmpty {
            Section("Pièces jointes") {
                ForEach(entry.attachments) { attachment in
                    LabeledContent {
                        Text(byteSize(attachment.data.count))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(attachment.name, systemImage: "paperclip")
                    }
                }
            }
        }
    }

    private func byteSize(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// Valeur en clair (non secrète) avec bouton de copie.
private struct CopyableRow: View {
    let text: String
    let accessibilityLabel: String

    var body: some View {
        HStack {
            Text(text)
                .textSelection(.enabled)
            Spacer()
            Button {
                Clipboard.copy(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// Mot de passe masqué par défaut : révélation à la demande (`ProtectedSecret`) et copie à portée
/// limitée (`withRevealed`).
private struct PasswordRow: View {
    let password: ProtectedSecret

    @State private var revealed = false

    var body: some View {
        HStack {
            Text(revealed ? password.reveal() : "••••••••")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(revealed ? .primary : .secondary)
                .textSelection(.enabled)
            Spacer()
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(revealed ? "Masquer le mot de passe" : "Révéler le mot de passe")

            Button {
                password.withRevealed { Clipboard.copy($0) }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copier le mot de passe")
        }
    }
}

/// Ligne TOTP : code courant + secondes restantes. Le calcul vit en Core (`TotpGenerator`) ; la
/// vue ne fait qu'afficher et rafraîchir chaque seconde via `TimelineView`.
private struct TotpRow: View {
    let config: TotpConfig
    let date: Date

    var body: some View {
        if let code = TotpGenerator.code(for: config, at: date) {
            let remaining = TotpGenerator.remainingSeconds(period: config.period, at: date)
            HStack(spacing: 12) {
                Text(grouped(code))
                    .font(.system(.title2, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                CountdownRing(remaining: remaining, period: config.period)
                Button {
                    Clipboard.copy(code)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copier le code")
            }
        } else {
            Text("Configuration TOTP invalide")
                .foregroundStyle(.secondary)
        }
    }

    /// Regroupe un code à 6 chiffres en `123 456` pour la lisibilité ; laisse les autres tels quels.
    private func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<middle]) \(code[middle...])"
    }
}

/// Compte à rebours circulaire jusqu'au basculement de fenêtre TOTP.
private struct CountdownRing: View {
    let remaining: Int
    let period: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(remaining)")
                .font(.caption2)
                .monospacedDigit()
        }
        .frame(width: 28, height: 28)
        .accessibilityLabel("\(remaining) secondes restantes")
    }

    private var fraction: CGFloat {
        guard period > 0 else { return 0 }
        return CGFloat(remaining) / CGFloat(period)
    }
}

/// Champ personnalisé : masqué par défaut s'il est protégé, révélable, copiable. Le modèle porte
/// la valeur en clair (`CustomField.value`) — c'est l'UI qui applique le masquage via `isProtected`.
private struct CustomFieldRow: View {
    let field: CustomField

    @State private var revealed = false

    private var isHidden: Bool { field.isProtected && !revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.key)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(isHidden ? "••••••••" : field.value)
                    .font(field.isProtected ? .system(.body, design: .monospaced) : .body)
                    .foregroundStyle(isHidden ? .secondary : .primary)
                    .textSelection(.enabled)
                Spacer()
                if field.isProtected {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(revealed ? "Masquer le champ" : "Révéler le champ")
                }
                Button {
                    Clipboard.copy(field.value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copier le champ")
            }
        }
    }
}
