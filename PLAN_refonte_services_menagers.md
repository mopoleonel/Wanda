# Plan — Refonte Wanda : services ménagers à domicile

Plan proposé en réponse à `PROMPT_refonte_services_menagers.md`. **Rien n'est
implémenté** : à valider (et à ajuster) avant de commencer. Les questions
ouvertes sont regroupées en fin de document avec, pour chacune, le choix que
je recommande par défaut.

---

## 0. Constats de l'analyse (à régler avant ou pendant la refonte)

| # | Constat | Conséquence | Correctif proposé |
|---|---|---|---|
| A | La clé `GROQ_API_KEY` des secrets Supabase est **refusée par Groq** (`invalid_api_key`, testé le 20/10/2026). | Toute analyse IA échoue : **aucun signalement citoyen ne peut être envoyé** aujourd'hui. | Vous : créer une nouvelle clé sur console.groq.com et `supabase secrets set GROQ_API_KEY=…`. |
| B | Le modèle `meta-llama/llama-4-scout-17b-16e-instruct` a été **arrêté par Groq le 17/07/2026**. Modèle de vision actuel : `qwen/qwen3.8-27b` (3 images max par requête, 20 Mo, JSON mode compatible). | Même avec une clé valide, `analyze-signalement` échouerait. | Passer les deux fonctions sur `qwen/qwen3.8-27b`, nom du modèle lu depuis un secret `GROQ_VISION_MODEL` (changement futur sans redéployer le code). |
| C | Twilio (envoi des codes WhatsApp) est configuré avec un identifiant factice. | Seuls les numéros de test peuvent se connecter. | Vous : renseigner les vrais identifiants Twilio dans Supabase. |
| D | Le prestataire ne peut aujourd'hui qu'**accepter** une mission (pas de refus). | Exigé par le prompt (« il accepte ou refuse »). | Nouveau statut `refuse` (tampon REFUSÉ). |
| E | La table `sollicitations` n'a pas de migration dans le dépôt (créée à la main). | Les nouvelles colonnes doivent s'ajouter sans connaître toute la structure actuelle. | Migration 008 en `add column if not exists`, sans rien supprimer. |
| F | `storage_repository` ne sait produire que des URL publiques. | Les photos de demande doivent rester privées (preuves). | Ajouter un envoi privé + URL signées (même principe que le bucket `identites` de la 005). |

---

## 1. Catégories de services (remplacent les métiers)

Même règle « copie carbone » de DESIGN.md. Je réutilise les **4 paires
teinte/encre déjà validées** (contrastes connus) en les réattribuant, et
l'encre « Déchets » reste celle du signalement « Dépôt d'ordures » (cohérence
visuelle ville / domicile).

| Code (base) | Libellé | Icône Material | Teinte | Encre |
|---|---|---|---|---|
| `menage` | Ménage et nettoyage | `cleaning_services_rounded` | #D8E7F8 | #1B4F8C |
| `linge` | Linge | `local_laundry_service_rounded` | #F6D8DF | #8E2F4C |
| `dechets` | Déchets | `delete_sweep_rounded` | #D5EEEA | #14665A |
| `nuisibles` | Lutte contre les nuisibles | `pest_control_rounded` | #F7E9A6 | #6E5400 |

Libellé court pour les onglets et tags : « Ménage », « Linge », « Déchets »,
« Nuisibles ».

**Fichiers touchés** : `lib/core/widgets/bordereau.dart` (`TradeStyle` →
catégories par code, libellé court/long), `home_page.dart` (texte d'accroche
et exemple animé « Besoin d'un plombier » → « Grand ménage »),
`citoyen_login_page.dart` (sous-titre), `around_you_scene.dart` (icônes de la
scène), `service_page.dart` (onglets, filtres), `prestataire_marker_factory.dart`
(anneau du marqueur = encre de la 1re catégorie du prestataire), tests.

### Plusieurs services par prestataire

- Nouvelle colonne `particuliers.services text[] not null default '{}'`
  (codes de catégorie), avec contrainte `services <@ array['menage','linge','dechets','nuisibles']`.
- `service_propose` **conservée** (lecture seule, historique) puis
  supprimable plus tard.
- **Migration des prestataires existants** : leurs anciens métiers
  (plombier…) n'ont pas d'équivalent ménager → `services = '{}'`. Ils
  repassent « profil incomplet » (ne peuvent plus passer en ligne) et le
  rappel d'arrivée leur demande de choisir leurs services. Voir question Q1.
- Profil prestataire : la grille à choix unique devient une **sélection
  multiple** (mêmes tuiles `TradeChoiceTile`, case cochée par service).
- Recherche citoyen : filtre `services @> array[code]` au lieu d'une égalité.
- Triggers 005 (`exiger_profil_complet`) et 006 (`figer_identite_certifiee`)
  et vue `verifications_a_traiter` : passés sur `services`. Voir Q2 pour le
  verrouillage après certification.

### Formules

Chaque demande choisit : **ponctuelle** ou **abonnement** (`hebdomadaire`
ou `mensuel`). Colonnes `formule` et `frequence` sur la sollicitation.
L'abonnement **des prestataires à Wanda** (`abonnement_expire_at`, essai) ne
change pas ; dans le code, la formule client s'appelle partout `formule`
(jamais « abonnement » seul) pour éviter la confusion.

---

## 2. Tarification fixée par Wanda

### Formule

```
minutes   = Σ (quantité × minutes du poste) + options
minutes   = minutes × (1 + majoration d'état)          (ménage : 0 / 25 / 50 %)
main d'œuvre = arrondi(minutes / 60 × tarif horaire)
prix passage = main d'œuvre + déplacement + produits (si fournis par le prestataire)
prix         = arrondi à la centaine supérieure (« 5 400 FCFA »)
abonnement   = prix passage × passages par mois × (1 − remise abonnement)
```

### Tables (migration 009)

Une seule table de paramètres, lisible par tous les utilisateurs connectés
(estimation en direct), **modifiable uniquement par un administrateur**
(aucune politique insert/update/delete ; modification via SQL Editor ou clé
service_role) :

```sql
tarifs (service text, cle text, valeur numeric, unite text, libelle text,
        primary key (service, cle))
-- unite : 'min' | 'fcfa' | 'pourcent' | 'nombre'
```

Valeurs de départ (celles du prompt ; les autres sont **à valider**, Q3) :

| service | clé | valeur | source |
|---|---|---|---|
| global | tarif_horaire | 1 200 FCFA | prompt |
| global | deplacement | 1 000 FCFA | prompt |
| global | remise_abonnement | 0 % | à valider |
| menage | chambre / salon / cuisine / douche_wc | 30 / 40 / 45 / 30 min | prompt |
| menage | vitres / frigo / four | +30 / +20 / +20 min | prompt |
| menage | etat_sale / etat_tres_sale | +25 / +50 % | prompt |
| menage | produits | 1 500 FCFA | **proposé** |
| linge | panier_lavage | 40 min | **proposé** |
| linge | draps_delicats (par panier) | +15 min | **proposé** |
| linge | piece_repassage | 4 min | **proposé** |
| linge | produits (lessive) | 500 FCFA / panier | **proposé** |
| dechets | sac | 5 min | **proposé** |
| dechets | etage | 2 min / étage | **proposé** |
| dechets | distance_par_10m | 1 min | **proposé** |
| dechets | passage_minimum | 15 min | **proposé** |
| nuisibles | piece | 20 min | **proposé** |
| nuisibles | produit_par_piece (cafards, moustiques, punaises, rats…) | 1 000 → 3 000 FCFA selon type | **proposé** |
| nuisibles | infestation_moyenne / forte | +50 / +100 % sur produits | **proposé** |

Requête d'exemple documentée (comme la 005) :
`update tarifs set valeur = 1300 where service = 'global' and cle = 'tarif_horaire';`

### Calcul côté serveur

- Fonction SQL `calculer_prix_demande(service, formule, frequence, reponses jsonb)`
  → `minutes, prix_passage, prix_total, detail jsonb` (lignes lisibles :
  « 3 chambres × 30 min »…). `stable`, lit la table `tarifs`.
- Fonction SQL `creer_demande(...)` (`security definer`) : vérifie l'appelant,
  **recalcule** le prix et insère la sollicitation. C'est le seul chemin de
  création des demandes ménagères.
- Trigger : un client ne peut ni écrire ni modifier `minutes_estimees`,
  `prix_*`, `prix_detail`, `ia_analyse` (comme `proteger_badge_identite`).
- Dans l'app : même calcul en Dart (`lib/data/pricing/tarification.dart`,
  pur, sans réseau) alimenté par la table `tarifs` → **prix en direct**
  pendant le questionnaire. Au récapitulatif, l'app demande le prix au
  serveur (`calculer_prix_demande`) et affiche **celui-là** avant de
  réserver. Les deux calculs partagent des cas de test identiques (Dart :
  tests unitaires ; SQL : requêtes de contrôle avec résultats attendus dans
  la migration).

---

## 3. Sollicitation enrichie (migration 008)

Colonnes ajoutées à `sollicitations` (aucune supprimée) :

| colonne | type | rôle |
|---|---|---|
| service | text | `menage` / `linge` / `dechets` / `nuisibles` |
| formule | text | `ponctuelle` / `abonnement` |
| frequence | text null | `hebdomadaire` / `mensuel` |
| reponses | jsonb | réponses au questionnaire |
| produits_fournis | boolean | produits apportés par le prestataire |
| minutes_estimees | int | calcul serveur |
| prix_passage, prix_total | int (FCFA) | calcul serveur |
| prix_detail | jsonb | lignes du calcul |
| photos | text[] | chemins dans le bucket privé `demandes` |
| ia_analyse | jsonb | réponse IA (fourchette, confiance, incohérences) |
| creneau | timestamptz + `creneau_moment` (matin / après-midi) | voir Q5 |

Les anciennes sollicitations (sans service) restent lisibles : la fiche
affiche simplement « Demande » sans prix.

### Statuts et tampons

| statut | tampon | encre |
|---|---|---|
| en_attente | REÇU | violet |
| accepte | CONFIRMÉ (au lieu de « EN ROUTE ») | ambre |
| refuse (nouveau) | REFUSÉ | rouge |
| termine | TERMINÉ | vert |
| annule | ANNULÉ | rouge |
| archive | CLASSÉ | gris |
| *ajustement en attente* (porté par la table ci-dessous) | AJUSTEMENT | violet |

### Ajustements (migration 010)

Table `ajustements` : `id, sollicitation_id, minutes_supp, produits_supp,
motif, photos text[], prix_supp (calcul serveur), statut (en_attente /
accepte / refuse), created_at, repondu_at`.
- `demander_ajustement(...)` : réservé au prestataire de la mission, statut
  `accepte`, prix supplémentaire calculé au tarif horaire de la table.
- `repondre_ajustement(id, accepte bool)` : réservé au client ; si accepté,
  `prix_total` de la sollicitation est mis à jour côté serveur.
- Aucun supplément possible hors de ce circuit ; tout est horodaté (preuve).
- Notifications push (trigger 003 étendu) : demande reçue, refus, ajustement
  demandé / accepté / refusé, mission terminée.

### Photos et preuves

- Bucket **privé** `demandes`, chemin `<citoyen_id>/<demande_id>/<n>.jpg`.
- Lecture : le client propriétaire et le prestataire de la sollicitation
  (politique storage liée à `sollicitations`). Aucune URL publique ; l'app
  affiche des URL signées de courte durée.
- Pas de suppression ni de remplacement (comme `identites`) : preuves en
  cas de litige.
- Compression avant envoi : 1 280 px max, qualité JPEG 60 (≈150–250 Ko).

---

## 4. Analyse IA des photos (Edge Function `analyze-demande-menage`)

- Copie de la structure d'`analyze-signalement` : POST seulement,
  vérification du JWT (`auth.getUser()`), `GROQ_API_KEY` lu depuis les
  secrets, modèle `qwen/qwen3.8-27b` (secret `GROQ_VISION_MODEL`).
- Entrée : `service`, `reponses`, chemins des photos (1 à 3 — limite Groq).
  La fonction **télécharge elle-même** les photos depuis le bucket privé avec
  le JWT de l'utilisateur : l'app n'envoie les images qu'une seule fois
  (réseau lent) et ne peut pas faire analyser une photo qui ne lui appartient
  pas. Seul le bucket `demandes` est lu : **jamais `identites`**.
- Prompt par service ; réponse JSON strict (`response_format: json_object`)
  validée côté fonction :

```json
{ "photos_conformes": true,
  "estimation": { "mesure": "pieces_sales|paniers|sacs|infestation",
                  "min": 2, "max": 3, "etat": "sale" },
  "confiance": 0.0-1.0,
  "incoherences": ["Les photos montrent environ 3 sacs, 1 déclaré"] }
```

- L'app compare : si l'estimation dépasse nettement la déclaration (seuil
  dans `tarifs`, par défaut +50 % ou un niveau d'état au-dessus), elle
  propose « Corriger ma demande » (pré-rempli) ou « Garder ma déclaration ».
  **L'IA ne bloque jamais** : réseau, quota ou erreur → prix sur le
  questionnaire seul, mention « Analyse photo indisponible ».
- Le résultat est enregistré dans `ia_analyse` (preuve, visible du
  prestataire).
- `analyze-signalement` reçoit la même correction de modèle (constat B).

---

## 5. Écrans

### Citoyen

1. **Accueil services** (`service_page`, onglet Experts) : en tête, 4 grandes
   tuiles de catégorie (copie carbone) « Réserver un ménage »… ; dessous, les
   prestataires proches qui proposent la catégorie choisie (liste / carte
   inchangées). Le raccourci « Signaler un incident » reste.
2. **Nouvelle demande** (`features/demande/demande_page.dart`, nouvel
   écran, route `/citoyen/demande/:service`) — en-tête `Letterhead` avec
   piste d'étapes (comme le signalement), **barre basse fixe avec le prix en
   direct** (« ≈ 5 400 FCFA », Barlow Condensed) et le bouton « Continuer » :
   1. Formule : Ponctuelle / Abonnement (Hebdomadaire · Mensuel) — `SegmentedButton`.
   2. Questionnaire du service, en 1 ou 2 écrans courts : **compteurs −/+**
      (cibles 48 dp), choix en tuiles (état du logement, type de nuisible,
      niveau d'infestation), interrupteurs pour les options. Aucun champ texte
      (sauf note facultative).
   3. Photos (obligatoires selon le service, 1 à 3) : prise de vue guidée
      (« photographiez la pièce la plus sale »).
   4. Vérification : analyse IA (non bloquante) → proposition de correction
      éventuelle.
   5. Récapitulatif : détail du prix **confirmé par le serveur**, créneau,
      choix du prestataire (proches qui proposent ce service, note, distance,
      badge vérifié) → « Réserver pour 5 400 FCFA ».
   Depuis la fiche d'un prestataire, « Réserver » ouvre le même parcours avec
   le prestataire déjà choisi.
3. **Mes demandes** : la fiche affiche service, formule, prix, tampon ; un
   bandeau « Ajustement demandé : +1 h, +1 200 FCFA — Accepter / Refuser »
   quand il y en a un ; notation après « TERMINÉ » (avis existants).

### Prestataire

4. **Profil** : sélection multiple des services.
5. **Missions** : chaque fiche montre service, formule, durée estimée, prix
   (ce qu'il touchera — voir Q6). Le détail montre **questionnaire, photos
   et analyse IA avant d'accepter** ; boutons **Accepter / Refuser**.
6. Mission confirmée : « Demander un ajustement » (minutes en plus, produits,
   motif, photo) ; « Terminer la mission ».

### Inchangés

Signalement urbain, espace entreprise, certification (CNI + selfie),
connexion par code.

---

## 6. Ce qui peut gêner le signalement et l'espace entreprise

1. **« Déchets » (service payant à domicile) vs « Dépôt d'ordures »
   (signalement gratuit à la ville)** : risque de confusion pour le citoyen.
   Je propose un libellé explicite (« Ramassage de poubelles à domicile »)
   et une phrase d'aide sur la tuile signalement.
2. **Même quota Groq** pour les deux fonctions IA : un pic de demandes
   ménagères peut faire échouer des signalements. À surveiller (constat A
   d'abord).
3. **Secteur entreprise « Environnement (Déchets) »** : nom proche du
   service « Déchets », sans lien technique (tables différentes).
4. Les teintes du signalement reprennent celles des anciens métiers ; elles
   restent cohérentes avec la nouvelle attribution (bleu = eau, jaune =
   électricité, vert d'eau = déchets).
5. Les textes du trigger push 003 parlent d'« expert en route » : adaptés
   pour les sollicitations, inchangés pour les signalements.
6. Rappel : les signalements sont lisibles sans connexion avec la clé
   publique (photo, GPS, identifiant citoyen) — à corriger côté RLS,
   indépendamment de cette refonte.

---

## 7. Migrations (ordre d'exécution, documenté dans le README)

| N° | Contenu |
|---|---|
| 008 | `particuliers.services` + migration des prestataires ; colonnes de `sollicitations` ; statut `refuse` ; triggers 005/006 et vue mis à jour |
| 009 | table `tarifs` + valeurs de départ + RLS admin ; `calculer_prix_demande` ; `creer_demande` ; protection des colonnes de prix ; requêtes d'exemple et de contrôle |
| 010 | table `ajustements` + RLS ; `demander_ajustement`, `repondre_ajustement` |
| 011 | bucket privé `demandes` + politiques storage |
| 012 | triggers de notifications push étendus |

Chaque script est relançable (`if not exists`, `create or replace`).

---

## 8. Code — fichiers

**Nouveaux** :
- `lib/data/models/categorie_service.dart` (codes, libellés, formules)
- `lib/data/models/demande_menage.dart` (réponses, formule, prix)
- `lib/data/models/ajustement.dart`
- `lib/data/pricing/tarification.dart` (calcul pur, miroir du SQL)
- `lib/data/repositories/tarif_repository.dart`,
  `demande_repository.dart` (création via RPC, ajustements, photos privées,
  appel IA)
- `lib/features/demande/` : `demande_page.dart`, `questionnaires/*.dart`
  (un widget par service), `compteur.dart`, `prix_en_direct.dart`
- `supabase/functions/analyze-demande-menage/index.ts`
- `supabase/sql/008` à `012`

**Modifiés** : `bordereau.dart`, `particulier.dart`, `sollicitation.dart`,
`profile_repository.dart`, `prestataire_repository.dart`,
`sollicitation_repository.dart`, `storage_repository.dart`,
`app_routes.dart`, `app_router.dart`, `home_page.dart`,
`citoyen_login_page.dart`, `service_page.dart`,
`dashboard_particulier_page.dart`, `prestataire_marker_factory.dart`,
`around_you_scene.dart`, `error_mapper.dart` (nouvelles erreurs SQL),
`analyze-signalement/index.ts` (modèle), README.md, PRODUCT.md, DESIGN.md.

**Tests** : `tarification_test.dart` (tous les services, formules,
majorations, arrondis, cas limites), questionnaires (compteurs, prix en
direct), parcours de demande (IA OK / IA en échec / correction proposée),
prestataire (accepter, refuser, ajustement), client (accepter / refuser un
ajustement), mise à jour des tests existants (métiers → catégories).
`flutter analyze` et `flutter test` verts à chaque étape.

**Ordre de livraison** (chaque étape testée et utilisable) :
1. Catégories + multi-services (008 partielle) — l'app reste cohérente.
2. Tarification (009) + questionnaire + prix en direct + création serveur.
3. Photos privées (011) + analyse IA.
4. Prestataire : accepter / refuser + ajustements (010) + notifications (012).
5. Documentation, revue design, tests sur téléphone.

Travail sur une nouvelle branche `refonte/services-menagers` (la sauvegarde
du 20/10 reste intacte).

---

## 9. Questions ouvertes (mon choix par défaut entre crochets)

- **Q1 — Prestataires existants** : leurs métiers n'ont pas d'équivalent.
  [Services vides, ils choisissent à la prochaine connexion ; l'ancien métier
  reste en historique.] Ou les supprimer / les désactiver ?
- **Q2 — Verrouillage après certification** (règle du 15/10 : le métier est
  figé) : avec plusieurs services ? [Un prestataire certifié peut **ajouter**
  un service mais pas en retirer un qui a déjà des avis.] Ou tout figer ?
- **Q3 — Valeurs non fournies** (linge, déchets, nuisibles, produits,
  remise abonnement) : je mets mes propositions du tableau §2 en base, vous
  les corrigez ensuite par SQL. [Oui.]
- **Q4 — Abonnement : exécution** des passages récurrents. [Une
  sollicitation = l'engagement ; le prestataire l'accepte une fois ; chaque
  passage effectué est pointé (table `passages`, migration 010) et visible du
  client.] Ou seulement l'enregistrement de la formule pour l'instant, sans
  suivi des passages ?
- **Q5 — Date et créneau** : le prompt n'en parle pas, mais une prestation à
  domicile en a besoin. [Ajouter « date souhaitée + matin / après-midi » au
  récapitulatif.]
- **Q6 — Ce que voit le prestataire** : le prix total payé par le client, ou
  sa part (commission Wanda) ? [Le prix total ; pas de commission pour
  l'instant — le paiement Mobile Money reste hors périmètre.]
- **Q7 — Refus** : quand un prestataire refuse. [Le client est notifié et
  choisit un autre prestataire depuis sa fiche ; demande, réponses, photos et
  prix sont conservés.] Ou réattribution automatique au plus proche ?
