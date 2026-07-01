# CLAUDE.md — Constitution du projet (StrongClone)

> Ce fichier est la **source d'autorité** pour tous les agents (Claude Code local et
> GitHub Actions). Il prime sur les habitudes par défaut. Les agents spécialisés
> (`.claude/agents/*.md`) héritent de ces règles.

## 1. Ce qu'on construit

Un client **KeePass `.kdbx`** pour **iPhone** (iOS 17+), clone fidèle mais simplifié de
StrongBox : connecteur **Google Drive** uniquement (+ stockage local), **déverrouillage
FaceID**, **sans AutoFill** en v1, en **SwiftUI natif**.

**Branding** : « StrongClone » est un *codename* de développement. Ne jamais réutiliser le
nom « StrongBox », son logo ou son identité visuelle dans un artefact publiable.

## 2. Méthode : spec-driven (OpenSpec) — non négociable

- Toute évolution de comportement passe par un **change OpenSpec** dans `openspec/changes/`
  (`proposal.md`, `specs/`, `design.md`, `tasks.md`) **avant** d'écrire du code.
- Ordre : `/opsx:propose` → validation humaine → `/opsx:apply` → PR → revue → merge →
  `/opsx:archive` (met à jour `openspec/specs/`, la vérité courante).
- Une PR qui touche du `.swift` **doit** référencer un change OpenSpec (vérifié par
  `spec-guard.yml`). Pas de code sans spec.

## 3. Architecture en couches (dépendances descendantes uniquement)

```
App/ (SwiftUI, cible Xcode)            → dépend de Core, jamais l'inverse
Sources/StrongCloneCore/ (SwiftPM)
  Database/  → wrapper KDBXKit ↔ modèles domaine (Group, Entry, Field, TOTP, Attachment)
  Storage/   → protocole StorageProvider + Local & GoogleDrive
  Security/  → BiometricKeyStore (Keychain+FaceID), AutoLockManager
```

- **Core est du Swift pur, testable sans simulateur** (`swift test`). Aucune dépendance
  UIKit/SwiftUI dans Core. La biométrie/OAuth qui exigent un device restent en couche App
  ou derrière des protocoles injectables (mockables).
- L'app dépend du package Core via SwiftPM. Pas de logique métier dans les vues SwiftUI.

## 4. Règles de sécurité (bloquantes en revue)

1. **Jamais de format maison** : on lit/écrit du `.kdbx` standard via **KDBXKit**. On ne
   réimplémente pas la crypto à la main.
2. **Interopérabilité KeePassXC obligatoire** : toute base écrite doit se rouvrir dans
   KeePassXC desktop (test de round-trip en CI).
3. **Aucun secret en clair** : mots de passe/clés jamais loggés, jamais en `print`, jamais
   persistés hors Keychain. La clé maître stockée pour FaceID utilise
   `SecAccessControlCreateWithFlags(..., .biometryCurrentSet, ...)` et est invalidée si la
   biométrie change. Pas de fallback code PIN trivial.
4. **Effacement mémoire** : à chaque verrouillage (arrière-plan / timeout), purger les
   secrets déchiffrés.
5. **Presse-papier** : les copies de mot de passe s'auto-effacent après délai.
6. Secrets CI (`ANTHROPIC_API_KEY`, OAuth Google) uniquement via *GitHub Secrets*, jamais
   dans le repo.

## 5. Qualité de code

- **Swift 6**, concurrency stricte. SwiftUI idiomatique, `@Observable` pour les view models.
- **Lint/format** : SwiftLint + swift-format doivent passer (exécutés en CI et pre-commit).
- **Tests** : tout comportement Core a des tests XCTest. Les critères de succès de la spec
  se traduisent en tests. Pas de merge si la CI est rouge.
- Nommage explicite, pas d'abréviations obscures. Commentaires au niveau du code environnant.
- Petites PR atomiques, une par change (ou sous-tâche).

## 6. Réutiliser avant d'écrire

Briques imposées (ne pas réinventer) :
- `.kdbx` : **KDBXKit** (`shadone/KDBXKit`, SwiftPM). Repli documenté : KeePassKit.
- Google Drive : **swift-google-drive-client** (`darrarski/...`, SwiftPM).
- FaceID : `LocalAuthentication`. Keychain : framework `Security`.

## 7. Environnement de build

- **Local (cette machine : Command Line Tools seulement)** : `swift build` compile le
  package Core. `swift test` **ne fonctionne pas** ici car XCTest n'est fourni qu'avec
  Xcode complet. L'app iOS ne se build/teste pas non plus en local.
- **Machine avec Xcode complet** : `swift test` exécute les tests du Core (sans simulateur).
- **CI (GitHub Actions, runner macOS)** : Xcode complet → `swift test` sur Core **et**
  `xcodebuild` build+test de l'app sur simulateur iPhone. C'est là que les tests tournent.
- **Projet Xcode généré par XcodeGen** depuis `project.yml` (le `.xcodeproj` n'est pas
  commité). Régénérer avec `xcodegen generate`.
