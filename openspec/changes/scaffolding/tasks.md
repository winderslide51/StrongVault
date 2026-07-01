## 1. Plateforme spec-driven

- [x] 1.1 `openspec init --tools claude` + contexte/règles dans `openspec/config.yaml`
- [x] 1.2 Constitution `CLAUDE.md` (archi, sécurité, qualité, environnement de build)
- [x] 1.3 `README.md` décrivant structure et workflow

## 2. Core (Swift pur, testable)

- [x] 2.1 `Package.swift` (target `StrongCloneCore`, Swift 6, iOS 17 / macOS 14)
- [x] 2.2 Modèles domaine `DomainModels.swift` (Group/Entry/CustomField/TotpConfig/Attachment)
- [x] 2.3 `StorageProvider` + `StorageError` + `InMemoryStorageProvider`
- [x] 2.4 `MasterKeyStore` (protocole) + `AutoLockPolicy` (logique pure)

## 3. Tests Core

- [x] 3.1 Tests modèles domaine (aplatissement récursif, defaults TOTP, égalité)
- [x] 3.2 Tests stockage (round-trip, détection de conflit)
- [x] 3.3 Tests `AutoLockPolicy` (timeout, arrière-plan, désactivé)
- [x] 3.4 `swift build` vert en local (XCTest exécuté en CI faute d'Xcode local)

## 4. App iOS (device — buildée/testée en CI)

- [x] 4.1 `project.yml` XcodeGen (app iPhone iOS 17, NSFaceIDUsageDescription, dép. Core)
- [x] 4.2 Squelette `App/` (`StrongCloneApp`, `RootView`) + `AppTests/` smoke test
- [x] 4.3 Validation de `project.yml` via `xcodegen generate`

## 5. Agents & pipeline CI/CD

- [x] 5.1 Agents `.claude/agents/` : spec-architect, implementer, test-engineer, pr-reviewer
- [x] 5.2 `ci.yml` (lint + tests Core + build/test app simulateur)
- [x] 5.3 `claude-review.yml` (pr-reviewer) + `claude-dispatch.yml` (@claude)
- [x] 5.4 `spec-guard.yml` (validate + no-code-without-spec)
- [x] 5.5 Configs `.swiftlint.yml`, `.swift-format` + doc `docs/CI_SETUP.md`

## 6. Vérification interop KeePassXC

- [ ] 6.1 Non applicable à ce change (aucune lecture/écriture .kdbx) — couvert par `kdbx-read`
