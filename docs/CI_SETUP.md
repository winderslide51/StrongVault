# Mise en route CI/CD & pipeline agentic

## 1. Secrets GitHub (Settings → Secrets and variables → Actions)

| Secret | Usage |
|---|---|
| `ANTHROPIC_API_KEY` | Agents Claude dans `claude-review.yml` et `claude-dispatch.yml` |

Alternative : installer l'app GitHub officielle avec `claude /install-github-app`
(configure le secret et l'app automatiquement — nécessite d'être admin du repo).

## 2. Workflows

| Workflow | Déclencheur | Rôle |
|---|---|---|
| `ci.yml` | push / PR sur `main` | Gate mécanique : SwiftLint + swift-format, `swift test` (Core), `xcodebuild test` (app, simulateur iPhone) |
| `claude-review.yml` | PR `opened`/`synchronize` | Agent **pr-reviewer** : revue automatique structurée |
| `claude-dispatch.yml` | `@claude` en commentaire/issue | Mode interactif (corrections/implémentation à la demande) |
| `spec-guard.yml` | PR sur `main` | `openspec validate` + refuse le code Swift sans change OpenSpec |

## 3. Branch protection (`main`)

Settings → Branches → Add rule sur `main` :
- ✅ Require a pull request before merging (au moins **1 review humaine**).
- ✅ Require status checks to pass : `CI / lint`, `CI / core-tests`, `CI / app-build`,
  `Spec Guard / spec-guard`.
- ✅ Require conversation resolution (pour traiter les remarques du pr-reviewer).
- ✅ Require branches to be up to date before merging.

Ainsi un merge exige : **CI verte + spec valide + revue Claude traitée + revue humaine**.

## 4. Cycle d'une feature

```
/opsx:propose "…"   → change OpenSpec (spec-architect)  → PR de spec → validation humaine
/opsx:apply         → code + tests (implementer / test-engineer)
PR d'implémentation → ci.yml + claude-review.yml + spec-guard.yml ; itérer via @claude
merge (gates verts) → /opsx:archive → openspec/specs/ = nouvelle vérité
```

## 5. Coût / garde-fous

- La revue Claude ne se déclenche que sur `opened`/`synchronize` (pas à chaque commentaire).
- Cadrer les prompts ; envisager un `budget_tokens` dans `claude_args` si besoin.
- `concurrency` annule les runs CI obsolètes sur une même branche.
