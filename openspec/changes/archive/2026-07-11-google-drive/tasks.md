> **Portée « build only »** : le provider Drive est **entièrement testable en CI** derrière
> un `DriveClient` injecté (fake). La connexion réelle exige un client OAuth Google Cloud
> (clientID + redirect scheme, PKCE, **sans** secret pour une app iOS) provisionné côté
> device plus tard — **aucun secret dans le repo** (CLAUDE.md §6). **Pas d'interop KeePassXC**
> ici : ce change **n'écrit aucun format `.kdbx`**, il récupère des octets opaques depuis Drive.

## 1. Core — seam `DriveClient` (Swift pur, testable)

- [x] 1.1 Protocole Core `DriveClient` (Sendable) : `metadata(fileId:)` / `download(fileId:)`. Sans SDK.
- [x] 1.2 `FakeDriveClient` (cible de test) : octets/métadonnées scriptés + erreurs `notFound`/`network`.

## 2. Core — `GoogleDriveProvider` (Swift pur, testable)

- [x] 2.1 `GoogleDriveProvider<Client: DriveClient>: StorageProvider` (`{ client, fileId }`, `identifier = fileId`).
- [x] 2.2 `metadata()` délègue à `client.metadata(fileId:)` (mapping assuré côté client ; Drive
      n'expose pas la taille → `sizeBytes = nil`).
- [x] 2.3 `load()` délègue à `client.download(fileId:)`.
- [~] 2.4 Key file optionnel = second `download(fileId:)` distinct (démontré par deux providers en
      test) ; helper UI dédié + sélection du key file **reportés** (build-only).
- [x] 2.5 `save(_:expectedRemote:)` → `StorageError.unknown(...)` (lecture seule).
- [x] 2.6 Propagation des `StorageError` du client, sans réinterprétation.

## 3. App — client live & UI (device, buildé en CI)

- [x] 3.1 `swift-google-drive-client` (darrarski) ajouté à la cible **App** dans `project.yml` (Core sans SDK).
- [x] 3.2 `GoogleDriveClientLive: DriveClient` (SDK) : erreurs Drive → `StorageError`
      (404→notFound, notAuthorized→accessDenied, réseau→network, reste→unknown) + mapping métadonnées.
- [~] 3.3 OAuth : jetons (échange/refresh/persistance Keychain) délégués au SDK, jamais loggés.
      **Navigateur système + `onOpenURL`** (openURL par défaut du SDK) plutôt qu'`ASWebAuthenticationSession`
      — plus simple ; passage à ASWebAuthenticationSession possible en suivi.
- [~] 3.4 Sélection d'un `.kdbx` Drive (par `fileId`, jamais le contenu). Key file distinct **reporté**.
- [x] 3.5 Action « Ajouter depuis Drive » (menu + écran de connexion/liste) → `GoogleDriveProvider`
      via `AppModel.provider(for:)`, alimentant le flux d'ouverture existant.

## 4. Tests (Core, `swift test` via `FakeDriveClient`)

- [x] 4.1 `metadata()` : `fileId`→`identifier`, `name`→`displayName`, `modifiedTime`→`modifiedAt`.
- [x] 4.2 `load()` : présent → octets exacts ; absent → `StorageError.notFound`.
- [x] 4.3 Propagation d'erreurs : `network(_)` remonte tel quel.
- [x] 4.4 Key file : deux `download(fileId:)` distincts renvoient base et key file indépendamment.
- [x] 4.5 `save()` : lève `StorageError.unknown(...)`.

## 5. Vérification manuelle (device — non prouvée par la CI)

- [ ] 5.1 Une fois le clientID OAuth provisionné (hors repo) : se connecter à Google via
      `ASWebAuthenticationSession`, accorder le scope lecture.
- [ ] 5.2 Sélectionner un vrai `.kdbx` sur Drive, l'ajouter, l'ouvrir via le flux existant.
- [ ] 5.3 Sélectionner un `.kdbx` + key file distincts et ouvrir la base.
- [ ] 5.4 Vérifier le refresh de jeton (session longue) et la déconnexion (jetons effacés,
      aucun secret loggé).
- [ ] 5.5 **Bloquant avant release device (revue sécurité)** : auditer l'accessibilité Keychain
      effective des jetons OAuth stockés par le SDK — exiger `...ThisDeviceOnly` et **non**
      synchronisé iCloud (CLAUDE.md §3). Si le SDK ne le garantit pas, fournir un stockage jeton
      custom conforme avant tout branchement OAuth réel.
