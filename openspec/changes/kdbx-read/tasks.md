## 1. Spike KDBXKit (bloquant, avant toute UI)

- [ ] 1.1 Ajouter la dépendance KDBXKit dans `Package.swift` et `project.yml`
- [ ] 1.2 Committer des golden files de test générés par KeePassXC (KDBX 3.1, 4.0, 4.1 ;
      AES-256 + Argon2, ChaCha20 + Argon2 ; un avec key file ; mots de passe factices)
- [ ] 1.3 Test Core : ouvrir chaque golden file et asserter un contenu connu (échoue si
      KDBXKit ne gère pas un cas requis → déclenche le repli KeePassKit, documenté)

## 2. Core — ouverture & mapping (Swift pur, testable)

- [ ] 2.1 `DatabaseDocument` : `open(data:credentials:) throws` via `KDBXReader.parse`
- [ ] 2.2 Mapping `KDBXContent` → `Group`/`Entry`/`CustomField`/`TotpConfig`/`Attachment`
- [ ] 2.3 Ajuster `Entry` : secrets révélés à la demande (accessor scoped) au lieu de
      `password: String` en clair ; adapter les tests existants
- [ ] 2.4 Erreurs typées (mauvais mot de passe, version non supportée, corruption)
- [ ] 2.5 Génération TOTP (Base32 + HOTP/TOTP)

## 3. App — accès fichier & UI (device, buildé/testé en CI)

- [ ] 3.1 `LocalStorageProvider` : `UIDocumentPicker` + security-scoped bookmark, `load()`
- [ ] 3.2 Écran Unlock (mot de passe + key file optionnel, affichage d'erreur)
- [ ] 3.3 Écran Browse (arborescence groupes/entrées)
- [ ] 3.4 Écran Entry detail (révéler/copier, TOTP + compte à rebours, champs custom,
      liste des pièces jointes) — mot de passe masqué par défaut

## 4. Tests

- [ ] 4.1 Tests Core mapping + erreurs typées (mauvais mot de passe, corruption, versions)
- [ ] 4.2 Round-trip interne de lecture (contenu golden ⇔ modèle domaine)
- [ ] 4.3 Known-Answer Tests TOTP (vecteurs RFC 6238) + décodage Base32
- [ ] 4.4 Test « secret non exposé » : le mot de passe n'apparaît pas en clair dans le modèle

## 5. Interop KeePassXC (CI)

- [ ] 5.1 Étape CI installant `keepassxc-cli` (brew) et ouvrant les golden files (headless,
      mot de passe via stdin) pour confirmer leur validité côté écosystème
- [ ] 5.2 Documenter que le round-trip write→keepassxc-cli complet arrive avec `kdbx-write`

## 6. Vérification manuelle (device — non prouvée par la CI)

- [ ] 6.1 Checklist : importer un vrai `.kdbx` via le sélecteur de fichiers, l'ouvrir,
      parcourir, révéler/copier, vérifier un code TOTP contre une autre app
