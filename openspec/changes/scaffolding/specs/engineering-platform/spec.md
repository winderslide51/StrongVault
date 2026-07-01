## ADDED Requirements

### Requirement: Développement piloté par les specs (OpenSpec)
Le projet SHALL utiliser OpenSpec comme source de vérité : toute évolution de comportement
passe par un change (`proposal`, `specs`, `design`, `tasks`) avant implémentation, puis est
archivée dans `openspec/specs/` après merge.

#### Scenario: Une feature démarre par une proposition
- **WHEN** on souhaite ajouter ou modifier un comportement
- **THEN** un change OpenSpec est créé et validé avant tout code applicatif

#### Scenario: Code sans spec refusé
- **WHEN** une pull request modifie un fichier `.swift` sous `Sources/`, `App/`, `Tests/`
  ou `AppTests/` sans modifier de change sous `openspec/changes/<nom>/`
- **THEN** le workflow `spec-guard` échoue et bloque le merge

### Requirement: Agents spécialisés à responsabilités séparées
Le projet SHALL définir quatre agents (`spec-architect`, `implementer`, `test-engineer`,
`pr-reviewer`) avec des périmètres d'outils distincts, l'agent qui revoit étant indépendant
de celui qui implémente.

#### Scenario: Revue indépendante
- **WHEN** une pull request est ouverte ou mise à jour
- **THEN** l'agent `pr-reviewer` publie une revue structurée (sécurité, conformité spec,
  correction, interop, qualité) sans avoir produit le code revu

### Requirement: Gates CI obligatoires avant merge
Le projet SHALL exiger, avant merge sur `main`, une CI verte (lint, tests Core, build/test
app iOS), une spec valide, et une revue.

#### Scenario: CI rouge bloque le merge
- **WHEN** le lint, les tests Core ou le build/test de l'app échouent
- **THEN** la pull request ne peut pas être mergée
