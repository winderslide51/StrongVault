## Why

L'app est aujourd'hui **lecture seule** (`kdbx-read`) : elle ouvre un `.kdbx` et le
parcourt, mais ne peut rien modifier. La première capacité d'écriture est la fondation de
tout le reste : éditer une base ouverte (CRUD complet sur entrées, champs et groupes) puis
la **sauvegarder localement**. C'est aussi le change qui **durcit le contrat `save`** du
protocole `StorageProvider` (jusqu'ici un stub) — contrat dont dépendra ensuite la synchro
Google Drive (`google-drive-sync`).

L'écriture touche à la crypto et au format : une erreur silencieuse peut corrompre une base
ou casser l'interopérabilité KeePassXC (CLAUDE.md §4.2). Ce change s'appuie sur les capacités
d'écriture **déjà présentes dans KDBXKit 1.3.0** (aucune crypto maison, CLAUDE.md §6) et pose
un **spike d'écriture bloquant** prouvé par `keepassxc-cli` réel avant d'écrire quoi que ce soit
d'autre.

## What Changes

- **Session d'édition (Core)** : l'ouverture conserve le `KDBXContent` parsé et **mutable** ;
  une couche Core testable en Swift pur (façon `TreeMutator`/`EntryFieldOps` du CLI KDBXKit)
  **mute l'arbre `KDBX.Group`/`KDBX.Entry` en place**. On ne reconstruit **jamais** un
  `KDBXContent` depuis notre modèle domaine `DatabaseDocument` (projection lossy → perte
  d'historique/icônes/champs non modélisés). C'est le point d'architecture central.
- **Édition des champs** : mot de passe et champs standard (titre, identifiant, URL, notes)
  et champs custom (protégés / non). Un secret modifié est ré-encodé chiffré au repos
  (`ProtectedString.Value.unprotected`, **jamais** `.protectedInMemory` qui est en clair sur
  disque). `Times.lastModificationTime` est bumpé et l'historique snapshoté (comme `entry set`).
- **Structure** : ajout / suppression d'entrées ; ajout / suppression / renommage de groupes.
- **Sérialisation & sauvegarde** : ré-encodage via `KDBXWriter` (chemin de production
  `streamingWrite`, ou `write` eager pour un buffer testable) puis `StorageProvider.save(...)`.
  `LocalStorageProvider` (App) **implémente réellement** `save` (fin du stub côté local) et
  renvoie un `StorageMetadata` à jour.
- **Migration 3.1 → 4.1** : le writer n'émet que du KDBX 4.x ; une base 3.1 est migrée à la
  sauvegarde. `KDBXContent.legacyFormatNotice == .willMigrate(from:)` est remonté à l'UI qui
  **prévient l'utilisateur avant d'écraser**.
- **Interop** : spike + étape CI `keepassxc-cli` (write → open) — le round-trip interne prouve
  la self-consistance, **pas** l'interop.

## Capabilities

### New Capabilities
- `database-editing`: session d'édition Core mutant le `KDBXContent` en place (champs
  standard/custom, mot de passe chiffré au repos + historique/dates, CRUD entrées & groupes).
- `database-saving`: ré-sérialisation via `KDBXWriter`, sauvegarde locale réelle via
  `StorageProvider.save`, avertissement de migration 3.1→4.1, interop KeePassXC.

### Modified Capabilities
<!-- Aucune capacité de spec **archivée** n'est modifiée. Le contrat `StorageProvider.save`
     et `StorageMetadata` appartiennent à `core-foundation` (scaffolding, **non archivé**) :
     `database-saving` en durcit la sémantique (save réel + métadonnées à jour) sans delta
     MODIFIED formel, comme `kdbx-read` l'a fait pour le modèle `Entry`. La cohérence du
     contrat `save`/`StorageMetadata` avec `google-drive-sync` (jeton de révision) est
     assurée : voir design.md. -->

## Impact

- Aucune nouvelle dépendance : KDBXKit 1.3.0 (déjà présent) sait écrire.
- CI : nouvelle étape interop **write → `keepassxc-cli` open** (round-trip réel), en plus de
  la lecture posée par `kdbx-read`.
- `LocalStorageProvider.save` devient effectif (device) ; le stub `GoogleDriveProvider.save`
  reste tel quel jusqu'à `google-drive-sync`.
- Critères vérifiables : chaque exigence de `database-editing` porte ≥1 scénario Core prouvé
  par `swift test` ; `database-saving` ajoute un scénario interop `keepassxc-cli` en CI.
- **Non-goals** : upload/synchro Drive et détection de conflit (`google-drive-sync`) ;
  résolution de conflit / merge ; **création d'une base neuve** dans l'UI (bien que
  `KDBXContent.makeEmpty` existe) ; déplacement d'entrées entre groupes ; ajout/suppression de
  **pièces jointes** et édition d'**icônes custom** ; édition TOTP ; corbeille/undo ; AutoFill ;
  iPad / macOS.
