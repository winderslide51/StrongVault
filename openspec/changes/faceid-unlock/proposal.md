## Why

Aujourd'hui l'utilisateur doit ressaisir le mot de passe maître à chaque ouverture de sa
base `.kdbx`. C'est le principal frein ergonomique du produit. StrongBox (la référence)
résout cela en stockant le secret d'ouverture derrière la biométrie. Le spike KDBXKit du
change `kdbx-read` a **confirmé l'Option A** : la clé composite 32 octets (le « R »
pré-haché) est exposée par `UnlockData.keyDataBytes` et réinjectable via
`UnlockData(rawKeyData:)` — elle rouvre la base **sans jamais mémoriser le mot de passe**.
On peut donc offrir un déverrouillage Face ID conforme à CLAUDE.md §4 (aucun secret en
clair hors Keychain, invalidation à tout changement de biométrie).

## What Changes

- Nouveau service Core `BiometricUnlockService`, générique sur le protocole `MasterKeyStore`
  (déjà défini par le change scaffolding). Trois opérations : **enrôlement** (stocke la clé
  composite 32 octets après un déverrouillage manuel réussi), **récupération** (lit le
  secret Keychain → `DatabaseCredential(rawKeyData:)`, ou `nil` si non enrôlé → repli
  saisie mot de passe), **désactivation** (supprime le secret). Erreurs typées : non
  enrôlé, secret stocké invalide (longueur != 32 octets).
- Réutilisation de `AutoLockPolicy` (déjà en Core, testée) pour décider du verrouillage et
  déclencher la **purge mémoire** des secrets déchiffrés (arrière-plan / timeout d'inactivité).
- Nouvelle implémentation App `KeychainMasterKeyStore: MasterKeyStore` : `SecItemAdd` /
  `SecItemCopyMatching` avec `SecAccessControlCreateWithFlags(..., .biometryCurrentSet, ...)`
  et récupération via `kSecUseAuthenticationContext: LAContext`.
- Protocole App `BiometricEvaluator` enveloppant `LAContext` (injectable), pour que l'app
  reste compilable et testable sans déclencher un vrai prompt Face ID.
- Câblage de l'écran Unlock : bouton « Déverrouiller avec Face ID » et bascule « Activer
  Face ID pour cette base », proposée seulement après un déverrouillage manuel réussi.
- La clé de stockage par base (`id`) = `StorageMetadata.identifier` (uniforme local/Drive).
- `NSFaceIDUsageDescription` est **déjà présent** dans `project.yml` : aucune dépendance ni
  entitlement supplémentaire à ajouter.

Non-goals : voir la section Impact.

## Capabilities

### New Capabilities
- `biometric-unlock`: déverrouiller une base `.kdbx` via Face ID en réutilisant la clé
  composite 32 octets stockée derrière la biométrie (`.biometryCurrentSet`), avec
  enrôlement/récupération/désactivation, repli mot de passe, erreurs typées et purge
  mémoire des secrets au verrouillage.

### Modified Capabilities
<!-- Aucune capacité de spec archivée n'est modifiée. Le protocole `MasterKeyStore` et
     `AutoLockPolicy` proviennent du change `scaffolding` (non encore archivé) : ce change
     les consomme sans changer leur contrat. `DatabaseCredential`/`rawKeyData` proviennent
     du change `kdbx-read`. Aucun delta MODIFIED requis. -->

## Impact

- Frameworks Apple uniquement (couche App) : `LocalAuthentication`, `Security`. **Aucune**
  dépendance SwiftPM ajoutée. `NSFaceIDUsageDescription` déjà déclaré.
- Code : Core (`BiometricUnlockService`, erreurs typées, réutilisation `AutoLockPolicy`) ;
  App (`KeychainMasterKeyStore`, `BiometricEvaluator`, câblage écran Unlock).
- Prouvable en CI (`swift test`) : le service Core avec un `FakeMasterKeyStore` et un
  `AutoLockPolicy` réel. Compilé par `xcodebuild` : `KeychainMasterKeyStore` /
  `BiometricEvaluator`. **Non prouvable en CI** (device/manuel) : le vrai prompt Face ID et
  l'invalidation `.biometryCurrentSet` au changement de biométrie.
- Pas de vérification interop KeePassXC : ce change ne lit ni n'écrit d'octets `.kdbx`, il
  ne touche qu'au stockage local d'un secret d'ouverture — l'interop reste couverte par
  `kdbx-read`.
- Non-goals : AutoFill (hors v1), autres connecteurs cloud, iPad/macOS, code PIN de repli
  (interdit par CLAUDE.md §4.3), synchronisation du secret biométrique entre appareils,
  écriture/édition de base (`kdbx-write`), Google Drive (`google-drive`).

Critères vérifiables (chaque exigence a un scénario testable, cf. `specs/biometric-unlock/spec.md`) :
- Enrôlement : après un déverrouillage manuel, le secret stocké est exactement la clé
  composite 32 octets (assertion `FakeMasterKeyStore`).
- Récupération : `retrieve` d'une base non enrôlée retourne `nil` (repli mot de passe) ;
  d'une base enrôlée retourne un `DatabaseCredential` porteur du `rawKeyData` d'origine.
- Robustesse : un secret stocké de longueur != 32 octets produit une erreur typée, pas de crash.
- Désactivation : après `disable`, la récupération retourne `nil`.
- Purge/verrouillage : sur décision `AutoLockPolicy.shouldLock`, l'état déverrouillé et ses
  secrets sont libérés (assertion sur l'état du service).
