## Context

Le change `kdbx-read` a validé (spike KDBXKit 1.3.0) que la **clé composite 32 octets** est
accessible via `UnlockData.keyDataBytes` et réinjectable via `UnlockData(rawKeyData:)`.
Cette clé rouvre la base sans mémoriser le mot de passe : c'est **l'Option A** retenue pour
Face ID. Le change `scaffolding` fournit déjà deux briques Core testées : le protocole
`MasterKeyStore` (Sendable) et `AutoLockPolicy` (logique pure de verrouillage). Le type
`DatabaseCredential` (`password` / `keyFile` / `rawKeyData`) vient de `kdbx-read` et
alimente `DatabaseDocument.open`. Ce change assemble ces briques pour offrir le
déverrouillage biométrique, en séparant strictement le Core (Swift pur, testable) de la
couche App (Keychain + `LocalAuthentication`, device).

Rappel du contrat `MasterKeyStore` consommé :
`storeSecret(_ secret: Data, forDatabase id: String) async throws`,
`retrieveSecret(forDatabase id: String, reason: String) async throws -> Data?`,
`removeSecret(forDatabase id: String) async throws`.
La clé de base `id` = `StorageMetadata.identifier` (uniforme local/Drive).

## Goals / Non-Goals

**Goals:**
- Déverrouiller une base enrôlée via Face ID sans ressaisir le mot de passe.
- Enrôler une base (stocker la clé composite 32 octets) après un déverrouillage manuel réussi.
- Désactiver le déverrouillage biométrique d'une base (suppression du secret).
- Garder toute la logique décisionnelle en Core testable ; ne laisser au device que le
  vrai prompt biométrique et l'API Keychain.
- Respecter CLAUDE.md §4 : secret uniquement en Keychain, `.biometryCurrentSet`, purge
  mémoire au verrouillage, pas de PIN de repli.

**Non-Goals:**
- AutoFill, autres connecteurs cloud, iPad/macOS.
- Écriture/édition de base, Google Drive (changes dédiés).
- Synchronisation du secret biométrique entre appareils (le Keychain reste local, non-iCloud).
- Repli par code PIN (interdit).

## Decisions

- **Option A — stocker la clé composite, pas le mot de passe.** On persiste les 32 octets
  de `UnlockData.keyDataBytes`. À la récupération on reconstruit
  `DatabaseCredential(rawKeyData:)` → `DatabaseDocument.open`. Alternative écartée : stocker
  le mot de passe maître (viole l'esprit de §4, secret réutilisable trivialement, et impose
  de le garder en mémoire au moment de l'enrôlement).
- **Service Core générique sur `MasterKeyStore`.** `BiometricUnlockService` ne connaît ni
  Keychain ni `LAContext` ; il orchestre enrôlement/récupération/désactivation et valide la
  longueur (32 octets) du secret. Testé avec un `FakeMasterKeyStore` en mémoire. Le vrai
  Keychain n'est qu'une implémentation du protocole, côté App.
- **`BiometricEvaluator` injectable côté App.** L'accès Keychain protégé par biométrie
  passe par `kSecUseAuthenticationContext: LAContext`. On enveloppe `LAContext` derrière un
  protocole `BiometricEvaluator` pour compiler et tester l'app sans déclencher de prompt
  réel (fake renvoyant succès/échec). Le vrai prompt reste une vérification device.
- **`.biometryCurrentSet` (et non `.biometryAny`).** `SecAccessControlCreateWithFlags` avec
  `.biometryCurrentSet` : le secret est **invalidé** si l'empreinte biométrique enrôlée
  change (ajout/suppression d'un visage). Conforme à §4.3. Conséquence assumée : après un
  changement de biométrie, la base bascule sur le repli mot de passe (ré-enrôlement requis).
- **Enrôlement uniquement après déverrouillage manuel réussi.** On ne peut stocker la clé
  composite que si on l'a obtenue par une ouverture correcte ; l'UI n'expose la bascule
  « Activer Face ID » qu'après ce succès. Évite de stocker une clé non vérifiée.
- **Récupération = `nil` signifie « non enrôlé ».** Le service distingue « pas de secret »
  (repli saisie mot de passe, cas nominal) d'une **erreur** (secret présent mais invalide,
  ou échec de récupération). L'appelant App traduit l'échec biométrique utilisateur en
  retour à la saisie manuelle.
- **Réutiliser `AutoLockPolicy` pour la purge.** Aucune nouvelle politique : sur
  `shouldLock == true` (arrière-plan ou timeout), le service relâche l'état déverrouillé et
  ses secrets. La libération mémoire des `Data`/clés est déterministe côté Core.
- **Clé Keychain = `StorageMetadata.identifier`.** Un secret par base, indépendant de la
  source (local/Drive), ce qui prépare la réutilisation par le connecteur Drive.

## Risks / Trade-offs

- [Perte d'accès après changement de biométrie] `.biometryCurrentSet` invalide le secret →
  l'utilisateur doit ressaisir le mot de passe et ré-enrôler. Assumé et documenté (sécurité
  > confort). Le repli mot de passe garantit l'absence de perte de données.
- [Secret dérobé si l'appareil est compromis] Mitigé : Keychain matériel + biométrie, pas
  de copie hors Keychain, purge mémoire au verrouillage. La clé composite reste sensible —
  jamais loggée, jamais en `print`, jamais persistée ailleurs (§4.3).
- [Impossible de prouver le vrai prompt en CI] Le comportement biométrique réel et
  l'invalidation `.biometryCurrentSet` ne sont pas simulables sur runner CI → couverts par
  une checklist de vérification device. Le Core (décisions, longueur, purge) est, lui,
  entièrement prouvé par `swift test` avec fakes.
- [Longueur de clé inattendue] KDBXKit expose 32 octets aujourd'hui ; on valide la longueur
  au lieu de la présumer, avec une erreur typée plutôt qu'un crash.

## Migration Plan

Additif : nouveau service Core, nouvelle implémentation App, câblage écran Unlock existant.
Aucune donnée persistée n'est modifiée ; le secret biométrique est créé à la demande de
l'utilisateur. Rollback = masquer la bascule/bouton Face ID et supprimer les secrets
enrôlés (`removeSecret`). Aucune migration de format `.kdbx`.

## Open Questions

- Faut-il proposer l'enrôlement automatiquement après le premier déverrouillage réussi, ou
  toujours via une bascule explicite ? (proposé : bascule explicite ; tranché à
  l'implémentation UI).
- Message `reason` du prompt (`LAContext.localizedReason`) : formulation finale et
  localisation — fixé à l'implémentation App.
- Faut-il exposer côté App l'état « base enrôlée » pour afficher un badge dédié ? (nice to
  have, hors tranche minimale).
