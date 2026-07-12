## ADDED Requirements

### Requirement: Session d'édition mutant le KDBXContent en place
Le système SHALL conserver, à l'ouverture, le `KDBXContent` parsé par KDBXKit et exposer une
couche Core (Swift pur, testable) qui **mute son arbre `KDBX.Group`/`KDBX.Entry` en place**.
Le système SHALL NOT reconstruire un `KDBXContent` à partir du modèle domaine
`DatabaseDocument` (projection lossy : perte d'historique, d'icônes et de champs non modélisés).

#### Scenario: L'édition préserve les données non modélisées
- **WHEN** on ouvre une base dont une entrée porte un champ inconnu du modèle domaine (ex. un
  élément propriétaire) puis on modifie un **autre** champ de cette entrée et on ré-sérialise
- **THEN** le champ non modélisé est toujours présent, à l'identique, dans la base ré-ouverte

#### Scenario: La mutation opère sur l'arbre KDBXKit conservé
- **WHEN** on modifie une entrée via la session d'édition
- **THEN** le `KDBXContent` conservé reflète la modification sans qu'aucun `KDBXContent` neuf
  n'ait été reconstruit depuis `DatabaseDocument`

### Requirement: Édition du mot de passe d'une entrée
Le système SHALL permettre de modifier le mot de passe d'une entrée. La nouvelle valeur SHALL
être ré-encodée **chiffrée au repos** via `KDBX.ProtectedString.Value.unprotected` (et jamais
`.protectedInMemory`, en clair sur disque). Le système SHALL bumper
`Times.lastModificationTime` et snapshoter l'état précédent dans l'historique de l'entrée.

#### Scenario: Le nouveau mot de passe est chiffré au repos
- **WHEN** on remplace le mot de passe d'une entrée et qu'on ré-sérialise la base
- **THEN** la valeur du champ `Password` est portée en `.unprotected` (marquée protégée dans
  le XML), jamais en `.regular` ni `.protectedInMemory`

#### Scenario: Date de modification et historique
- **WHEN** on modifie le mot de passe d'une entrée
- **THEN** `lastModificationTime` de l'entrée est postérieur à sa valeur d'avant l'édition, et
  un snapshot de l'état précédent est ajouté à l'historique de l'entrée

### Requirement: Édition des champs standard et custom
Le système SHALL permettre d'éditer les champs standard non secrets (titre, identifiant, URL,
notes) et les champs custom. Un champ custom **protégé** SHALL être ré-encodé en
`.unprotected` (chiffré au repos) ; un champ **non protégé** en `.regular` (clair).

#### Scenario: Édition d'un champ standard non secret
- **WHEN** on change le titre d'une entrée et qu'on ré-sérialise
- **THEN** la base ré-ouverte expose le nouveau titre, `lastModificationTime` étant bumpé

#### Scenario: Champ custom protégé vs non protégé
- **WHEN** on ajoute un champ custom marqué protégé et un champ custom non protégé
- **THEN** après ré-sérialisation le champ protégé est en `.unprotected` (protégé sur disque)
  et le champ non protégé en `.regular` (clair sur disque)

### Requirement: Ajout et suppression d'entrées
Le système SHALL permettre d'ajouter une nouvelle entrée dans un groupe et de supprimer une
entrée existante, en mutant l'arbre conservé.

#### Scenario: Ajout d'une entrée
- **WHEN** on ajoute une entrée (titre + mot de passe) à un groupe et qu'on ré-sérialise
- **THEN** la base ré-ouverte contient cette entrée dans ce groupe, avec son mot de passe
  chiffré au repos

#### Scenario: Suppression d'une entrée
- **WHEN** on supprime une entrée existante et qu'on ré-sérialise
- **THEN** la base ré-ouverte ne contient plus cette entrée

### Requirement: Ajout, suppression et renommage de groupes
Le système SHALL permettre d'ajouter un sous-groupe, de supprimer un groupe et de renommer un
groupe existant.

#### Scenario: Ajout et renommage d'un groupe
- **WHEN** on ajoute un sous-groupe puis on le renomme et qu'on ré-sérialise
- **THEN** la base ré-ouverte expose le sous-groupe sous son nouveau nom

#### Scenario: Suppression d'un groupe
- **WHEN** on supprime un groupe (et son contenu) et qu'on ré-sérialise
- **THEN** la base ré-ouverte ne contient plus ce groupe ni ses entrées

### Requirement: Aucun secret en clair au-delà du chiffrement disque
Le système SHALL garantir qu'aucun secret édité n'est journalisé, imprimé ou persisté en clair
ailleurs que dans le `.kdbx` chiffré. Les secrets manipulés en édition SHALL emprunter les
mêmes types protégés que la lecture (pas de `String` persistant dans le modèle) et SHALL être
purgés au verrouillage comme aujourd'hui.

#### Scenario: Un secret édité n'est pas exposé en clair par le modèle
- **WHEN** on édite le mot de passe d'une entrée via la session d'édition
- **THEN** le secret n'est accessible que par révélation explicite (scoped) et n'apparaît en
  clair dans aucune description/log du modèle
