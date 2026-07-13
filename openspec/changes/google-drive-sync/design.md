## Context

`google-drive-storage` (archivé) a posé un `GoogleDriveProvider` **lecture seule** derrière un
`DriveClient` injectable, avec `GoogleDriveClientLive` (SDK darrarski) confiné à l'App. Deux
points restaient ouverts : `save()` stub (« lecture seule (kdbx-write) ») et OAuth « build
only » (réserve §5.5 : persistance des jetons hors iCloud). `kdbx-write` a depuis durci
`StorageProvider.save`. Ce change active l'upload **avec détection de conflit**.

État vérifié du Core (`Sources/StrongCloneCore/Storage/`) :
- `StorageProvider.save(_:expectedRemote:) -> StorageMetadata` existe déjà (le paramètre
  `expectedRemote` est précisément le crochet de l'écriture conditionnelle).
- `StorageError.conflict(remote: StorageMetadata)` **existe déjà** — inutilisé jusqu'ici, il
  devient le canal de conflit.
- `DriveClient` expose `metadata(fileId:)` et `download(fileId:)` ; `GoogleDriveClientLive`
  mappe déjà `modifiedTime` et traduit les erreurs SDK → `StorageError`.

## Goals / Non-Goals

**Goals :**
- Uploader la base modifiée vers Drive via le contrat `save` de `kdbx-write`.
- **Détecter + avertir** en cas de divergence distante (jamais écraser à l'aveugle, CLAUDE.md §4).
- OAuth réel + persistance des jetons en Keychain `...ThisDeviceOnly` (non-iCloud).

**Non-Goals :**
- Résolution/merge de conflit ; synchro auto en arrière-plan ; file hors-ligne ;
  autres connecteurs cloud ; multi-comptes ; provisioning OAuth Google Cloud (device) ;
  AutoFill ; iPad/macOS.

## Decisions

- **Jeton de révision opaque dans `StorageMetadata`** (`revisionToken: String?`). Source :
  `headRevisionId` de Drive (ou, à défaut, `modifiedTime`) — opaque du point de vue du Core,
  qui se contente de le comparer. `DriveClient.metadata(fileId:)` le renseigne ;
  `GoogleDriveProvider` le **capture au `load()`** pour servir de base à la comparaison.
- **Détection de conflit côté provider** : `save(_:expectedRemote:)` relit la révision distante
  courante et la compare à `expectedRemote.revisionToken`. Mismatch ⇒ `StorageError.conflict(remote:)`
  (métadonnées distantes courantes jointes pour l'UI). Match ⇒ upload, puis retour d'un
  `StorageMetadata` avec le **nouveau** jeton. Décision produit assumée : **détecter + avertir**,
  pas de merge.
- **Testabilité Core** : toute la logique jeton/conflit/upload est prouvée via `FakeDriveClient`
  (révision programmable, upload simulé qui incrémente la révision). Aucun réseau, aucun secret.
- **OAuth réel confiné à l'App** : `GoogleDriveClientLive` gère la connexion (PKCE, sans secret).
  **Persistance des jetons en Keychain avec `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`**
  (non-iCloud) — lève la réserve §5.5. Expiré ⇒ refresh SDK ; révoqué ⇒ `accessDenied`.
- **Provisioning device** : clientID/redirect OAuth (Info.plist/xcconfig, hors repo, CLAUDE.md
  §6). Ne bloque ni la CI ni le Core (fakes) — c'est une tâche device explicite.

## Cohérence du contrat `save` / `StorageMetadata` avec `kdbx-write`

Les deux changes partagent la **même** signature `save(_:expectedRemote:) -> StorageMetadata`.
`kdbx-write` l'implémente pour le local (écriture inconditionnelle, `expectedRemote` ignorable)
et renvoie des métadonnées à jour. `google-drive-sync` l'implémente pour Drive en **exploitant**
`expectedRemote.revisionToken` pour la comparaison conditionnelle. Le champ `revisionToken`
ajouté à `StorageMetadata` est **rétro-compatible** (optionnel, `nil` en local) : aucune
signature ni exigence de `kdbx-write` n'est cassée. `StorageMetadata`/`StorageProvider`
relèvent de `core-foundation` (non archivé), d'où l'absence de delta MODIFIED formel là-dessus.

## Risks / Trade-offs

- [Écrasement silencieux d'une modif distante] → comparaison de révision **avant** upload ;
  `StorageError.conflict` + UI de rechargement. Jamais d'upload sans vérification.
- [Fenêtre de course entre relecture et upload] → limite acceptée en v1 (détection best-effort,
  pas de verrou distant/If-Match transactionnel) ; documentée. Amélioration (ETag/If-Match)
  hors scope.
- [Jetons OAuth exposés/synchronisés] → Keychain `...ThisDeviceOnly`, jamais loggés, jamais
  dans le repo.

## Migration Plan

Additif côté contrat (`revisionToken` optionnel). Le stub `save()` lecture seule est retiré et
remplacé par l'upload conditionnel. Rollback = réactiver le stub (retour lecture seule) sans
impact sur la lecture ni sur `kdbx-write`.

## Open Questions

- Source exacte du jeton : `headRevisionId` (préféré, monotone) vs `modifiedTime` (fallback) —
  tranché à l'implémentation selon ce que le SDK darrarski expose de façon fiable.
- Conflit en **création** (fichier distant apparu entre-temps) : traité comme conflit si un
  fichier de même identité existe déjà — à confirmer côté device.
