> **Résultat du spike (2026-07-11)** : KDBXKit **1.3.0** validé. Il lit les bases KeePassXC
> KDBX 4.x (AES-256, KDF AES-KDF), lève des erreurs typées (`KDBXReader.Error.wrongCredentials`,
> `.unsupportedFormatVersion`, `.corruptedHMAC`), et **expose la clé composite 32 o** via
> `UnlockData.keyDataBytes` / `init(rawKeyData:)` → **FaceID Option A retenue** (voir `faceid-unlock`).
> Pas de repli KeePassKit nécessaire. Deux limites relevées, non bloquantes pour la tranche
> minimale : (a) `keepassxc-cli db-create` ne permet pas de choisir version/cipher/KDF (produit
> du KDBX 4.x AES-KDF) → matrice 3.1/4.0/ChaCha20/Argon2 reportée au change de suivi ; (b) KDBXKit
> 1.3.0 lit mal les key files **XML v2.0** de KeePassXC (décode le hex comme du base64) → on
> utilise un **key file binaire brut 32 o**, correctement géré des deux côtés.

- [x] 1.1 Ajouter la dépendance KDBXKit dans `Package.swift` et `project.yml`
- [~] 1.2 Golden files KeePassXC committés : `demo-password.kdbx` (AES-256/AES-KDF, mdp seul) et
      `demo-keyfile.kdbx` + `demo-keyfile.key` (mdp + key file brut). Mots de passe factices
      documentés. Matrice 3.1/4.0/4.1 + ChaCha20 + Argon2 **reportée** (cf. limite `keepassxc-cli`).
- [x] 1.3 Test Core `KDBXKitSpikeTests` : ouvre chaque golden file, asserte le contenu connu,
      vérifie l'erreur typée sur mauvais mot de passe, et le round-trip clé composite (FaceID).

## 2. Core — ouverture & mapping (Swift pur, testable)

- [x] 2.1 `DatabaseDocument.open(data:credentials:) throws` via `KDBXReader.parse` + type
      partagé `DatabaseCredential` (point de couplage Drive/FaceID).
- [x] 2.2 Mapping `KDBXContent` → `Group`/`Entry` (champs standard + dates), plus `CustomField`
      (tous les champs hors standards/TOTP, `isProtected` reflétant `Protected="True"` KDBX),
      `TotpConfig` (parsing otpauth URI **et** `TOTP Seed`/`TOTP Settings` KeePassXC) et
      `Attachment` (binaires `.inline` et `.ref` résolus via le pool `innerHeader.binaryContent`).
      `mapEntry`/`mapGroup` passés en `internal` pour être exercés directement par les tests.
- [x] 2.3 `Entry.password` → `ProtectedSecret` (révélé à la demande, jamais `String` en clair,
      `description` masquée) ; tests existants adaptés (init inchangé grâce au string literal).
- [x] 2.4 Erreurs typées `DatabaseOpenError` (wrongCredentials, missingCredentials,
      unsupportedVersion, corrupted, invalidKeyFile) mappées depuis `KDBXReader.Error`.
- [x] 2.5 Génération TOTP dans `TotpGenerator` : décodage Base32 (RFC 4648, tolérant
      padding/espaces/casse) + HOTP/TOTP (RFC 4226/6238) via CryptoKit HMAC (SHA1/256/512),
      `digits`/`period` depuis `TotpConfig`, plus `remainingSeconds(period:at:)` pour le
      compte à rebours. Secret jamais journalisé.

## 3. App — accès fichier & UI (device, buildé/testé en CI)

- [x] 3.1 `LocalStorageProvider` : `fileImporter` + security-scoped bookmark, `load()`
      (conforme au protocole Core `StorageProvider`, lecture seule).
- [x] 3.2 Écran Unlock (mot de passe + key file optionnel, erreurs typées affichées).
- [x] 3.3 Écran Browse en **arbre** : chaque niveau liste les sous-groupes (navigation
      récursive) puis les entrées du groupe courant ; tap sur une entrée → `EntryDetailView`.
      `Clipboard` extrait dans `App/Clipboard.swift` (partagé).
- [x] 3.4 `EntryDetailView` : identifiant (copie), mot de passe masqué révélable/copiable
      (`ProtectedSecret`), URL, notes, **TOTP** (code + compte à rebours rafraîchi chaque
      seconde via `TimelineView`, copie), champs custom (masqués si `isProtected`, révélables)
      et liste des pièces jointes (nom + taille, sans aperçu/export en v1). Copies via
      `Clipboard` (auto-effacement §5 + `localOnly`).

## 4. Tests

- [x] 4.1 Tests Core mapping + erreurs typées (`DatabaseDocumentTests` : mauvais mot de passe,
      identifiants manquants, key file).
- [x] 4.2 Round-trip interne de lecture (contenu golden ⇔ modèle domaine).
- [x] 4.3 Known-Answer Tests TOTP (`TotpGeneratorTests`) : vecteurs RFC 6238 Annexe B
      (SHA1/256/512, digits 8, timestamps 59…20000000000), décodage Base32 RFC 4648 (+ entrées
      invalides → nil), parsing otpauth URI et `TOTP Seed`/`TOTP Settings`. Mapping enrichi
      couvert par `DatabaseMappingTests` (customFields protégés/non, TOTP, pièces jointes
      inline/ref).
- [x] 4.4 Test « secret non exposé » : le mot de passe n'apparaît pas en clair dans le modèle
      (`description`/`reflecting` masqués, révélation explicite requise).

## 5. Interop KeePassXC (CI)

- [ ] 5.1 Étape CI installant `keepassxc-cli` (brew) et ouvrant les golden files (headless,
      mot de passe via stdin) pour confirmer leur validité côté écosystème
- [ ] 5.2 Documenter que le round-trip write→keepassxc-cli complet arrive avec `kdbx-write`

## 6. Vérification manuelle (device — non prouvée par la CI)

- [ ] 6.1 Checklist : importer un vrai `.kdbx` via le sélecteur de fichiers, l'ouvrir,
      parcourir, révéler/copier, vérifier un code TOTP contre une autre app
