# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users
- **Citoyens (priorité n°1)** : habitants des villes camerounaises (Douala, Yaoundé), souvent sur Android d'entrée de gamme avec une connexion parfois lente. Deux jobs : signaler un incident urbain (photo + catégorie, vérifiée par IA) et trouver rapidement un artisan fiable à proximité (plombier, électricien, maçon, froid & clim), puis suivre sa demande.
- **Prestataires particuliers** : artisans indépendants qui reçoivent des sollicitations, gèrent leur disponibilité, leur profil et leur abonnement (essai gratuit, forfaits payants à venir).
- **Entreprises** : structures qui reçoivent les signalements assignés comme missions, les traitent sur le terrain (itinéraire) et gardent un historique.

## Product Purpose
Wanda, « l'œil intelligent de la ville », relie les citoyens à leur ville : faire remonter les incidents urbains aux services compétents et mettre en relation avec des experts de proximité. Succès : un citoyen signale ou trouve un expert en moins d'une minute, et voit que sa demande avance.

## Positioning
Une seule app qui combine signalement urbain vérifié par IA et place de marché d'artisans géolocalisés, pensée pour le contexte camerounais (numéro WhatsApp comme identité citoyenne, réseau variable).

## Operating Context
- Usage en extérieur, souvent d'une main, en mobilité, sous forte luminosité.
- Inscription citoyen par numéro WhatsApp (code OTP), profil complété plus tard ; prestataires et entreprises par email.
- Carte (Google Maps) pour les experts et missions ; notifications push (FCM) pour l'avancement.
- Langue : français.

## Capabilities and Constraints
- Flutter + Supabase, Riverpod, go_router. Écrans : splash, choix du rôle, connexions (citoyen / prestataire), espace citoyen, services (accueil experts, suivi, profil, assistant IA), signalement, tableau de bord particulier, tableau de bord entreprise, carte interne.
- Doit rester fluide sur des appareils modestes et des réseaux lents (images légères, peu d'effets coûteux).
- Paiement Mobile Money : hors périmètre pour l'instant (« bientôt disponible »).

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
1. Le citoyen d'abord : signaler et trouver un expert doivent être les gestes les plus directs de l'app.
2. Confiance visible : statut, avancement, note et fiabilité des experts toujours lisibles.
3. Léger et robuste : chaque écran reste utilisable sur un petit Android et une connexion lente.
4. Local et humain : langage simple en français, références au contexte camerounais.

## Accessibility & Inclusion
Lisibilité en plein soleil (contrastes forts), cibles tactiles généreuses pour un usage à une main, textes qui supportent l'agrandissement système.
