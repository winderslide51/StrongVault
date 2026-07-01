## ADDED Requirements

### Requirement: Modèles domaine KeePass indépendants du format
Le package Core SHALL exposer des modèles domaine (`Group`, `Entry`, `CustomField`,
`TotpConfig`, `Attachment`) `Sendable`, indépendants du format de fichier, sans dépendance
UIKit/SwiftUI.

#### Scenario: Aplatissement récursif des entrées
- **WHEN** un `Group` contient des entrées et des sous-groupes imbriqués
- **THEN** `allEntriesRecursive` retourne toutes les entrées de l'arborescence

### Requirement: Abstraction de stockage avec détection de conflit
Le package Core SHALL définir un protocole `StorageProvider` (`metadata`, `load`, `save`)
permettant une écriture conditionnelle : si la version distante attendue diffère, une
erreur `StorageError.conflict` est levée.

#### Scenario: Round-trip lecture/écriture
- **WHEN** on sauvegarde des données puis on les recharge via un `StorageProvider`
- **THEN** les octets rechargés sont identiques à ceux sauvegardés

#### Scenario: Conflit détecté sur métadonnée périmée
- **WHEN** on sauvegarde en fournissant une métadonnée distante qui ne correspond plus à
  l'état courant
- **THEN** `StorageError.conflict` est levée avec les métadonnées distantes courantes

### Requirement: Politique de verrouillage automatique
Le package Core SHALL fournir une `AutoLockPolicy` (logique pure) décidant du reverrouillage
selon un délai d'inactivité et/ou le passage en arrière-plan.

#### Scenario: Verrouillage après délai
- **WHEN** le délai d'inactivité configuré est atteint
- **THEN** `shouldLock` retourne `true`

#### Scenario: Verrouillage à l'arrière-plan
- **WHEN** `lockOnBackground` est actif et l'app passe en arrière-plan
- **THEN** `shouldLock` retourne `true`
