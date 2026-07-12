## 1. SPIKE d'écriture — BLOQUANT (prouvable en CI)

> Aucune autre tâche ne démarre tant que ce spike n'est pas vert. Il prouve l'interop réelle,
> pas la self-consistance.

- [x] 1.1 Charger un golden file existant (`demo-password.kdbx`), le parser en `KDBXContent`,
      **muter en mémoire** l'arbre `KDBX.Entry` (changer un mot de passe en `.unprotected`).
- [x] 1.2 Ré-encoder via `KDBXWriter.write(...)` vers un buffer `Data`, écrire dans un fichier
      temporaire.
- [x] 1.3 Ouvrir ce fichier avec **`keepassxc-cli`** (headless, mot de passe via stdin) et
      asserter que la modification est lue. Échec ⇒ on bloque et on diagnostique avant tout code
      d'édition (piège connus : déclaration `<?xml version>`, séparateur de tags, key-file).

## 2. Core — session d'édition (Swift pur, testable via `swift test`)

- [x] 2.1 Conserver le `KDBXContent` parsé à l'ouverture (session mutable) ; le modèle domaine
      `DatabaseDocument` reste une projection lecture seule. **Ne jamais** reconstruire un
      `KDBXContent` depuis `DatabaseDocument`.
- [x] 2.2 Opérations d'édition de champ (façon `EntryFieldOps`/`TreeMutator` du CLI KDBXKit),
      ciblées par UUID : set mot de passe (`.unprotected`), set champs standard, set champ custom
      protégé (`.unprotected`) / non protégé (`.regular`).
- [x] 2.3 Bump `Times.lastModificationTime` + snapshot historique à chaque édition de champ.
- [x] 2.4 CRUD structure : add/delete entrée dans un groupe ; add/delete/rename groupe.
- [x] 2.5 Garde-fou sécurité : les secrets d'édition empruntent les types protégés (pas de
      `String` persistant) ; jamais `.protectedInMemory`.

## 3. Core — sérialisation (Swift pur, testable via `swift test`)

- [x] 3.1 Ré-encoder le `KDBXContent` édité en octets via `KDBXWriter.write(...)` (buffer),
      `regenerateSalts: true` par défaut.
- [x] 3.2 Exposer `legacyFormatNotice` (`.willMigrate(from:)`) au niveau session pour l'UI.

## 4. App — sauvegarde locale & UI (device, build/test en CI)

- [x] 4.1 `LocalStorageProvider.save(_:expectedRemote:)` réel : écriture **atomique** à
      l'emplacement du security-scoped bookmark, retour d'un `StorageMetadata` à jour. Fin du
      stub local. Chemin de production via `KDBXWriter.streamingWrite(to:)`.
- [x] 4.2 UI d'édition : écran de consultation `EntryDetailView` rendu éditable (champs
      standard + custom protégés/non), ajout/suppression d'entrée, add/delete/rename de groupe.
- [x] 4.3 Bannière d'avertissement de **migration 3.1→4.1** avant sauvegarde (via
      `legacyFormatNotice`), confirmation utilisateur avant écrasement.
- [x] 4.4 Purge mémoire au verrouillage inchangée : l'état d'édition non sauvegardé est aussi
      purgé (pas de secret édité résiduel).

## 5. Interop KeePassXC (CI) — étape obligatoire (CLAUDE.md §4.2)

- [x] 5.1 Étape CI **write → `keepassxc-cli` open** : le round-trip reprend le spike §1 sur les
      golden files (édition en mémoire → `KDBXWriter` → `keepassxc-cli` ré-ouvre et vérifie).
- [x] 5.2 Test Core de round-trip **stable** (`regenerateSalts: false`) : sels/nonce préservés et
      contenu strictement identique après reparse. (Le byte-identique initialement visé n'est pas
      garanti par KDBXKit : l'ordre des champs du VariantDictionary KDF — un `Dictionary` Swift —
      peut permuter entre deux écritures, fichiers sémantiquement identiques et valides.)

## 6. Tests (Core, `swift test`)

- [x] 6.1 Édition mot de passe → `.unprotected`, `lastModificationTime` bumpé, historique +1.
- [x] 6.2 Champs standard + custom protégé (`.unprotected`) / non protégé (`.regular`).
- [x] 6.3 CRUD entrées & groupes (add/delete/rename) via ré-ouverture.
- [x] 6.4 Préservation des données non modélisées (champ inconnu conservé après édition d'un
      autre champ) — prouve la mutation en place vs. reconstruction lossy.
- [x] 6.5 Migration : base 3.1 ⇒ `legacyFormatNotice == .willMigrate(from:)` ; base 4.x ⇒ `nil`.
- [x] 6.6 Sécurité : un secret édité n'apparaît en clair dans aucune description/log du modèle.

## 7. Vérification manuelle (device — non prouvée par la CI)

- [ ] 7.1 Éditer une vraie base locale sur iPhone, sauvegarder, la rouvrir dans KeePassXC
      desktop ; vérifier une migration 3.1→4.1 avec l'avertissement affiché avant écrasement.
