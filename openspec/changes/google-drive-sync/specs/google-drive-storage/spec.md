## MODIFIED Requirements

### Requirement: Provider Drive pour un fichier .kdbx
Le système SHALL fournir un `GoogleDriveProvider` conforme à `StorageProvider`, construit à
partir d'un `DriveClient` injecté et d'un `fileId`, dont les métadonnées exposent
`identifier == fileId` **et un jeton de révision opaque** (`revisionToken`) renseigné par le
`DriveClient` (ex. `headRevisionId`/`modifiedTime` Drive).

#### Scenario: Métadonnées mappées depuis Drive avec jeton de révision
- **WHEN** on appelle `metadata()` sur un `GoogleDriveProvider` dont le `DriveClient` renvoie
  un fichier Drive (`name`, `modifiedTime`, `size`, révision) pour ce `fileId`
- **THEN** le `StorageMetadata` retourné a `identifier == fileId`, `displayName == name`,
  `modifiedAt == modifiedTime`, `sizeBytes == size` et un `revisionToken` non nul reflétant la
  révision distante

### Requirement: Authentification OAuth réelle avec jetons en Keychain
Le système SHALL rendre la connexion Google Drive effective via le SDK
`swift-google-drive-client` (OAuth PKCE, sans secret client), en **confinant le SDK à la couche
App** derrière `DriveClient` pour que le Core reste testable sans réseau ni secret. Les jetons
OAuth SHALL être persistés dans le **Keychain avec
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`** (non synchronisés iCloud). Un jeton d'accès
expiré SHALL être rafraîchi ; un jeton révoqué SHALL produire `StorageError.accessDenied`.
Aucun secret ni jeton SHALL être journalisé.

#### Scenario: Le Core fonctionne avec un client injecté sans OAuth
- **WHEN** on exerce `GoogleDriveProvider` avec un `FakeDriveClient` en `swift test`
- **THEN** `metadata()`, `load()`, l'upload et le fetch du key file fonctionnent sans aucun
  flux OAuth ni accès réseau réel

#### Scenario: Jeton révoqué
- **WHEN** le `DriveClient` signale une autorisation révoquée pour ce `fileId`
- **THEN** l'opération propage `StorageError.accessDenied`, sans qu'aucun jeton ne soit loggé

#### Scenario: Persistance des jetons hors iCloud (vérification device)
- **WHEN** l'utilisateur se connecte à Drive puis relance l'app sur le même appareil
- **THEN** la session est restaurée depuis le Keychain (`...ThisDeviceOnly`), sans re-login, et
  les jetons ne sont pas synchronisés vers un autre appareil via iCloud

## ADDED Requirements

### Requirement: Capture du jeton de révision au chargement
Le système SHALL capturer, au moment du `load()`, le jeton de révision distant courant et le
conserver dans le `StorageMetadata` associé à la base ouverte, afin de servir de référence pour
la détection de conflit à la sauvegarde.

#### Scenario: Le jeton capturé au load est disponible pour la sauvegarde
- **WHEN** on appelle `load()` sur un `GoogleDriveProvider` dont le `DriveClient` expose une
  révision distante
- **THEN** un `StorageMetadata` portant ce `revisionToken` est disponible et peut être passé
  ultérieurement comme `expectedRemote` de `save(_:expectedRemote:)`

### Requirement: Upload de la base vers Drive
Le système SHALL implémenter `GoogleDriveProvider.save(_:expectedRemote:)` en uploadant les
octets vers Drive via le `DriveClient` et en retournant un `StorageMetadata` à jour, dont un
**nouveau** `revisionToken` reflétant la révision distante après écriture.

#### Scenario: Upload réussi renvoie un nouveau jeton
- **WHEN** on appelle `save(_:expectedRemote:)` avec un `expectedRemote` dont le
  `revisionToken` correspond à la révision distante courante
- **THEN** les octets sont uploadés et le `StorageMetadata` retourné porte un nouveau
  `revisionToken` distinct de celui fourni

### Requirement: Détection de conflit avant upload
Le système SHALL comparer, avant tout upload, le `revisionToken` de `expectedRemote` à la
révision distante courante. S'ils diffèrent, le système SHALL lever
`StorageError.conflict(remote:)` **sans écraser** le fichier distant. S'ils correspondent (ou
si `expectedRemote` est absent en création), le système SHALL procéder à l'upload.

#### Scenario: Révision distante changée depuis le chargement
- **WHEN** la révision distante a changé depuis la capture (`expectedRemote.revisionToken`
  diffère de la révision courante) et qu'on appelle `save(_:expectedRemote:)`
- **THEN** `StorageError.conflict(remote:)` est levée, portant les métadonnées distantes
  courantes, et aucun octet n'est écrit sur Drive

#### Scenario: Révision inchangée autorise l'upload
- **WHEN** la révision distante est identique à `expectedRemote.revisionToken`
- **THEN** l'upload est effectué et un `StorageMetadata` à jour est retourné

## REMOVED Requirements

### Requirement: Écriture en lecture seule
**Raison** : l'upload Drive est désormais implémenté (exigences « Upload de la base vers
Drive » et « Détection de conflit avant upload »). Le stub `save()` lecture seule qui levait
`StorageError.unknown("lecture seule (kdbx-write)")` est retiré.
