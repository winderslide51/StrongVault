## 1. Dépendances

- [ ] 1.1 Aucune nouvelle dépendance : SDK `swift-google-drive-client` (darrarski) déjà présent
      sur la cible App ; `StorageError.conflict(remote:)` déjà défini dans le Core.

## 2. Core — jeton de révision, conflit, upload (Swift pur, testable via `swift test`)

- [ ] 2.1 Ajouter un `revisionToken: String?` opaque à `StorageMetadata` (optionnel,
      rétro-compatible ; `nil` en local — cohérent avec `kdbx-write`).
- [ ] 2.2 `DriveClient.metadata(fileId:)` renseigne `revisionToken` (headRevisionId/modifiedTime).
- [ ] 2.3 `GoogleDriveProvider` capture le `revisionToken` au `load()`.
- [ ] 2.4 `GoogleDriveProvider.save(_:expectedRemote:)` : relire la révision distante, comparer
      à `expectedRemote.revisionToken` ; mismatch ⇒ `StorageError.conflict(remote:)` sans upload ;
      match ⇒ upload + retour d'un `StorageMetadata` au **nouveau** jeton. Retirer le stub
      « lecture seule ».
- [ ] 2.5 Étendre `FakeDriveClient` : révision programmable + upload simulé qui incrémente la
      révision, pour exercer succès et conflit.

## 3. App — upload live, Keychain, UI conflit (device, build/test en CI)

- [ ] 3.1 `GoogleDriveClientLive` : implémenter l'upload réel (SDK darrarski) et exposer le
      jeton de révision (headRevisionId) dans `metadata`.
- [ ] 3.2 **Persistance des jetons OAuth en Keychain** avec
      `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (non-iCloud) ; refresh sur expiration ;
      révocation ⇒ `accessDenied`. Aucun jeton loggé (lève la réserve §5.5 de `google-drive`).
- [ ] 3.3 UI de conflit : message « la base a changé sur Drive », option recharger ; l'upload
      n'écrase jamais sans révision concordante.
- [ ] 3.4 **Montée de scope OAuth** : `GoogleDriveConfig.scope` passe de `drive.readonly` à
      `https://www.googleapis.com/auth/drive` (l'upload l'exige ; le fichier n'étant pas créé
      par l'app, `drive.file` ne le verrait pas). Nécessite une reconnexion (re-consentement)
      des sessions existantes.

## 4. Tests (Core, `swift test` via fakes)

- [ ] 4.1 Mapping métadonnées avec `revisionToken` non nul.
- [ ] 4.2 Capture du jeton au `load()` réutilisable comme `expectedRemote`.
- [ ] 4.3 Upload succès ⇒ nouveau `revisionToken` distinct.
- [ ] 4.4 Conflit : révision distante changée ⇒ `StorageError.conflict(remote:)`, aucun upload.
- [ ] 4.5 Révocation ⇒ `StorageError.accessDenied` (aucun jeton loggé).

## 5. Interop / CI

- [ ] 5.1 CI Core vert via `FakeDriveClient` (aucun réseau, aucun secret). L'OAuth réel n'est
      **pas** exercé en CI.
- [ ] 5.2 (Optionnel) réutiliser une base produite par `kdbx-write` comme charge utile d'upload
      simulé, pour prouver la cohérence du contrat `save` de bout en bout côté Core.

## 6. Device — provisioning & vérification manuelle (non prouvé par la CI)

- [ ] 6.1 Provisionner le **clientID/redirect OAuth** Google Cloud (Info.plist/xcconfig, hors
      repo, CLAUDE.md §6). Tâche device ; ne bloque ni CI ni Core.
- [ ] 6.2 Vérifier sur device : connexion Drive réelle, upload d'une base éditée, relance de
      l'app restaurant la session depuis le Keychain (`...ThisDeviceOnly`), scénario de conflit
      (modifier la base sur un autre appareil, tenter un upload ⇒ avertissement, pas d'écrasement).
- [ ] 6.3 Vérifier que les jetons ne sont **pas** synchronisés iCloud (attribut Keychain).
