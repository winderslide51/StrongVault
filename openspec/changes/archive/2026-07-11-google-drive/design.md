## Context

`kdbx-read` a posé `DatabaseDocument` (ouverture d'octets `.kdbx` + identifiants) et
`LocalStorageProvider` (accès local via `StorageProvider`). Le protocole `StorageProvider`
(Core, `core-foundation`) est déjà fixé :

- `metadata() async throws -> StorageMetadata`
- `load() async throws -> Data`
- `save(_ data: Data, expectedRemote: StorageMetadata?) async throws -> StorageMetadata`
- `StorageMetadata { identifier, displayName, modifiedAt, sizeBytes }`
- `StorageError { notFound, accessDenied, conflict(remote:), network(String), unknown(String) }`

Il faut une seconde implémentation, Google Drive, sans faire entrer le SDK Google (ni de
secret OAuth) dans le Core ni dans la CI. Le SDK retenu est `swift-google-drive-client`
(darrarski), qui expose un `GoogleDriveClient` et gère l'échange/refresh des jetons.

## Goals / Non-Goals

**Goals:**
- Télécharger un `.kdbx` (et un key file optionnel) depuis Drive derrière `StorageProvider`,
  pour réutiliser tel quel le flux d'ouverture de `kdbx-read`.
- Rendre le provider **entièrement testable en `swift test`** (mapping, erreurs, key file)
  via un `DriveClient` injecté, sans réseau ni secret.
- Garder le Core sans dépendance SDK ; confiner le SDK Google et l'OAuth à la couche App.

**Non-Goals:**
- Upload / écriture Drive (`kdbx-write`), autres connecteurs cloud, sync/conflit distant,
  AutoFill, iPad/macOS, provisioning réel du client OAuth (device, plus tard).

## Decisions

- **Seam `DriveClient` (Core, Sendable)** : `metadata(fileId:) async throws -> StorageMetadata`
  et `download(fileId:) async throws -> Data`. C'est la seule frontière que le Core connaît du
  monde Drive. Le mapping des champs Drive (`name`→`displayName`, `modifiedTime`→`modifiedAt`,
  `size`→`sizeBytes`) est fait **dans le client** pour que le Core reste agnostique du SDK.
  Alternative écartée : injecter directement le `GoogleDriveClient` du SDK dans le Core → ferait
  fuiter la dépendance SDK dans le package pur et casserait `swift test` sans device.
- **`GoogleDriveProvider: StorageProvider`** enveloppe `{ client: DriveClient, fileId: String }`.
  `metadata()` délègue à `client.metadata(fileId:)` ; `load()` délègue à `client.download(fileId:)`.
  `identifier = fileId` (stable, réutilisable pour rouvrir la même base).
- **Key file = fetch distinct** : quand une base a un key file sur Drive, on ne fait pas un
  double-load de la base ; on émet un **second** `download(fileId:)` sur le fileId du key file.
  Le provider peut exposer un helper de fetch du key file, mais la combinaison base+key file
  reste au flux d'ouverture (`DatabaseDocument`), pas au provider. Alternative écartée : encoder
  le key file dans le `StorageProvider` de la base → couplerait deux fichiers distincts.
- **Traduction d'erreurs** : le `DriveClient` (couche App) traduit les échecs Drive en
  `StorageError` — 404 → `notFound`, 401/403 → `accessDenied`, panne réseau → `network(_)`,
  reste → `unknown(_)`. Le provider propage sans réinterpréter. Testable via un fake qui lève
  les cas voulus.
- **`save()` lecture seule** : `GoogleDriveProvider.save(...)` lève
  `StorageError.unknown("lecture seule (kdbx-write)")`. Typé et explicite plutôt que silencieux ;
  l'upload arrivera avec `kdbx-write`.
- **OAuth confiné à l'App** : `GoogleDriveClientLive` (App) enveloppe le SDK ; l'OAuth passe par
  `ASWebAuthenticationSession` avec **PKCE** et **sans secret client** (app iOS publique). Le SDK
  gère l'échange initial, le **refresh** et la persistance des jetons (hors repo). Scope par
  défaut : lecture (`drive.readonly` ou file-picker) pour ouvrir une base existante.
- **Dépendance ciblée** : `swift-google-drive-client` déclaré sur la cible **App** dans
  `project.yml` uniquement ; `Package.swift` (Core) reste inchangé.

## Risks / Trade-offs

- [Provisioning OAuth différé bloque le test réel] → accepté : le contrat Core est prouvé par
  `FakeDriveClient` ; le device sera vérifié manuellement une fois le clientID fourni.
- [Divergence entre `FakeDriveClient` et le SDK réel] → on modélise le fake d'après les cas Drive
  réels (404/401/403/réseau) ; la vérification device confirme le mapping live.
- [Jetons OAuth = secrets] → jamais dans le repo ni loggés ; persistance déléguée au SDK
  (Keychain/stockage sécurisé), invalidation au refresh échoué (CLAUDE.md §3/§6).
- [Scope trop large] → on demande la **lecture** seule en v1 ; l'upload (scope écriture) est
  repoussé à `kdbx-write`.
- [Grandes bases / timeout réseau] → `download` renvoie les octets complets en mémoire (comme le
  local) ; le streaming n'est pas nécessaire pour des `.kdbx` typiques.

## Migration Plan

Additif : nouveau protocole Core + nouveau provider + nouvelle implémentation App + une
dépendance SDK sur la cible App. Aucun changement de contrat `StorageProvider`. Rollback =
retrait du provider, du client live, de l'écran « Ajouter depuis Drive » et de la dépendance
`project.yml` ; aucune donnée persistée par ce change hormis les jetons gérés par le SDK
(effaçables via déconnexion).

Pas d'interop KeePassXC ici : **ce change n'écrit aucun format `.kdbx`** — il ne fait que
récupérer des octets opaques depuis Drive. Le round-trip KeePassXC reste porté par les changes
qui lisent/écrivent réellement le format (`kdbx-read`, `kdbx-write`).

## Open Questions

- Sélection du fichier : file-picker Google Drive natif vs listage via l'API `files.list` — à
  trancher selon l'ergonomie du SDK et le scope minimal (proposé : file-picker si dispo).
- Le key file Drive doit-il être mémorisé (fileId persistant) à côté du fileId de la base pour
  réouverture sans re-sélection ? (proposé : oui, sans stocker le contenu, seulement les fileId).
- Faut-il un cache local des octets téléchargés pour l'ouverture hors-ligne ? (repoussé, hors
  périmètre lecture v1).
