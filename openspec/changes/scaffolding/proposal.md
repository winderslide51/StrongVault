## Why

Le projet part de zéro. Avant toute feature produit, il faut établir la **plateforme de
développement** (spec-driven + pipeline agentic) et le **squelette du Core** afin que
chaque fonctionnalité suivante se construise de façon reproductible, testée et revue.

## What Changes

- Mise en place d'OpenSpec comme source de vérité (dossiers `openspec/specs` & `changes`).
- Constitution du projet dans `CLAUDE.md` (archi en couches, sécurité, qualité).
- Package SwiftPM `StrongCloneCore` (Swift pur, testable sans simulateur) avec modèles
  domaine, abstraction de stockage et politique de verrouillage automatique.
- Squelette de l'app iOS SwiftUI (iPhone) généré par XcodeGen (`project.yml`).
- Quatre agents spécialisés (`.claude/agents/`) : spec-architect, implementer,
  test-engineer, pr-reviewer.
- Pipeline GitHub Actions : `ci.yml`, `claude-review.yml`, `claude-dispatch.yml`,
  `spec-guard.yml`, + configs lint (`.swiftlint.yml`, `.swift-format`).

## Capabilities

### New Capabilities
- `engineering-platform`: méthode spec-driven, agents spécialisés et gates CI/CD
  garantissant « pas de code sans spec, pas de merge sans CI verte + revue ».
- `core-foundation`: modèles domaine KeePass, abstraction de stockage et politique de
  verrouillage automatique du package Core, testables sans device.

### Modified Capabilities
<!-- Aucune : premier change du projet. -->

## Impact

- Dépendances : OpenSpec (CLI), XcodeGen, SwiftLint/swift-format, GitHub Actions,
  `anthropics/claude-code-action@v1`. Secret requis : `ANTHROPIC_API_KEY`.
- Code : création de `Sources/StrongCloneCore`, `Tests/`, `App/`, `AppTests/`.
- Aucune dépendance externe Swift encore (KDBXKit / Drive ajoutés dans leurs changes).
