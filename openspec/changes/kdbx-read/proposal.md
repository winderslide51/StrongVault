## Why

Le scaffolding pose la plateforme mais l'app ne sait encore rien faire. La première
capacité produit est de **lire une vraie base KeePass** : ouvrir un fichier `.kdbx` local
avec son mot de passe et en parcourir le contenu. Ce change valide aussi concrètement le
choix de KDBXKit (spike) et met en place le harnais d'interopérabilité KeePassXC qui servira
de source de vérité pour tous les changes suivants.

## What Changes

- Ajout de la dépendance **KDBXKit** (SwiftPM). Elle impose **iOS 26 / macOS 15** (déjà
  aligné) et fournit `KDBXReader.parse`, `UnlockData`, `ProtectedString`.
- Nouveau `DatabaseDocument` (Core) : ouvre des octets `.kdbx` via `KDBXReader.parse` et
  **mappe** `KDBXContent` → modèles domaine (`Group`/`Entry`/…). Lecture seule.
- Révélation des secrets **à la demande** (scoped) plutôt qu'en clair dans le modèle :
  le mapping ne matérialise pas les mots de passe en `String` persistants (ajustement du
  type `Entry`, cf. exigence de mapping de `database-opening`).
- `LocalStorageProvider` (App→Core) : sélection d'un `.kdbx` via `UIDocumentPicker` +
  security-scoped bookmark, puis `load()`.
- UI : écran **Unlock** (saisie mot de passe + key file optionnel), **Browse**
  (arborescence groupes/entrées), **Entry detail** (révéler/copier champs, code TOTP avec
  compte à rebours, champs custom, liste des pièces jointes). Pas d'édition.
- Gestion d'erreurs typées (mauvais mot de passe, version non supportée, HMAC corrompu).
- Harnais de tests d'interop : **golden files** `.kdbx` produits par KeePassXC + étape CI
  **`keepassxc-cli`** ; vecteurs **RFC 6238** pour le TOTP.

## Capabilities

### New Capabilities
- `database-opening`: ouverture/déchiffrement d'un `.kdbx` local et mapping vers le modèle
  domaine, avec erreurs typées et secrets révélés à la demande.
- `vault-browsing`: navigation dans les groupes/entrées et consultation du détail d'une
  entrée (révéler/copier, TOTP, champs custom, pièces jointes).

### Modified Capabilities
<!-- Aucune capacité de spec modifiée. L'ajustement du modèle `Entry` (secrets révélés à la
     demande plutôt que `password: String` en clair) est un détail d'implémentation porté par
     l'exigence « Mapping vers le modèle domaine sans secret en clair » de `database-opening`
     et par les tasks ci-après. `core-foundation` n'étant pas encore archivé, aucun delta
     MODIFIED n'est requis. -->


## Impact

- Dépendance externe : KDBXKit → **iOS 26 / macOS 15** (fait), runner CI **macos-15** (fait).
- CI : installation de `keepassxc-cli` (brew) + commit de golden files de test.
- Non-goals : écriture/édition (`kdbx-write`), FaceID (`faceid-unlock`), Google Drive
  (`google-drive`), recherche/favoris (`polish`). KDBX 3.1 est lu (pas écrit).
