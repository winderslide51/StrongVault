# StrongClone

Client **KeePass (`.kdbx`)** pour **iPhone** — clone fidèle mais simplifié de StrongBox :
connecteur **Google Drive** (+ local), **déverrouillage FaceID**, SwiftUI natif.
*« StrongClone » est un codename de développement — voir la note branding dans `CLAUDE.md`.*

Ce dépôt est construit selon une méthode **spec-driven (OpenSpec)** et un **pipeline agentic
GitHub Actions** (agents spécialisés : conception, implémentation, tests, revue de PR).

## Structure

```
CLAUDE.md                 Constitution du projet (règles pour humains + agents)
openspec/                 Specs (vérité) & changes (propositions) — source de vérité
Package.swift             Package SwiftPM : cible Core (Swift pur, testable sans simulateur)
Sources/StrongCloneCore/  Database / Storage / Security
Tests/                    Tests XCTest du Core
App/                      App SwiftUI iPhone (cible Xcode)
project.yml               Spéc XcodeGen → génère StrongClone.xcodeproj (non commité)
.claude/agents/           spec-architect · implementer · test-engineer · pr-reviewer
.github/workflows/        ci · claude-review · claude-dispatch · spec-guard
```

## Développement

### Core
```bash
swift build          # compiler le package Core (OK avec Command Line Tools seuls)
swift test           # tests unitaires + round-trip crypto — nécessite Xcode complet
                     # (XCTest absent des Command Line Tools) ; sinon exécutés en CI
```

### App iOS (nécessite Xcode complet — CI ou poste avec Xcode)
```bash
brew install xcodegen swiftlint    # une fois
xcodegen generate                  # génère StrongClone.xcodeproj
open StrongClone.xcodeproj
```

## Workflow d'une feature (spec-driven)

```
/opsx:propose "…"   → change OpenSpec (proposal/specs/design/tasks)
                      validation humaine (PR de spec)
/opsx:apply         → implémentation + tests selon tasks.md
PR → CI + revue Claude automatique + revue humaine → merge
/opsx:archive       → openspec/specs/ mis à jour (nouvelle vérité)
```

Voir `CLAUDE.md` pour les règles complètes (sécurité, archi, qualité).
