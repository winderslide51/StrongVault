## Why

Le connecteur Google Drive est aujourd'hui en **lecture seule** (`google-drive-storage`,
archivé) : on télécharge un `.kdbx` mais `GoogleDriveProvider.save` est un stub typé, et
l'OAuth réel n'est pas branché (« build only »). Maintenant que `kdbx-write` a durci le
contrat `StorageProvider.save`, on peut **renvoyer la base modifiée vers Drive**.

L'upload vers un stockage partagé introduit un risque : un autre appareil peut avoir modifié
la base entre notre chargement et notre sauvegarde. Écraser à l'aveugle perdrait ces
changements — interdit par l'esprit de CLAUDE.md §4 (« jamais écraser à l'aveugle »). Décision
produit : **détecter + avertir**. Avant d'uploader, on compare un **jeton de révision distant**
(capturé au chargement) à la révision distante actuelle ; s'il a changé, on **refuse** et on
prévient, plutôt que d'écraser.

## What Changes

- **Jeton de révision (Core)** : `StorageMetadata` porte un **jeton opaque** (`revisionToken`,
  ex. `headRevisionId`/`modifiedTime` Drive). `DriveClient.metadata(fileId:)` le renseigne ;
  `GoogleDriveProvider` le **capture au `load()`**.
- **Upload avec détection de conflit** : `GoogleDriveProvider.save(_:expectedRemote:)`
  implémente l'upload réel (remplace le stub). Avant écriture, il compare
  `expectedRemote.revisionToken` à la révision distante courante : identiques ⇒ upload +
  nouveau jeton retourné ; différents ⇒ `StorageError.conflict(remote:)`, **aucun écrasement**.
- **OAuth réel (App)** : la connexion Drive devient effective (SDK `swift-google-drive-client`,
  PKCE, sans secret). Les **jetons OAuth sont persistés dans le Keychain**
  (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, **non-iCloud** — c'était la réserve §5.5 de
  `google-drive`). Jeton d'accès expiré ⇒ rafraîchi ; jeton révoqué ⇒ `StorageError.accessDenied`.
- **Key file** : reste un **fetch distinct** (inchangé).
- **UI conflit** : message explicite « la base a changé sur Drive » avec l'option de recharger.

Le provisioning du **clientID OAuth Google Cloud** (Info.plist/xcconfig, hors repo, CLAUDE.md
§6) reste une **tâche device** : il ne bloque ni la CI ni le Core, testés via `FakeDriveClient`.

## Capabilities

### Modified Capabilities
- `google-drive-storage`: passe de lecture seule à **synchro**. On **retire** l'exigence
  « Écriture en lecture seule », on **modifie** le mapping des métadonnées (jeton de révision)
  et l'authentification OAuth (réelle + Keychain), et on **ajoute** la capture du jeton au
  chargement, l'upload et la détection de conflit.

## Impact

- Aucune nouvelle dépendance : le SDK `swift-google-drive-client` (darrarski) est déjà présent
  (cible App).
- Dépendance de contrat : réutilise `StorageProvider.save` durci par `kdbx-write` ;
  `StorageError.conflict(remote:)` existe déjà dans le Core. Le jeton de révision ajouté à
  `StorageMetadata` (capability `core-foundation`, non archivée) reste cohérent avec
  `kdbx-write` (voir design.md) — aucun delta MODIFIED formel sur `core-foundation`.
- CI : Core vert via `FakeDriveClient` (upload simulé, conflit, jeton) ; aucun réseau, aucun
  secret. L'OAuth réel et la persistance Keychain restent une vérification device.
- **Non-goals** : synchro automatique en arrière-plan ; **résolution** de conflit / merge
  (on détecte + avertit seulement) ; file d'attente hors-ligne ; autres connecteurs cloud
  (iCloud, Dropbox, OneDrive, WebDAV) ; multi-comptes ; provisioning réel du client OAuth
  Google Cloud (device) ; AutoFill ; iPad / macOS.
