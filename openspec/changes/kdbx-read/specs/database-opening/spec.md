## ADDED Requirements

### Requirement: Ouverture d'un .kdbx local avec identifiants
Le système SHALL ouvrir une base `.kdbx` (versions 3.1, 4.0, 4.1) à partir de ses octets et
d'identifiants (mot de passe maître, et optionnellement un key file), via KDBXKit, et
produire un modèle domaine navigable.

#### Scenario: Ouverture réussie avec mot de passe
- **WHEN** on fournit les octets d'un `.kdbx` valide et le bon mot de passe maître
- **THEN** un `DatabaseDocument` est produit exposant le groupe racine et ses entrées

#### Scenario: Ouverture réussie avec mot de passe + key file
- **WHEN** la base requiert un key file et qu'on fournit mot de passe + key file corrects
- **THEN** l'ouverture réussit

#### Scenario: Compatibilité des versions de format
- **WHEN** on ouvre successivement des bases KDBX 3.1, 4.0 et 4.1 valides
- **THEN** chacune s'ouvre et expose le même modèle domaine

### Requirement: Erreurs d'ouverture typées
Le système SHALL signaler les échecs d'ouverture par des erreurs typées, sans divulguer de
secret, et sans planter.

#### Scenario: Mauvais mot de passe
- **WHEN** le mot de passe fourni est incorrect
- **THEN** une erreur « identifiants invalides » est retournée (pas de crash, pas de secret)

#### Scenario: Fichier corrompu ou non supporté
- **WHEN** les octets sont corrompus ou dans un format non supporté
- **THEN** une erreur typée distincte (corruption / version non supportée) est retournée

### Requirement: Mapping vers le modèle domaine sans secret en clair
Le système SHALL convertir le contenu KDBXKit en modèles domaine (`Group`, `Entry`,
`CustomField`, `TotpConfig`, `Attachment`) sans matérialiser les secrets en clair ; les
valeurs protégées sont révélées uniquement à la demande.

#### Scenario: Les champs standards sont mappés
- **WHEN** une entrée possède titre, identifiant, URL et notes
- **THEN** ces champs non secrets sont disponibles sur le `Entry` domaine

#### Scenario: Le mot de passe n'est pas exposé en clair par défaut
- **WHEN** une entrée est mappée
- **THEN** son mot de passe n'est accessible que via une révélation explicite (scoped),
  et n'est pas stocké en clair dans le modèle
