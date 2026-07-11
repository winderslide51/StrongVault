## ADDED Requirements

### Requirement: Enrôlement de la clé composite après déverrouillage manuel
Le système SHALL, après un déverrouillage manuel réussi d'une base, pouvoir stocker la clé
composite 32 octets derrière la biométrie via le `MasterKeyStore`, indexée par
l'identifiant de la base, et SHALL refuser d'enrôler une clé dont la longueur n'est pas de
32 octets.

#### Scenario: Enrôlement d'une clé composite valide
- **WHEN** on enrôle une base en fournissant une clé composite de 32 octets
- **THEN** le `MasterKeyStore` contient exactement ces 32 octets pour l'identifiant de la base

#### Scenario: Rejet d'une clé de longueur invalide
- **WHEN** on tente d'enrôler une clé dont la longueur n'est pas de 32 octets
- **THEN** une erreur typée « secret invalide » est levée et rien n'est stocké

### Requirement: Déverrouillage biométrique par récupération de la clé composite
Le système SHALL récupérer la clé composite stockée pour une base et produire un
`DatabaseCredential` porteur de `rawKeyData` permettant de rouvrir la base sans ressaisir le
mot de passe, sans jamais mémoriser ni exposer le mot de passe maître.

#### Scenario: Récupération réussie d'une base enrôlée
- **WHEN** on demande le déverrouillage d'une base préalablement enrôlée
- **THEN** un `DatabaseCredential` porteur du `rawKeyData` d'origine (32 octets) est retourné

#### Scenario: La clé composite rouvre la base sans mot de passe
- **WHEN** le `DatabaseCredential` récupéré est passé à l'ouverture de la base
- **THEN** la base s'ouvre correctement alors qu'aucun mot de passe n'a été fourni ni mémorisé

### Requirement: Repli sur la saisie du mot de passe si non enrôlé
Le système SHALL distinguer une base non enrôlée (aucun secret stocké) d'une erreur : dans
le cas non enrôlé, la récupération SHALL retourner l'absence de secret pour déclencher le
repli sur la saisie manuelle du mot de passe.

#### Scenario: Base non enrôlée
- **WHEN** on demande le déverrouillage d'une base qui n'a jamais été enrôlée
- **THEN** l'absence de secret (`nil`) est retournée, sans erreur, indiquant le repli mot de passe

### Requirement: Robustesse face à un secret stocké invalide
Le système SHALL signaler par une erreur typée, sans planter et sans divulguer de secret, le
cas où un secret est présent en stockage mais ne correspond pas à une clé composite de 32
octets.

#### Scenario: Secret stocké de longueur inattendue
- **WHEN** le stockage contient pour une base un secret dont la longueur n'est pas de 32 octets
- **THEN** une erreur typée « secret stocké invalide » est retournée (pas de crash, pas de secret exposé)

### Requirement: Désactivation du déverrouillage biométrique
Le système SHALL permettre de désactiver le déverrouillage biométrique d'une base en
supprimant son secret du `MasterKeyStore`.

#### Scenario: Désactivation puis récupération
- **WHEN** on désactive le déverrouillage biométrique d'une base enrôlée puis on demande sa récupération
- **THEN** l'absence de secret (`nil`) est retournée, indiquant le repli mot de passe

### Requirement: Purge mémoire des secrets au verrouillage
Le système SHALL, lorsque `AutoLockPolicy` décide du verrouillage (passage en arrière-plan
ou dépassement du délai d'inactivité), relâcher l'état déverrouillé et libérer les secrets
déchiffrés en mémoire.

#### Scenario: Verrouillage sur décision de la politique
- **WHEN** une base est déverrouillée et que `AutoLockPolicy.shouldLock` devient `true`
- **THEN** l'état déverrouillé du service est relâché et les secrets déchiffrés ne sont plus retenus

### Requirement: Invalidation du secret au changement de biométrie
Le secret biométrique SHALL être protégé par un contrôle d'accès `.biometryCurrentSet` de
sorte qu'un changement de la biométrie enrôlée sur l'appareil invalide le secret et force un
repli sur la saisie du mot de passe puis un ré-enrôlement.

#### Scenario: Biométrie modifiée sur l'appareil
- **WHEN** la biométrie enrôlée de l'appareil est modifiée après l'enrôlement d'une base
- **THEN** le secret stocké est invalidé et la récupération biométrique échoue, imposant le repli mot de passe et un ré-enrôlement
