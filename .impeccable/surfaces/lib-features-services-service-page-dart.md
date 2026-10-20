---
version: 1
slug: "lib-features-services-service-page-dart"
primary_target: "lib/features/services/service_page.dart"
related_targets: ["lib/main.dart"]
---

# Surface brief — App Wanda (toutes les surfaces Flutter)

Scope : toute l'app mobile (splash, choix du rôle, connexions, espace citoyen, services, signalement, tableaux de bord particulier et entreprise). Mode : Operate. Priorité : parcours citoyen.

Audience/tâche : citoyen en extérieur, d'une main, sous le soleil, Android modeste : signaler un incident ou trouver un expert proche, puis suivre sa demande. Prestataires : recevoir, accepter, clôturer des missions.

## Direction contract

THESIS : chaque signalement et chaque demande est une fiche numérotée que la ville tamponne à chaque étape ; l'état se lit comme un tampon, pas comme une pastille. Refuse le « dark mode vert néon + glassmorphism » de la catégorie.

OWN-WORLD : fond clair papier blanc-vert (#F3F6F1), surfaces blanches, filets d'un pixel encre (#14201A à 12 %), en-tête vert administratif profond (#0E5A3A) façon papier à en-tête, encre de tampon violette (#5B3CC4) réservée aux statuts, copies carbone colorées (jaune, rose, bleu, vert pâle) comme code couleur fixe par métier. Rayons modérés (10–14), pas d'ombres arbitraires, pas de verre dépoli. Numéros de fiche en chiffres tabulaires.

STORY : le citoyen comprend en un coup d'œil ce qu'il peut faire (signaler / trouver un expert), voit ses fiches avancer (REÇU → EN COURS → RÉSOLU) et fait confiance aux experts (note, fiabilité, distance) ; le prestataire voit ses missions comme une pile de bordereaux à traiter.

FIRST VIEWPORT (accueil services citoyen) : bandeau vert à en-tête (logo + « Bonjour » + bascule Liste/Carte) ; dessous, rangée de métiers en onglets carbone colorés ; « Recommandés » ; liste dense d'experts (nom, métier, note, distance, bouton). Action primaire : solliciter un expert depuis sa fiche. Navigation Material NavigationBar en bas, 4 destinations.

SIGNATURE : le tampon de statut (bordure double, capitales espacées, légère rotation, encre violette ou verte/rouge selon l'état) qui « tombe » (échelle 1.25→1, opacité) quand un statut change ; numéro de fiche « N° 000123 » sur chaque demande/signalement/mission. Code couleur métier identique sur carte, puces et fiches. Suivi en lignes stables dont seul le tampon change.

FORM : Bordereau tamponné (candidat 5 de ma liste ordonnée : 1 panneaux de signalisation, 2 enseignes peintes, 3 pagne wax, 4 taxi jaune, 5 bordereau/tampon, 6 marché central, 7 call-box). Seed key : c4b7c06f.

FINISH : unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Décisions ouvertes
- Thème sombre : secondaire (l'usage extérieur impose le clair par défaut).
