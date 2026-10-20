---
name: WANDA
description: L'œil intelligent de la ville — fiches numérotées et tamponnées, sur papier clair, sous en-tête vert officiel.
colors:
  paper: "#F3F6F1"
  surface: "#FFFFFF"
  surface-sunk: "#E9EEE7"
  ink: "#14201A"
  ink-soft: "#46564D"
  ink-muted: "#66766D"
  rule: "#14201A29"
  rule-strong: "#14201A4D"
  letterhead: "#0E5A3A"
  letterhead-deep: "#0A4029"
  on-letterhead-soft: "#C9E3D3"
  brand-leaf: "#8BD14A"
  green-tint: "#E2EFE6"
  stamp-violet: "#5B3CC4"
  stamp-violet-tint: "#ECE7FB"
  progress: "#9A5B00"
  done: "#1E7A46"
  danger: "#C2362B"
  danger-tint: "#FBE3E0"
  gold: "#B8860B"
  service-menage-tint: "#D8E7F8"
  service-menage-ink: "#1B4F8C"
  service-linge-tint: "#F6D8DF"
  service-linge-ink: "#8E2F4C"
  service-dechets-tint: "#D5EEEA"
  service-dechets-ink: "#14665A"
  service-nuisibles-tint: "#F7E9A6"
  service-nuisibles-ink: "#6E5400"
typography:
  display:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "30sp"
    fontWeight: 800
    lineHeight: 1.08
    letterSpacing: "-0.8px"
  heading:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "24sp"
    fontWeight: 800
    lineHeight: 1.12
    letterSpacing: "-0.5px"
  section-title:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "18sp"
    fontWeight: 700
    lineHeight: 1.2
  card-title:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "16sp"
    fontWeight: 700
    lineHeight: 1.2
  body:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "15sp"
    fontWeight: 400
    lineHeight: 1.4
  caption:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "13sp"
    fontWeight: 500
    lineHeight: 1.3
  label:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "14sp"
    fontWeight: 600
  stamp:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "13sp"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "1.6px"
  number:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "15sp"
    fontWeight: 600
    letterSpacing: "0.4px"
rounded:
  chip: "10px"
  field: "12px"
  card: "14px"
  sheet: "24px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
  gutter: "20px"
components:
  button-primary:
    backgroundColor: "{colors.letterhead}"
    textColor: "{colors.surface}"
    rounded: "{rounded.field}"
    height: "54px"
  button-outlined:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    height: "52px"
  fiche-card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.card}"
    padding: "16px"
  input-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "16px"
  service-tab:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.chip}"
    height: "48px"
  counter-button:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.letterhead}"
    rounded: "{rounded.field}"
    height: "48px"
  price-bar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    height: "78px"
  navigation-bar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink-soft}"
    height: "72px"
  letterhead:
    backgroundColor: "{colors.letterhead}"
    textColor: "{colors.surface}"
    padding: "20px"
---

# Design System: WANDA

## Overview

**Le bordereau tamponné.** Chaque signalement, demande ou mission est une fiche numérotée (« N° 004213 ») que la ville tamponne à chaque étape. L'état se lit comme un tampon d'administration — double filet, capitales condensées, légère inclinaison — jamais comme une pastille colorée anonyme.

L'app s'utilise dehors, d'une main, en plein soleil, sur des Android modestes : le monde est donc **clair** (papier blanc-vert), contrasté, et sans effets coûteux (pas de flou, pas de halos, pas d'ombres décoratives). Le vert WANDA vit dans l'**en-tête officiel** de chaque écran — une bande verte au bord perforé, comme une souche détachée d'un carnet à souches.

Structure, navigation et contrôles sont du Material 3 standard (NavigationBar, SegmentedButton, FilledButton, bottom sheets, AlertDialog) : le monde n'apporte que la palette, la typographie, la densité et le geste signature (le tampon).

## Colors

### Primary
- **Vert en-tête** `letterhead` #0E5A3A — bandes d'en-tête, boutons principaux, focus. `letterhead-deep` pour le texte sur teinte verte.
- **Feuille** `brand-leaf` #8BD14A — le vert clair du logo, réservé aux signaux sur fond vert (point « en ligne », progression).

### Secondary
- **Encre de tampon violette** `stamp-violet` #5B3CC4 — statuts « REÇU » et « AJUSTEMENT » (en attente de réponse), et la proposition de correction de l'IA. Ne sert à rien d'autre.

### Tertiary — états
`progress` #9A5B00 (en cours / en route), `done` #1E7A46 (terminé / résolu / en ligne), `danger` #C2362B (annulé, erreur, actions destructrices), `ink-muted` (classé).

### Neutral
`paper` #F3F6F1 fond de page · `surface` blanc pour les fiches · `surface-sunk` zones en creux · `ink` / `ink-soft` / `ink-muted` pour le texte (15:1, 7,5:1, 4,7:1 sur blanc) · `rule` filet d'un pixel.

### Named Rules
- **Copie carbone par service.** Chaque service a une paire teinte/encre et une icône Material fixes, identiques sur les tuiles de réservation, les onglets, les étiquettes, l'en-tête d'une demande, les photos d'identité par défaut et l'anneau des marqueurs de carte (couleur du premier service du prestataire) :
  - **Ménage et nettoyage** — bleu `service-menage` #D8E7F8 / #1B4F8C, `cleaning_services` ;
  - **Linge** — rose `service-linge` #F6D8DF / #8E2F4C, `local_laundry_service` ;
  - **Déchets** (ramassage des poubelles) — vert d'eau `service-dechets` #D5EEEA / #14665A, `delete_sweep` ;
  - **Nuisibles** — jaune `service-nuisibles` #F7E9A6 / #6E5400, `pest_control`.
  Ce sont les 4 paires déjà validées des anciens métiers (contrastes encre / teinte connus), réattribuées. L'accès « Signaler un incident » est en `green-tint`. Exception connue, laissée en l'état en attendant la décision sur le signalement : les tuiles de types d'incident de l'écran de signalement reprennent encore ces teintes (Fuite d'eau en bleu, Électricité en jaune, Dépôt d'ordures en vert d'eau).
- **L'encre parle d'état.** Le violet, l'ambre, le vert « done » et le rouge ne s'emploient que pour un statut réel.

## Typography

**Archivo** pour tout le texte (grotesque d'allure administrative, lisible dehors) ; **Barlow Condensed** pour ce qui est tamponné ou numéroté (statuts, numéros de fiche, distances, compteurs), en chiffres tabulaires. Tailles en sp : le texte suit le réglage système.

### Hierarchy
display 30/800 · heading 24/800 (titres d'en-tête) · section-title 18/700 · card-title 16/700 · body 15/400 · label 14/600 · caption 13/500 · stamp 13/700 capitales espacées · number 15/600 tabulaire.

### Named Rules
- **Les chiffres sont en condensé.** « 5,8 km », « N° 125FC3 », « 3 000 FCFA » : Barlow Condensed, format français (virgule décimale).

## Layout

Gouttière latérale 20 dp. Rythme 4/8/12/16/24/32. En-tête vert pleine largeur sous la barre d'état (edge-to-edge), contenu sur papier en dessous, NavigationBar Material en bas pour les espaces à onglets (citoyen 4 destinations, artisan 3, entreprise 4). Action principale d'un parcours (signalement) dans une barre basse fixe, à portée de pouce. Cibles tactiles ≥ 48 dp.

## Elevation & Depth

Pas d'ombres : la profondeur vient du contraste papier / fiche blanche et des **filets d'un pixel** (`rule`). Les feuilles (bottom sheets, dialogues) utilisent la surface blanche Material sans teinte.

### Named Rules
- **Filet, pas ombre.** Toute carte = surface blanche + filet `rule` + coins 14.

## Shapes

chip 10 · field 12 · card 14 · sheet 24. Photos d'identité carrées à coins doux (18 % de la taille), jamais en cercle — elles sont « agrafées » sur la fiche. Seul le logo reste rond.

## Components

### Buttons
FilledButton vert (54 dp) pour l'action principale ; OutlinedButton à filet pour la secondaire ; rouge `danger` en texte pour les actions destructrices ; TextButton vert pour les liens.

### Chips (onglets de service)
Hauteur 48, icône + libellé court. Sélectionné : teinte carbone du service + filet 1,5 à l'encre du service.

### Tuiles de réservation
Grille 2 × 2 en tête de l'espace citoyen : fond teinte carbone, filet à 25 % de l'encre, icône 28 dp et libellé complet à l'encre du service, hauteur minimale 112 dp, rangées à hauteur égale (le texte agrandi pousse la tuile).

### Questionnaire de demande
- **Compteur** : libellé (et aide) à gauche, boutons − / + carrés de 48 dp (contour `rule-strong`, coins `field`, icône verte), valeur en Barlow Condensed 24 entre les deux. Aucune saisie de texte.
- **Liste de choix** : tuiles pleine largeur ≥ 52 dp avec bouton radio, libellé et aide ; sélection = fond à 7 % de l'encre du service + filet 2 dp.
- **Interrupteur** : `SwitchListTile` Material pour les options oui / non.
- **Barre de prix** : barre basse fixe, blanche à filet supérieur ; à gauche « Estimation » (ou « Prix fixe » une fois confirmé par le serveur) et le montant en Barlow Condensed 26 précédé de « ≈ » tant qu'il n'est pas confirmé ; à droite l'action de l'étape. Annoncée aux lecteurs d'écran à chaque changement.
- **Piste d'étapes** (`PisteEtapes`) : dans l'en-tête, une barre de 4 dp par étape, `brand-leaf` une fois atteinte ; partagée par le signalement et la réservation.

### Cards / Containers — la fiche
`FicheCard` : blanc, filet, coins 14. Une fiche de demande porte en tête son numéro (`FicheNumber`), la date et son tampon ; puis la personne (photo d'identité + nom) ; puis, séparées par un filet, ses actions.

### Inputs / Fields
TextField Material à contour : fond blanc, filet `rule-strong`, focus vert 2 dp, libellé flottant, aide sur 2 lignes. Champ verrouillé (numéro WhatsApp vérifié) avec cadenas.

### Navigation
Material NavigationBar blanche, indicateur `green-tint`, libellés toujours visibles, badge de compteur sur les missions en attente.

### Le tampon de statut (signature)
`StatusStamp` : double filet (2 + 1 dp) à l'encre du statut, fond à 6 % de l'encre, Barlow Condensed en capitales, rotation −4°. Demandes : REÇU (violet) → CONFIRMÉ (ambre) → TERMINÉ (vert), REFUSÉ / ANNULÉ (rouge), CLASSÉ (gris), et AJUSTEMENT (violet) tant qu'un ajustement de prix attend la réponse du client. Quand l'état change, le nouveau tampon « tombe » (échelle 1,35 → 1, fondu, ease-out expo, 380 ms) ; instantané si les animations système sont désactivées. Variante large pour la confirmation « TRANSMIS » d'un signalement et le détail d'une mission.

### L'en-tête officiel
`Letterhead` : bande verte, ligne de contexte (retour, logo, espace ou salutation, photo de profil), titre en heading blanc, sous-titre `on-letterhead-soft`, emplacement bas optionnel (statut en ligne, piste d'étapes), bord inférieur perforé (demi-cercles de 4 dp tous les 14 dp).

## Do's and Don'ts

### Do:
- Donner un numéro de fiche et un tampon à tout ce qui a un statut.
- Garder le code couleur de service identique partout, carte comprise.
- Afficher tout montant au format « 5 400 FCFA » (espaces insécables, Barlow Condensed) ; un montant trop large rétrécit, il ne se coupe jamais.
- Écrire en français simple, chiffres au format français.
- Rester clair et contrasté : l'usage est en extérieur.

### Don't:
- Pas de fond sombre néon, de verre dépoli, de halos ou de dégradés décoratifs (l'ancien monde de l'app).
- Pas d'étiquette au-dessus d'un titre qui ne fait que le répéter ; la ligne de contexte de l'en-tête sert uniquement à la navigation, à la salutation ou à l'étape en cours.
- Pas de tampon décoratif : un tampon affiche toujours un état réel.
- Pas de photo d'identité ronde ni de couleur de service inventée.
