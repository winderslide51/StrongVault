import StrongCloneCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Navigation minimale : liste à plat des entrées de la base ouverte, avec révélation et copie
/// du mot de passe (masqué par défaut). L'arborescence complète, le détail riche et le TOTP
/// arrivent avec le change de suivi.
struct BrowseView: View {
    let document: DatabaseDocument

    private var entries: [Entry] {
        document.root.allEntriesRecursive.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Base vide", systemImage: "tray")
            } else {
                ForEach(entries) { entry in
                    EntryRow(entry: entry)
                }
            }
        }
        .navigationTitle(document.name ?? "Base")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Une entrée : titre, identifiant, et mot de passe masqué révélable + copiable.
private struct EntryRow: View {
    let entry: Entry

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title.isEmpty ? "(sans titre)" : entry.title)
                .font(.headline)

            if !entry.username.isEmpty {
                HStack {
                    Label(entry.username, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Clipboard.copy(entry.username)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copier l'identifiant")
                }
            }

            HStack {
                Image(systemName: "key")
                Text(revealed ? entry.password.reveal() : "••••••••")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(revealed ? .primary : .secondary)
                Spacer()
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(revealed ? "Masquer le mot de passe" : "Révéler le mot de passe")

                Button {
                    entry.password.withRevealed { Clipboard.copy($0) }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copier le mot de passe")
            }

            if !entry.url.isEmpty {
                Text(entry.url)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Copie presse-papier avec **auto-effacement** (CLAUDE.md §5) : l'item expire après un délai
/// via l'API native `UIPasteboard`, sans laisser le secret traîner indéfiniment.
private enum Clipboard {
    static let clearDelay: TimeInterval = 30

    static func copy(_ value: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [.expirationDate: Date().addingTimeInterval(clearDelay)]
        )
    }
}
