## ADDED Requirements

### Requirement: Provider Drive pour un fichier .kdbx
Le système SHALL fournir un `GoogleDriveProvider` conforme à `StorageProvider`, construit à
partir d'un `DriveClient` injecté et d'un `fileId`, dont les métadonnées exposent
`identifier == fileId`.

#### Scenario: Métadonnées mappées depuis Drive
- **WHEN** on appelle `metadata()` sur un `GoogleDriveProvider` dont le `DriveClient` renvoie
  un fichier Drive (`name`, `modifiedTime`, `size`) pour ce `fileId`
- **THEN** le `StorageMetadata` retourné a `identifier == fileId`, `displayName == name`,
  `modifiedAt == modifiedTime` et `sizeBytes == size`

### Requirement: Téléchargement des octets de la base
Le système SHALL implémenter `load()` en déléguant à `DriveClient.download(fileId:)`, en
retournant les octets présents et en traduisant l'absence en `StorageError.notFound`.

#### Scenario: Fichier présent renvoie ses octets
- **WHEN** le `DriveClient` possède des octets pour ce `fileId` et qu'on appelle `load()`
- **THEN** exactement ces octets sont retournés

#### Scenario: Fichier absent
- **WHEN** le `DriveClient` ne connaît pas ce `fileId` et qu'on appelle `load()`
- **THEN** `StorageError.notFound` est levée

### Requirement: Key file optionnel en fetch distinct
Le système SHALL récupérer un key file optionnel par un **second** `DriveClient.download(fileId:)`
distinct, sans re-télécharger la base.

#### Scenario: Fetch du key file séparé de la base
- **WHEN** une base a un key file sur Drive et qu'on demande le fetch du key file (fileId dédié)
- **THEN** les octets du key file sont retournés via un appel `download(fileId:)` distinct de
  celui de la base (aucun double-load de la base)

### Requirement: Traduction des erreurs Drive vers StorageError
Le système SHALL propager les échecs du `DriveClient` sous forme de `StorageError` typés
(`notFound`, `accessDenied`, `network`) sans les réinterpréter.

#### Scenario: Accès refusé
- **WHEN** le `DriveClient` lève `StorageError.accessDenied` pour ce `fileId`
- **THEN** `load()` (ou `metadata()`) propage `StorageError.accessDenied`

#### Scenario: Panne réseau
- **WHEN** le `DriveClient` lève `StorageError.network(_)`
- **THEN** l'erreur `StorageError.network(_)` est propagée telle quelle

### Requirement: Écriture en lecture seule
Le système SHALL refuser `save(_:expectedRemote:)` en v1 par une erreur typée explicite,
l'upload étant reporté à `kdbx-write`.

#### Scenario: save() est un stub typé
- **WHEN** on appelle `save(_:expectedRemote:)` sur un `GoogleDriveProvider`
- **THEN** `StorageError.unknown("lecture seule (kdbx-write)")` est levée

### Requirement: Authentification OAuth injectable
Le système SHALL confiner l'OAuth Google et le SDK à la couche App derrière `DriveClient`, de
sorte que le Core soit testable sans réseau ni secret, et que les jetons soient rafraîchis ou
invalidés sans être exposés.

#### Scenario: Le Core fonctionne avec un client injecté sans OAuth
- **WHEN** on exerce `GoogleDriveProvider` avec un `FakeDriveClient` en `swift test`
- **THEN** `metadata()`, `load()` et le fetch du key file fonctionnent sans aucun flux OAuth ni
  accès réseau réel

#### Scenario: Refresh de jeton côté device (vérification manuelle)
- **WHEN** la session device est longue et le jeton d'accès expire, le SDK effectuant le refresh
- **THEN** les appels Drive suivants réussissent sans re-login, et si le refresh échoue les
  jetons sont invalidés sans qu'aucun secret ne soit loggé
