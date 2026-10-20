# Refonte Wanda : services ménagers à domicile

Wanda est déjà opérationnelle. On ne repart PAS de zéro : on la remodèle pour la recentrer sur les services ménagers à domicile, en gardant l'architecture, la logique et le design actuels.

## À lire avant de toucher au code
- README.md, PRODUCT.md, DESIGN.md (design « bordereau tamponné » : fiches numérotées, tampons de statut, en-tête vert perforé, Archivo + Barlow Condensed, filets sans ombres). Tout nouvel écran doit respecter DESIGN.md et réutiliser les composants existants (lib/core/widgets : bordereau.dart, FicheCard, StatusStamp, Letterhead, AppPrimaryButton, AppTextField, status_views…).
- L'architecture : Flutter + Supabase, Riverpod, go_router, repositories dans lib/data/repositories (aucun écran n'appelle Supabase directement), erreurs traduites via error_mapper, migrations SQL numérotées dans supabase/sql (la prochaine est 008), Edge Functions dans supabase/functions.
- Ce qui existe déjà et doit être RÉUTILISÉ, pas réécrit : scan CNI + selfie (lib/core/identity, certification_page, migrations 005 à 007), Edge Function analyze-signalement (modèle de référence pour appeler Groq côté serveur avec vérification du JWT), sollicitations, avis, notifications push, géolocalisation et carte des prestataires.

Commence par analyser le projet, puis présente-moi un plan détaillé (fichiers modifiés, nouvelles tables, migrations, écrans) et attends ma validation avant d'implémenter.

## 1. Remplacer les métiers
Les 4 métiers actuels (Plombier, Électricien, Maçon, Froid & Clim) sont remplacés par 4 catégories de services ménagers :
1. Ménage et nettoyage (ménage régulier, grand ménage, nettoyage après déménagement ou travaux, vitres, canapés et tapis)
2. Linge (lessive, repassage)
3. Déchets (ramassage des poubelles à domicile)
4. Lutte contre les nuisibles (désinsectisation, dératisation)

- Mets à jour partout où les anciens métiers apparaissent : TradeStyle dans bordereau.dart, home_page, service_page, citoyen_login_page, textes d'accueil, marqueurs de carte (prestataire_marker_factory), tests.
- Garde la règle « copie carbone par métier » de DESIGN.md : propose une paire teinte/encre et une icône Material pour chaque nouvelle catégorie, et mets à jour DESIGN.md en conséquence.
- Un prestataire peut proposer plusieurs services (aujourd'hui `particuliers.service_propose` n'en accepte qu'un) : adapte le schéma et prévois la migration des prestataires existants.
- Chaque service propose deux formules : ponctuelle et abonnement (hebdomadaire ou mensuel). Attention à ne pas confondre avec l'abonnement existant des prestataires à Wanda (`abonnement_expire_at`, essai gratuit), qui reste inchangé.
- Ne supprime pas le signalement urbain ni l'espace entreprise : laisse-les en place, je déciderai plus tard de leur sort. Signale-moi dans ton plan ce qui pourrait les gêner.

## 2. Prix fixés par Wanda, jamais par le prestataire
- Le prestataire ne saisit jamais de prix : il accepte ou refuse une mission.
- Prix = temps estimé × tarif horaire + frais de déplacement + produits (si fournis par le prestataire).
- Le temps est calculé à partir d'un questionnaire détaillé rempli par le client, propre à chaque service :
  - Ménage : nombre de chambres, salons, cuisines, douches/WC ; options (vitres, intérieur frigo, four) ; état du logement (normal, sale, très sale) avec majoration du temps (+25 %, +50 %).
  - Linge : nombre de paniers, draps ou vêtements délicats, repassage oui/non, nombre de pièces à repasser.
  - Déchets : nombre de sacs par semaine, fréquence de passage, étage et distance jusqu'au bac.
  - Nuisibles : type de nuisible, nombre de pièces, niveau d'infestation (le coût du produit pèse plus que le temps).
- Valeurs de départ (à mettre en base, modifiables) : chambre 30 min, salon 40 min, cuisine 45 min, douche/WC 30 min, vitres +30 min, frigo ou four +20 min chacun, tarif horaire 1 200 FCFA, déplacement 1 000 FCFA.
- Tous les paramètres de tarification sont stockés dans des tables Supabase, modifiables uniquement par un administrateur (RLS), sans toucher au code. Prévois une requête SQL d'exemple pour les modifier, comme dans la migration 005.
- Le calcul du prix doit être fait côté serveur (fonction SQL ou Edge Function) pour qu'un client ne puisse pas falsifier le montant ; l'appli peut afficher une estimation en direct, mais le prix enregistré est celui du serveur.
- Le client voit le prix final avant de réserver. Les montants s'affichent au format « 5 400 FCFA » en Barlow Condensed, comme le prévoit DESIGN.md.
- Enrichis la sollicitation existante (réponses au questionnaire, formule, temps estimé, prix, photos) plutôt que de créer un système de réservation parallèle.

## 3. Photos et vérification par IA (Groq)
- Le client ajoute des photos : obligatoires pour l'état du logement (ménage), le volume de linge, le volume de poubelles et les nuisibles.
- Crée une nouvelle Edge Function (par exemple analyze-demande-menage) sur le modèle d'analyze-signalement : même vérification du JWT, même lecture de GROQ_API_KEY depuis les secrets Supabase, même modèle de vision (vérifie dans la documentation Groq qu'il est toujours disponible).
- L'IA doit :
  - vérifier que les photos correspondent au service demandé ;
  - estimer l'état du logement, la quantité de linge, le volume de poubelles ou le niveau d'infestation ;
  - comparer avec les réponses du questionnaire.
- Réponse en JSON strict : estimation sous forme de fourchette, niveau de confiance, incohérences détectées.
- Si l'estimation de l'IA dépasse nettement la déclaration du client, l'appli lui propose de corriger sa demande. L'IA ne bloque jamais seule une réservation.
- Compresse les images avant l'envoi (réseau lent, Android modestes). En cas d'échec de l'IA (réseau, quota), le prix est calculé sur le questionnaire seul.
- Les photos de pièce d'identité ne sont jamais envoyées à Groq.

## 4. Protection contre les abus
- Le prestataire voit le questionnaire et les photos avant d'accepter la mission.
- Aucun supplément sur place : si le travail est plus important que prévu, le prestataire fait une demande d'ajustement dans l'appli, que le client accepte ou refuse. Chaque étape a son tampon de statut.
- Les photos, l'analyse IA et les ajustements sont conservés comme preuves en cas de litige (bucket privé, RLS).
- Notation après chaque mission avec le système d'avis existant.

## 5. Expérience utilisateur
- Questionnaire en étapes courtes, avec compteurs et boutons plutôt que de la saisie de texte, utilisable d'une main, cibles ≥ 48 dp.
- Prix qui se met à jour en direct pendant le questionnaire.
- Parcours fluide et attractif, mais strictement dans le style existant (pas de dégradés, d'ombres ni de fonds sombres).

## 6. Qualité
- Migrations SQL numérotées à partir de 008, documentées dans le README dans l'ordre d'exécution.
- Mets à jour PRODUCT.md, DESIGN.md et README.md.
- Ajoute ou adapte les tests (calcul du prix en particulier) ; `flutter analyze` et `flutter test` doivent passer.
- Ne mets aucune clé ni secret dans le code ou la documentation.
