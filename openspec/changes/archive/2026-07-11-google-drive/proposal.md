## Why

Aujourd'hui l'app n'ouvre que des `.kdbx` locaux (`LocalStorageProvider`, change
`kdbx-read`). Le connecteur produit de StrongClone est **Google Drive** : la plupart des
utilisateurs gardent leur base sur Drive et veulent la rouvrir depuis l'iPhone sans la
copier à la main. Ce change ajoute une seconde implémentation de `StorageProvider` qui
**télécharge** un `.kdbx` (et un key file optionnel) depuis Drive, pour l'ouvrir ensuite
via le flux existant (`DatabaseDocument`). C'est le seul connecteur cloud prévu (CLAUDE.md).

Le vrai OAuth Google exige un client OAuth (clientID + redirect scheme, PKCE, **sans**
secret pour une app iOS native) qui sera provisionné côté device plus tard — aucun secret
ne peut entrer dans le repo (CLAUDE.md §6). On rend donc le connecteur **entièrement
testable en CI** derrière un client injecté (fake) : mapping des métadonnées, traduction
des erreurs et fetch du key file sont prouvés par `swift test`, tandis que l'OAuth réel et
le réseau réel restent une vérification device/manuelle.

## What Changes

- Nouveau protocole Core injectable **`DriveClient`** (Sendable) : `metadata(fileId:)` et
  `download(fileId:)`. Il isole le SDK Google du Core (le Core reste sans dépendance SDK).
- Nouveau **`GoogleDriveProvider: StorageProvider`** (Core) enveloppant `{ client, fileId }` :
  `metadata()` mappe les champs Drive (`name`→`displayName`, `modifiedTime`→`modifiedAt`,
  `size`→`sizeBytes`, `identifier = fileId`) ; `load()` télécharge les octets.
- **Key file optionnel** = **fetch distinct** (un second `download(fileId:)` sur le fileId du
  key file), pas un double-load de la base. Le mélange base + key file reste au flux d'ouverture.
- **Traduction d'erreurs** Drive → `StorageError` (`notFound`, `accessDenied`, `network`).
- **`save()`** : lecture seule en v1 → renvoie `StorageError.unknown("lecture seule (kdbx-write)")`.
- **App (device, build-only en CI)** : `GoogleDriveClientLive` enveloppant le SDK
  `swift-google-drive-client` (darrarski) et conforme à `DriveClient` ; OAuth via
  `ASWebAuthenticationSession` (le SDK gère l'échange + refresh des jetons, persistés hors
  repo) ; sélection d'un fichier Drive (+ key file) ; action « Ajouter depuis Drive » dans la
  liste des bases.
- Dépendance `swift-google-drive-client` ajoutée à la **cible App uniquement** (`project.yml`).

## Capabilities

### New Capabilities
- `google-drive-storage`: récupération d'un `.kdbx` (et key file optionnel) depuis Google
  Drive derrière `StorageProvider`, avec métadonnées mappées, erreurs traduites, client
  OAuth injectable, et `save()` lecture seule typé.

### Modified Capabilities
<!-- Aucune capacité de spec existante modifiée. `GoogleDriveProvider` implémente le
     protocole `StorageProvider` déjà défini par le scaffolding (`core-foundation`, non
     archivé) sans en changer le contrat. Aucun delta MODIFIED requis. -->

## Impact

- Dépendance externe : `swift-google-drive-client` (SwiftPM) sur la **cible App seulement**.
  Le package Core reste sans dépendance SDK (portabilité + `swift test` sans device).
- CI : build de l'app avec la nouvelle dépendance ; tests Core via `FakeDriveClient`
  (aucun réseau, aucun secret). Le vrai OAuth n'est **pas** exercé en CI.
- Provisioning différé (device) : clientID OAuth Google + redirect URL scheme, à fournir hors
  repo au moment du branchement device. Scope OAuth par défaut : **lecture**
  (`drive.readonly` ou file-picker Drive) pour voir une base pré-existante.
- Critères vérifiables : chaque exigence de `google-drive-storage` porte ≥1 scénario Core
  prouvé par `FakeDriveClient` en `swift test` (mapping, `notFound`, `accessDenied`,
  `network`, fetch key file, `save()` typé), les autres étant marqués vérification device.
- **Non-goals** : écriture/upload vers Drive (`kdbx-write`) ; autres connecteurs cloud
  (iCloud, Dropbox, OneDrive, WebDAV) ; sélection multi-comptes / multi-bases avancée ;
  synchronisation automatique / résolution de conflit distant ; AutoFill ; iPad / macOS ;
  provisioning réel du client OAuth Google Cloud (fait plus tard, côté device).
