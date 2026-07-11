> **Raffinement de conception (impl.)** : `BiometricUnlockService` est un **courtier
> d'identifiants sans état** (struct générique sur `MasterKeyStore`), plutôt qu'un détenteur
> de la session déverrouillée. L'état déverrouillé (le `DatabaseDocument`) et sa **purge au
> verrouillage** vivent dans la couche App (vue SwiftUI + `AutoLockPolicy`), ce qui garde le
> Core pur et le document hors d'un singleton. Le statut « non enrôlé » est signalé par `nil`
> (pas d'erreur). Design équivalent côté exigences `biometric-unlock`.

- [x] 1.1 `BiometricUnlockService`, générique sur `MasterKeyStore` (Sendable) — courtier
      d'identifiants sans état (cf. note ci-dessus).
- [x] 1.2 Enrôlement `enroll(databaseID:compositeKey:)` : valide la longueur (32 octets) puis
      `storeSecret`. Appelé uniquement après un déverrouillage manuel réussi.
- [x] 1.3 Récupération `unlockCredential(databaseID:reason:) -> DatabaseCredential?` :
      `retrieveSecret` → si `nil`, retourne `nil` (repli saisie) ; sinon reconstruit
      `DatabaseCredential(rawKeyData:)`.
- [x] 1.4 Désactivation `disable(databaseID:)` : `removeSecret`.
- [x] 1.5 Erreur typée `BiometricUnlockError.invalidStoredKey` (longueur != 32 octets), sans
      divulguer de secret. Non-enrôlé = `nil` ; erreurs device (annulation) propagées telles quelles.
- [~] 1.6 Purge au verrouillage : `AutoLockPolicy.shouldLock` réutilisé tel quel ; la libération
      de l'état déverrouillé est portée par la couche App (le Core reste sans état).
- [x] 1.7 `FakeMasterKeyStore` en mémoire (fixture de test) : assertion des octets stockés,
      simulation `nil` / secret invalide / échec biométrique.

## 2. App — Keychain & évaluateur biométrique (device, compilé/testé en CI)

- [x] 2.1 `KeychainMasterKeyStore: MasterKeyStore` : `SecItemAdd` / `SecItemCopyMatching` /
      `SecItemDelete`, item par base indexé sur `id` (= `StorageMetadata.identifier`).
- [x] 2.2 Contrôle d'accès via `SecAccessControlCreateWithFlags(..., .biometryCurrentSet, ...)`
      + `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` ; récupération avec
      `kSecUseAuthenticationContext: LAContext` + `kSecUseOperationPrompt`.
- [x] 2.3 Protocole `BiometricEvaluator` (injectable) + `SystemBiometricEvaluator` (LAContext).
- [x] 2.4 Câblage écran Unlock : bouton « Déverrouiller avec Face ID » (si base enrôlée) et
      bascule « Activer Face ID » (si biométrie dispo et non enrôlée). Statut d'enrôlement
      (non secret) suivi en `UserDefaults`.
- [x] 2.5 `NSFaceIDUsageDescription` déjà dans `project.yml` — aucune dépendance ni entitlement.

## 3. Tests (Core, prouvés par `swift test` en CI)

- [x] 3.1 Enrôlement : après `enroll`, le `FakeMasterKeyStore` contient exactement les 32
      octets fournis pour l'`id` de base attendu.
- [x] 3.2 Récupération non enrôlée → `nil` (repli mot de passe), pas d'erreur.
- [x] 3.3 Récupération enrôlée → `DatabaseCredential` porteur du `rawKeyData` d'origine.
- [x] 3.4 Secret stocké de longueur != 32 octets → `BiometricUnlockError.invalidStoredKey` (pas de crash).
- [x] 3.5 Désactivation : après `disable`, la récupération retourne `nil`.
- [x] 3.6 Purge/verrouillage : sur `AutoLockPolicy.shouldLock == true`, le secret en mémoire est
      libéré (test du patron réutilisé par l'App).
- [~] 3.7 Non-exposition : `DatabaseCredential` masque `description` (couvert dans `kdbx-read`) ;
      `BiometricUnlockError` ne porte aucun secret.

<!-- Pas de tâche interop KeePassXC : non pertinent ici. Ce change ne lit ni n'écrit
     d'octets .kdbx ; il ne gère que le stockage local d'un secret d'ouverture.
     L'interopérabilité reste couverte par le change kdbx-read. -->

## 4. Vérification manuelle (device — non prouvée par la CI)

- [ ] 4.1 Activer Face ID sur une base après un déverrouillage manuel, quitter, rouvrir :
      le prompt Face ID apparaît et la base s'ouvre sans saisir le mot de passe.
- [ ] 4.2 Refuser / échouer le prompt Face ID : l'app bascule proprement sur la saisie mot
      de passe (repli), sans crash ni fuite.
- [ ] 4.3 Modifier la biométrie enrôlée de l'appareil (ajout/suppression de visage) : le
      secret `.biometryCurrentSet` est invalidé, la base repasse en saisie mot de passe et
      un ré-enrôlement est requis.
- [ ] 4.4 Passage en arrière-plan / dépassement du timeout d'inactivité : la base se
      reverrouille (secrets purgés), un nouveau déverrouillage est exigé.
