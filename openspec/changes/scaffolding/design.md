## Context

Machine locale = Command Line Tools uniquement (pas d'Xcode complet) : on peut compiler le
package Core (`swift build`) mais pas exécuter XCTest ni builder l'app iOS localement. Les
tests et builds iOS tournent donc en CI (runners macOS avec Xcode). Cette contrainte oriente
l'architecture vers un Core en Swift pur maximalement testable et une app fine.

## Goals / Non-Goals

**Goals:**
- Établir la méthode spec-driven (OpenSpec) et l'appliquer dès ce change (dogfooding).
- Fournir un Core compilable + testable et un squelette d'app générable.
- Automatiser la qualité : lint, tests, revue agentique, garde-fou anti-drift.

**Non-Goals:**
- Aucune fonctionnalité produit réelle (ouverture .kdbx, FaceID, Drive) — changes suivants.
- Pas de dépendance externe Swift encore (KDBXKit/Drive introduits plus tard).
- Pas d'AutoFill, iPad, macOS.

## Decisions

- **Core en package SwiftPM séparé** plutôt que tout dans l'app : testable sans simulateur,
  frontière nette App→Core. Alternative écartée : tout dans le target Xcode (non testable
  hors Xcode complet).
- **XcodeGen (`project.yml`)** plutôt que `.xcodeproj` commité : évite les conflits de
  merge sur le pbxproj et rend le projet reproductible en CI.
- **Deux modes d'agents** : sous-agents Claude Code locaux (`.claude/agents`) pour
  concevoir/implémenter, et `claude-code-action@v1` en CI pour la revue et le mode `@claude`.
- **spec-guard** impose « pas de code Swift sans change OpenSpec » (ce change se documente
  donc lui-même).

## Risks / Trade-offs

- [Tests non exécutables en local] → couverts en CI ; `swift build` sert de smoke test local.
- [Noms de simulateurs volatils entre images CI] → sélection dynamique du 1er iPhone dispo.
- [Coût des agents CI] → revue limitée à `opened`/`synchronize`, concurrency pour annuler
  les runs obsolètes.

## Migration Plan

Premier change : rien à migrer. Merge sur `main` puis `openspec archive scaffolding` pour
publier les specs comme vérité courante.

## Open Questions

- Nom/branding public définitif (« StrongClone » est un codename) — hors périmètre technique.
