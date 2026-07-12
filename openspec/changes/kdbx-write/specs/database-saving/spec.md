## ADDED Requirements

### Requirement: Ré-sérialisation via KDBXWriter
Le système SHALL ré-encoder le `KDBXContent` édité en octets `.kdbx` via `KDBXWriter` (chemin
de production `streamingWrite(to:content:binaries:unlockData:regenerateSalts:)`, ou `write(...)`
eager pour un buffer testable), sans réimplémenter de crypto (CLAUDE.md §6). Par défaut, les
sels SHALL être régénérés (`regenerateSalts: true`) à chaque sauvegarde.

#### Scenario: Round-trip interne read → write → read
- **WHEN** on ouvre une base, on édite une entrée, on ré-sérialise via `KDBXWriter`, puis on
  ré-ouvre les octets produits avec les mêmes identifiants
- **THEN** l'ouverture réussit et la modification est présente

#### Scenario: Régénération des sels par défaut
- **WHEN** on sauvegarde deux fois de suite la même base sans autre modification
- **THEN** les octets diffèrent (sels/nonce régénérés), et un test byte-identique n'est
  possible qu'en passant explicitement `regenerateSalts: false`

### Requirement: Sauvegarde locale réelle via StorageProvider
Le système SHALL implémenter réellement `StorageProvider.save(_:expectedRemote:)` pour le
stockage local (`LocalStorageProvider`), en écrivant les octets à l'emplacement de la base et
en retournant un `StorageMetadata` à jour (dont `modifiedAt`). Le stub « lecture seule » local
SHALL disparaître.

#### Scenario: La sauvegarde locale écrit les octets et renvoie des métadonnées à jour
- **WHEN** on appelle `save(_:expectedRemote:)` sur le provider local avec des octets `.kdbx`
- **THEN** les octets sont persistés à l'emplacement de la base et le `StorageMetadata`
  retourné reflète la nouvelle modification (identifiant inchangé, `modifiedAt` rafraîchi)

### Requirement: Avertissement de migration 3.1 → 4.1 avant écrasement
Le système SHALL détecter qu'une base ouverte est au format legacy (KDBX 3.1) via
`KDBXContent.legacyFormatNotice == .willMigrate(from:)` et SHALL avertir l'utilisateur que la
sauvegarde **migrera** le fichier en KDBX 4.1 **avant** d'écraser l'original (le writer n'émet
que du 4.x).

#### Scenario: Une base 3.1 signale la migration avant sauvegarde
- **WHEN** on ouvre une base KDBX 3.1
- **THEN** le système expose un avertissement de migration (`.willMigrate(from:)`) exploitable
  par l'UI, avant toute écriture

#### Scenario: Une base 4.x ne déclenche aucun avertissement
- **WHEN** on ouvre une base déjà en KDBX 4.x
- **THEN** aucun avertissement de migration n'est présenté (`legacyFormatNotice == nil`)

### Requirement: Interopérabilité KeePassXC de la base écrite
Le système SHALL garantir qu'une base écrite se ré-ouvre dans KeePassXC (CLAUDE.md §4.2). La
preuve SHALL être un test d'interop réel (`keepassxc-cli` ouvrant les octets produits par
`KDBXWriter`) ; le round-trip interne ne suffit pas (il prouve la self-consistance, pas
l'interop — trois bugs réels n'ont été attrapés que par `keepassxc-cli`).

#### Scenario: keepassxc-cli ouvre la base écrite
- **WHEN** on édite puis ré-sérialise une base et qu'on ouvre les octets produits avec
  `keepassxc-cli` (headless, mot de passe via stdin)
- **THEN** `keepassxc-cli` lit la base sans erreur et retrouve la modification
