## Context

Premier contact avec le vrai format. KDBXKit expose : `KDBXReader.parse(_ data:, unlockData:)
throws -> KDBXContent`, `UnlockData(masterPassword:/keyFile:/rawKeyData:)`, un modèle
`KDBXDatabase/Group/Entry` où les valeurs sont des `ProtectedString` révélées via
`withRevealedString { }`, et des erreurs typées (`.wrongCredentials`,
`.unsupportedFormatVersion`, `.corruptedHMAC`). Versions : lecture 3.1/4.0/4.1, écriture 4.x.

## Goals / Non-Goals

**Goals:**
- Ouvrir un `.kdbx` local et parcourir groupes/entrées + détail, en lecture seule.
- Valider KDBXKit sur fichiers réels (spike) et établir l'interop KeePassXC de référence.
- Ne jamais faire fuiter de secret en clair au-delà du strict nécessaire à l'affichage.

**Non-Goals:**
- Édition/sauvegarde, FaceID, Google Drive, recherche — changes ultérieurs.

## Decisions

- **Spike d'abord** : avant d'écrire l'UI, un test ouvre des golden files (3.1 + 4.x,
  Argon2/ChaCha20 et AES) et vérifie le contenu. Si KDBXKit échoue sur un cas nécessaire,
  on bascule sur le repli KeePassKit — décidé sur preuve, pas sur intuition.
- **Secrets révélés à la demande** : le mapping `KDBXContent`→domaine ne copie pas les
  mots de passe dans des `String`. `Entry` expose `reveal(_ field:) -> String` (ou un
  `SecretRef`) qui délègue à `ProtectedString.withRevealedString`. Alternative écartée :
  `password: String` eager (simple mais viole CLAUDE.md §4 ; secrets traînant en mémoire).
- **`UnlockData(masterPassword:)` maintenant, `rawKeyData:` plus tard** : le change FaceID
  réutilisera `rawKeyData` (clé 32 octets pré-hachée) stockée en Keychain — on n'y touche
  pas ici mais le mapping en tient compte.
- **`LocalStorageProvider`** : `UIDocumentPicker` (couche App) + security-scoped bookmark
  persistant ; `load()` renvoie les octets. Le Core reste agnostique (protocole existant).
- **Interop = source de vérité** : golden files générés par KeePassXC (commités, avec mots
  de passe de test bidon) ; le round-trip complet (write→keepassxc-cli) arrivera avec
  `kdbx-write`, mais l'étape CI `keepassxc-cli` (lecture) est posée dès maintenant.

## Risks / Trade-offs

- [KDBXKit incomplet sur un format réel] → spike bloquant en tout début ; repli KeePassKit.
- [Changer `Entry` casse le code existant] → peu de code en dépend (scaffolding) ; migration
  triviale, couverte par tests.
- [Golden files = secrets de test dans le repo] → mots de passe factices documentés, jamais
  de vraie donnée ; fichiers marqués comme fixtures de test.
- [Fuite de secret via logs/SwiftUI] → interdiction de `print`/log de secret ; l'UI n'affiche
  le mot de passe que sur action explicite (révéler) et efface le presse-papier (polish).

## Migration Plan

Additif : nouvelle dépendance + nouveaux fichiers. La modification de `Entry` est portée par
les tests. Rollback = retrait de la dépendance et des écrans (aucune donnée persistée).

## Open Questions

- Faut-il un `SecretRef` typé ou une simple fermeture `reveal` ? (proposé : accessor sur
  `Entry`, tranché à l'implémentation selon ergonomie/testabilité).
- Copie presse-papier : délai d'auto-effacement — fixé dans `polish`, valeur par défaut ici.
