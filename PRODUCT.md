# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users
- **Citoyens / clients (priorité n°1)** : habitants des villes camerounaises (Douala, Yaoundé), souvent sur Android d'entrée de gamme avec une connexion parfois lente. Job principal : réserver un service ménager à domicile — ménage et nettoyage, linge (lessive, repassage), ramassage des poubelles, lutte contre les nuisibles — au prix fixé par WANDA, une fois ou en abonnement (hebdomadaire ou mensuel), puis suivre sa demande. Job secondaire : signaler un incident urbain (photo + catégorie, vérifiée par IA).
- **Prestataires indépendants** : proposent un ou plusieurs des 4 services ; ne fixent jamais de prix, acceptent ou refusent une demande après avoir vu le questionnaire, les photos et l'analyse IA ; demandent un ajustement dans l'app si le travail est plus important ; gèrent leur disponibilité, leur profil et leur abonnement à WANDA (essai gratuit, forfaits payants à venir).
- **Entreprises** : structures qui reçoivent les signalements assignés comme missions, les traitent sur le terrain (itinéraire) et gardent un historique.

## Product Purpose
Wanda, « l'œil intelligent de la ville », met en relation les habitants avec des prestataires de services ménagers de proximité, à un prix juste et connu d'avance, et fait remonter les incidents urbains aux services compétents. Succès : un client réserve un service en quelques minutes en voyant le prix avant de s'engager, sans mauvaise surprise sur place, et voit sa demande avancer.

## Positioning
Services ménagers à domicile à prix fixé par WANDA (temps estimé × tarif horaire + déplacement + produits, calculé par le serveur), devis appuyé par des photos vérifiées par IA, aucun supplément sur place hors ajustement accepté dans l'app ; plus le signalement urbain. Pensé pour le contexte camerounais (numéro WhatsApp comme identité, réseau variable).

## Operating Context
- Usage en extérieur, souvent d'une main, en mobilité, sous forte luminosité.
- Connexion uniquement par numéro de téléphone + code WhatsApp, pour tous les rôles ; profil complété plus tard.
- Carte (Google Maps) pour les experts et missions ; notifications push (FCM) pour l'avancement.
- Langue : français.

## Capabilities and Constraints
- Flutter + Supabase, Riverpod, go_router. Écrans : splash, choix du rôle, connexions (citoyen / prestataire), espace citoyen (services, réservation en 4 étapes, suivi des demandes, profil, assistant), signalement, tableau de bord prestataire (missions, ajustements, certification), tableau de bord entreprise, carte interne.
- Prix : paramètres dans la table `tarifs` (administrateur seulement), calcul de référence côté serveur ; l'app n'affiche qu'une estimation tant que le serveur n'a pas confirmé.
- Doit rester fluide sur des appareils modestes et des réseaux lents (images légères, peu d'effets coûteux).
- Paiement Mobile Money : hors périmètre pour l'instant (« bientôt disponible »).
- Photos des demandes : privées, conservées comme preuves ; jamais d'envoi des pièces d'identité à l'IA.

## Brand Commitments
- Nom : WANDA.
- Logo à conserver tel quel : l'œil vert (`assets/images/wanda_logo.png`, variante `wanda_logo2.png`).
- Slogan à conserver : « L'œil intelligent de la ville ».
- Le vert reste la couleur de marque.

## Evidence on Hand
- Logos : `assets/images/wanda_logo.png`, `assets/images/wanda_logo2.png`.
- Photos de ville : `assets/images/city1.png` à `city4.jpg`.
- Aucun témoignage, chiffre d'usage ni partenaire officiel : ne pas en inventer.

## Product Principles
1. Le client d'abord : réserver un service doit être le geste le plus direct de l'app ; le signalement reste à un toucher.
2. Prix connu d'avance : le prix fixé par WANDA est visible avant de réserver, jamais négocié sur place.
3. Confiance visible : statut, avancement, note, badge « Identité vérifiée » et ajustements toujours lisibles.
4. Léger et robuste : chaque écran reste utilisable sur un petit Android et une connexion lente ; l'IA ne bloque jamais.
5. Local et humain : langage simple en français, références au contexte camerounais.

## Accessibility & Inclusion
Lisibilité en plein soleil (contrastes forts), cibles tactiles généreuses pour un usage à une main, textes qui supportent l'agrandissement système.
