## ADDED Requirements

### Requirement: Navigation dans les groupes et entrées
Le système SHALL permettre de parcourir l'arborescence des groupes et de lister les entrées
d'un groupe après ouverture d'une base.

#### Scenario: Lister le contenu d'un groupe
- **WHEN** l'utilisateur ouvre un groupe
- **THEN** ses sous-groupes et ses entrées sont affichés

#### Scenario: Descendre dans un sous-groupe
- **WHEN** l'utilisateur sélectionne un sous-groupe
- **THEN** le contenu de ce sous-groupe est affiché

### Requirement: Détail d'une entrée
Le système SHALL afficher le détail d'une entrée : champs standards, champs personnalisés,
pièces jointes (liste) et code TOTP le cas échéant ; le mot de passe est masqué par défaut.

#### Scenario: Consulter et révéler
- **WHEN** l'utilisateur ouvre une entrée
- **THEN** le mot de passe est masqué jusqu'à une action explicite de révélation

#### Scenario: Copier un champ
- **WHEN** l'utilisateur copie l'identifiant ou le mot de passe
- **THEN** la valeur est placée dans le presse-papier (auto-effacement traité dans `polish`)

#### Scenario: Code TOTP conforme
- **WHEN** une entrée contient une configuration TOTP
- **THEN** le code affiché correspond aux vecteurs de référence RFC 6238 pour l'instant donné

#### Scenario: Pièces jointes listées
- **WHEN** une entrée possède des pièces jointes
- **THEN** leurs noms et tailles sont listés
