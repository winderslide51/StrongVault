## Context

`kdbx-read` a validé KDBXKit **1.3.0** en lecture. Ce change active l'écriture, déjà
supportée par la lib (aucune crypto maison, CLAUDE.md §6). Faits techniques vérifiés dans le
checkout `.build/checkouts/KDBXKit` (à ne pas redécouvrir) :

- **Écriture** : `KDBXWriter.write(_ content:unlockData:regenerateSalts:)` (eager, vers un
  `OutputStream`/buffer) et `KDBXWriter.streamingWrite(to:content:binaries:unlockData:regenerateSalts:)`
  (chemin de production Apple, écrit vers une `URL`).
- **Base neuve** : `KDBXContent.makeEmpty(databaseName:kdf:)` (Argon2id par défaut) — **hors
  scope UI ici** (voir Non-Goals), utile seulement aux fixtures de test.
- **KDBX 4.x seulement** : les deux writers clampent la version à 4.1
  (`clampingFormatVersionToWritable`). Une base 3.1 est donc **migrée** à la sauvegarde ;
  `KDBXContent.legacyFormatNotice == .willMigrate(from:)` (posé par le reader legacy) sert à
  prévenir l'utilisateur.
- **Valeur secrète au repos** : `KDBX.ProtectedString.Value.unprotected(SecureBytes)` — c'est
  la forme « construite depuis du cleartext après édition », ré-encodée **chiffrée** dans le
  XML. `.protectedInMemory` est trompeur (clair sur disque, réservé aux fichiers XML non
  chiffrés) : **interdit** pour un secret. `.regular` = clair assumé (champ non protégé).
- **Sels** : `regenerateSalts: true` par défaut (obligation spec KDBX à chaque save) ;
  `false` seulement pour un round-trip **stable** de test (sels préservés + contenu reparsé
  identique — pas byte-identique : l'ordre du VariantDictionary KDF peut permuter).

## Goals / Non-Goals

**Goals :**
- Éditer une base ouverte (CRUD entrées/champs/groupes) et la sauvegarder **localement**.
- Durcir le contrat `StorageProvider.save` (fin du stub local) → fondation de `google-drive-sync`.
- Prouver l'**interop KeePassXC** de la base écrite (pas seulement la self-consistance).

**Non-Goals :**
- Upload/synchro Drive + conflit (`google-drive-sync`) ; merge/résolution.
- Création d'une base neuve dans l'UI ; déplacement d'entrées entre groupes ; pièces jointes ;
  icônes custom ; édition TOTP ; corbeille/undo ; AutoFill ; iPad/macOS.

## Decisions

- **Muter le `KDBXContent` conservé, jamais reconstruire depuis le domaine** — décision
  d'architecture centrale. Reconstruire un `KDBXContent` depuis `DatabaseDocument` (projection
  lossy) perdrait historique, icônes et champs non modélisés et laisserait `parserWarnings`
  non vides. La session d'édition Core mute l'arbre `KDBX.Group`/`KDBX.Entry` **en place**, à
  la manière du `TreeMutator`/`EntryFieldOps` du CLI KDBXKit. Le modèle domaine reste une
  **projection lecture seule** pour l'UI ; les mutations passent par des opérations Core
  dédiées (identifiées par UUID d'entrée/groupe).
- **Secret édité → `.unprotected`** (chiffré au repos), jamais `.protectedInMemory`. Écrit
  explicitement dans les scénarios de sécurité pour éviter le piège de nommage.
- **Bump `lastModificationTime` + snapshot historique** à chaque édition de champ (parité avec
  `entry set` du CLI) — testable en Core.
- **Sérialisation Core testable** : le round-trip `write` (eager, buffer `Data`) est le chemin
  prouvable en `swift test` sans device. `streamingWrite(to:)` (URL) est le chemin App réel.
- **`LocalStorageProvider.save`** (App, device) : écrit à l'emplacement pointé par le
  security-scoped bookmark et renvoie un `StorageMetadata` à jour. Écriture atomique côté
  fichier (temp + remplacement) pour éviter une base tronquée en cas d'échec.
- **Interop = source de vérité** : un **spike bloquant** (muter un golden file → `write` →
  `keepassxc-cli` open) valide l'interop **avant** le reste ; l'étape CI reprend ce round-trip.
  Justification : trois bugs réels (déclaration `<?xml version>`, séparateur de tags,
  normalisation key-file) n'ont été attrapés **que** par `keepassxc-cli` réel, jamais par le
  round-trip interne.

## Contrat `save` / `StorageMetadata` (cohérence inter-changes)

Le protocole `StorageProvider.save(_:expectedRemote:) -> StorageMetadata` existe déjà (le
Core définit aussi `StorageError.conflict(remote:)`, inutilisé pour l'instant). Ce change en
implémente la sémantique locale : écrire les octets, renvoyer des métadonnées à jour.
`expectedRemote` reste ignorable en local (pas de concurrence). `google-drive-sync`
**réutilisera exactement ce contrat** et introduira un **jeton de révision opaque** dans
`StorageMetadata` pour la détection de conflit — aucune signature ne change ici, ce qui garde
les deux changes cohérents. Note : `StorageMetadata`/`StorageProvider` relèvent de
`core-foundation` (non archivé), d'où l'absence de delta MODIFIED formel.

## Risks / Trade-offs

- [Corruption d'une base réelle par un writer buggé] → spike bloquant + CI interop
  `keepassxc-cli` avant d'exposer la moindre écriture ; écriture atomique côté fichier.
- [Perte de données non modélisées] → mutation en place du `KDBXContent`, jamais de
  reconstruction ; scénario de test dédié (champ inconnu préservé).
- [Migration 3.1→4.1 surprise] → avertissement UI **avant** écrasement via `legacyFormatNotice`.
- [Secret ré-encodé en clair par erreur de cas d'enum] → scénarios asserant `.unprotected`.

## Migration Plan

Additif : nouvelles opérations Core + `save` local effectif. Aucun format de données app
persisté ne change. Rollback = retrait des chemins d'écriture (la lecture reste intacte).

## Open Questions

- Ergonomie de l'API de mutation Core (opérations impératives vs. « edit builder ») — tranché
  à l'implémentation selon testabilité.
- Écriture atomique locale sur URL security-scoped : détails de remplacement de fichier à
  confirmer côté device (non prouvable en CI).
