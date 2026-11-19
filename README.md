# Wanda

Application Flutter de **services ménagers à domicile** (ménage et
nettoyage, linge, ramassage des poubelles, lutte contre les nuisibles) au
**prix fixé par WANDA**, et de signalement d'incidents urbains (Cameroun).
Le serveur est un back-end **Django** (`backend/`) ; Supabase n'est plus
utilisé par l'app (voir « Historique Supabase » plus bas).

## Architecture

```
lib/
  core/
    api/           Client HTTP de l'API WANDA (jeton JWT renouvelé tout seul,
                    session chiffrée sur le téléphone, suivi par
                    interrogation régulière).
    error/        AppException + mapError : toute erreur serveur/réseau est
                   traduite en message français avant d'atteindre l'UI.
    notifications/ Service FCM (voir section Notifications push ci-dessous).
    providers/     Providers Riverpod exposant les repositories.
    router/        Routes nommées (go_router).
    theme/         Couleurs, styles de texte, dégradés partagés.
    widgets/       Composants UI réutilisables (snackbar, boutons, états vides...).
  data/
    api/           Adaptateurs : réponses JSON de Django -> modèles de l'app.
    models/        Modèles typés (Citoyen, Particulier, Entreprise, Signalement,
                    Sollicitation, AvisPrestataire, CategorieService,
                    DemandeMenage, Ajustement, AnalyseIa) avec fromMap.
    pricing/       Calcul du prix d'une demande (miroir exact du calcul du
                    serveur, pour l'estimation en direct).
    repositories/  Tous les appels au serveur passent par ici — aucun écran
                    n'appelle l'API directement.
  features/        Un dossier par écran (auth, home, services, demande,
                    signalement, certification, dashboard_particulier,
                    dashboard_entreprise). La réservation pose une question
                    à la fois (`demande/parcours.dart`), puis montre le
                    récapitulatif et le montant à payer.
backend/           API Django (comptes, demandes, tarifs, vérifications,
                    signalements, notifications) + administration.
test_e2e/          Parcours complet contre un vrai serveur (lancé à la main).
supabase/          Ancien back-end, gardé pour l'import des données.
```

## Démarrage en local

### 1. Le serveur

```bash
cd backend
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt     # Linux/macOS : .venv/bin/pip
cp .env.exemple .env                              # puis adapter
.venv/Scripts/python manage.py migrate
.venv/Scripts/python manage.py createsuperuser    # accès à /admin
.venv/Scripts/python manage.py runserver 127.0.0.1:8000
```

Avec `OTP_FOURNISSEUR=console`, le code de connexion s'affiche dans le
terminal du serveur. Les numéros de `OTP_NUMEROS_TEST` (par défaut
690 00 00 01 et 690 00 00 02) acceptent toujours le code `123456`.

### 2. L'app

```bash
flutter pub get
flutter run --dart-define=API_URL=http://127.0.0.1:8000/api/
```

- **Téléphone branché en USB** : `adb reverse tcp:8000 tcp:8000`, puis
  l'adresse par défaut (`http://127.0.0.1:8000/api/`) fonctionne.
- **Émulateur Android** : `--dart-define=API_URL=http://10.0.2.2:8000/api/`.
- **Production** : `--dart-define=API_URL=https://wanda237.work/api/`.
  Android n'autorise le HTTP non chiffré que vers 127.0.0.1, localhost et
  10.0.2.2 (`android/app/src/main/res/xml/network_security_config.xml`) :
  partout ailleurs, HTTPS est obligatoire.

APK de diffusion (un fichier par processeur, plus léger) :

```bash
flutter build apk --release --split-per-abi --dart-define=API_URL=https://wanda237.work/api/
```

Aucune clé n'est embarquée dans l'app : Twilio, Groq et Firebase ne sont
configurés que sur le serveur (`backend/.env`).

## Mise en production du serveur

Serveur actuel : VPS Hetzner (Ubuntu 24.04, ARM). Domaine **wanda237.work**
(Porkbun, jusqu'au 19/11/2027) : site de présentation sur
https://wanda237.work/ (pages `confidentialite` et `conditions`), API sur
**https://wanda237.work/api/**, administration sur `/admin/`. Certificats
Let's Encrypt renouvelés tout seuls ; `www.` redirige vers le domaine.
L'ancienne adresse https://89-167-100-113.sslip.io reste servie pour les
toutes premières versions de l'app (`DOMAINES_SECONDAIRES` dans `.env`).
Le site est dans `backend/deploiement/site/` (fichiers servis par Caddy :
une mise à jour du serveur suffit, sans redémarrage).

Tout est dans `backend/deploiement/` : PostgreSQL, l'API, Caddy (HTTPS) dans
Docker, pare-feu (SSH, 80, 443 seulement), sauvegarde chaque nuit à 3 h de la
base et des photos dans `/opt/wanda/sauvegardes` (14 jours gardés). Les
secrets sont générés sur le serveur, dans `/opt/wanda/backend/deploiement/.env`
(jamais sur GitHub).

Mettre à jour le serveur après un changement du back-end (depuis le PC) :

```bash
git archive --format=tar HEAD backend | ssh -i ~/.ssh/wanda_vps root@89.167.100.113   'tar xf - -C /opt/wanda && cd /opt/wanda/backend/deploiement && docker compose up -d --build'
```

Commandes utiles sur le serveur (`ssh -i ~/.ssh/wanda_vps root@89.167.100.113`,
puis `cd /opt/wanda/backend/deploiement`) :

```bash
docker compose ps                                  # état des services
docker compose logs api --tail 50                  # journal de l'API (codes de connexion en mode console)
docker compose exec api python manage.py createsuperuser   # compte d'administration (/admin)
nano .env && docker compose up -d                  # changer un réglage (Twilio, Groq…)
```

Passer à un vrai domaine : créer un enregistrement DNS `A` vers
89.167.100.113, remplacer `DOMAINE`, `DJANGO_ALLOWED_HOSTS` et
`DJANGO_CSRF_TRUSTED_ORIGINS` dans `.env`, `docker compose up -d`, puis
recompiler l'app avec la nouvelle adresse.

**Avant l'ouverture au public** : configurer Twilio (`OTP_FOURNISSEUR=twilio`)
et retirer `OTP_NUMEROS_TEST` du `.env` (sinon n'importe qui connaissant le
code fixe entre dans les comptes de test).

### Reprendre les données de Supabase

```bash
.venv/Scripts/python manage.py importer_supabase --base "<URL PostgreSQL Supabase>"
# --fichiers copie aussi les photos (SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY requis)
```

### Modifier les tarifs

Depuis l'administration (`/admin`, section Tarification). L'app relit les
tarifs à chaque réservation ; le serveur recalcule toujours le prix lui-même.

## Historique Supabase

Les sections suivantes décrivent l'ancien back-end Supabase. Elles ne
servent plus qu'à comprendre les données importées.

### Migrations SQL (ancien back-end)

Dans le Dashboard Supabase > SQL Editor, exécuter dans l'ordre :

1. `supabase/sql/001_particuliers_location.sql` — ajoute la position GPS des
   prestataires (nécessaire pour le tri par proximité côté citoyen).
2. `supabase/sql/002_device_tokens.sql` — table des tokens FCM pour les
   notifications push.
3. `supabase/sql/003_push_triggers.sql` — déclenche automatiquement l'envoi
   de notifications sur les événements clés (nouvelle mission, mission
   acceptée/terminée, nouveau signalement assigné). Nécessite d'avoir
   déployé `send-push-notification` (voir plus bas) et configuré au
   préalable :
   ```sql
   alter database postgres set app.settings.service_role_key = '<ta-clé-service-role>';
   alter database postgres set app.settings.edge_functions_url = 'https://<PROJECT_REF>.supabase.co/functions/v1';
   ```

4. `supabase/sql/004_citoyens_inscription_whatsapp.sql` — nom, prénom et
   email des citoyens deviennent facultatifs (inscription par WhatsApp).
5. `supabase/sql/005_verification_identite_prestataires.sql` — certification
   facultative des prestataires (CNI + selfie) : table de traçabilité,
   journal d'audit, bucket privé `identites`, et badge « Identité vérifiée »
   (`particuliers.identite_verifiee`) mis à jour à la validation. Les
   dossiers se traitent depuis la vue `verifications_a_traiter` (requêtes
   d'exemple en fin de fichier).
6. `supabase/sql/006_identite_figee_apres_certification.sql` — informations
   figées une fois la certification envoyée ou validée.
7. `supabase/sql/007_rattacher_anciens_comptes_au_numero.sql` — connexion
   uniquement par numéro + code WhatsApp : rattache les anciens comptes à
   mot de passe à leur numéro (étape de vérification avant mise à jour).

#### Services ménagers (à exécuter dans cet ordre, après 001 à 007)

8. `supabase/sql/008_services_menagers.sql` — retire les anciens métiers
   (`service_propose`), ajoute `particuliers.services` (plusieurs services
   par prestataire : `menage`, `linge`, `dechets`, `nuisibles`), met à jour
   les règles de certification (services complétables, jamais retirés),
   enrichit `sollicitations` (service, formule, réponses, prix, photos,
   analyse IA, date et créneau) et ajoute le statut `refuse`.
9. `supabase/sql/009_tarification.sql` — table `tarifs` (paramètres de prix,
   modifiables **uniquement par un administrateur**) et fonction de calcul
   `calculer_prix`. Un contrôle intégré vérifie 8 cas de prix partagés avec
   les tests Dart : le script échoue si le calcul diverge.
10. `supabase/sql/010_photos_et_analyses_ia.sql` — bucket **privé**
    `demandes` (photos des demandes, conservées comme preuves) et table
    `analyses_ia` (écrite uniquement par l'Edge Function).
11. `supabase/sql/011_reservation_ajustements.sql` — `creer_demande` (seul
    chemin de création, **prix recalculé par le serveur**), colonnes de prix
    protégées, transitions de statut contrôlées, ajustements
    (`demander_ajustement` / `repondre_ajustement`), passages d'abonnement
    (`pointer_passage`), accès croisé aux photos.
12. `supabase/sql/012_notifications_services.sql` — notifications push des
    demandes, refus, ajustements et passages (remplace les textes de 003
    pour les demandes ; les signalements ne changent pas).

13. `supabase/sql/013_correctif_creer_demande.sql` — **correctif à lancer si
    011 a été appliqué avant le 22/10/2026** : la table `citoyens` a pour
    identifiant `citoyen_id` ; sans ce correctif, toute réservation échoue.
    Le même défaut touchait **007** (corrigé) : relancer 007 s'il avait
    échoué.

14. `supabase/sql/014_proteger_dossiers_prives.sql` — **sécurité, à lancer** :
    une ancienne politique de stockage, valable pour tous les buckets,
    permettait à tout utilisateur connecté de déposer (et de lire) des
    fichiers dans les dossiers privés `demandes` et `identites` d'un autre.
    Le script exclut ces deux buckets de toute politique qui ne précise pas
    de bucket, sans rien changer pour les autres (profils, signalements…).

15. `supabase/sql/015_temps_reel_demandes.sql` — active le temps réel sur
    `sollicitations`, `ajustements` et `passages` : sans lui, une nouvelle
    demande ou une réponse du prestataire n'apparaît chez le client qu'après
    avoir tiré l'écran pour rafraîchir.

16. `supabase/sql/016_securite_rls_profils_avis_signalements.sql` — **sécurité
    et isolation des données** : active RLS sur `citoyens` (isolation stricte
    des données personnelles), `particuliers` et `entreprises` (seul le
    propriétaire modifie son profil), `avis_prestataires` (seul le client d'une
    mission terminée note, une seule note par mission, note entre 1 et 5), et
    `signalements` (seul le citoyen dépose, l'entreprise assignée traite).

Les scripts 008 et suivants sont relançables.

#### Tester les migrations sans toucher à la base

`bash supabase/tests/lancer.sh` (Docker démarré) rejoue 005 → 015 sur un
PostgreSQL 15 jetable qui reproduit le schéma Supabase utile
(`supabase/tests/00_mini_supabase.sql`), vérifie que 008+ se relancent,
puis joue un scénario complet en tant qu'utilisateurs connectés : fraudes au
prix refusées, prix serveur, refus, ajustement, passages, aucun accès pour
un tiers (`supabase/tests/20_scenario_services.sql`).

#### Modifier les tarifs (ancien back-end)

```sql
-- Voir tous les paramètres
select service, cle, valeur, unite, libelle from tarifs order by 1, 2;
-- Exemple : tarif horaire à 1 300 FCFA
update tarifs set valeur = 1300 where service = 'global' and cle = 'tarif_horaire';
-- Essayer un calcul
select calculer_prix_demande('menage', 'ponctuelle', null,
  '{"chambres":2,"salons":1,"cuisines":1,"douche_wc":1,"etat":"normal"}', false);
```

Prix = temps estimé × tarif horaire + déplacement + produits, arrondi à la
centaine supérieure. Si une règle de calcul change (et pas seulement une
valeur), modifier à la fois `calculer_prix` (009) et
`lib/data/pricing/tarification.dart`, puis les cas de test des deux côtés.

### Edge Functions (ancien back-end)

Les deux fonctions IA lisent la clé `GROQ_API_KEY` et le modèle de vision
`GROQ_VISION_MODEL` (par défaut `qwen/qwen3.8-27b` ; `llama-4-scout` a été
arrêté par Groq le 17/07/2026) dans les secrets Supabase.

#### `analyze-demande-menage` — vérification des photos d'une demande

Vérifie que les photos correspondent au service, estime l'état / le volume /
l'infestation et le compare au questionnaire. Lit uniquement le bucket privé
`demandes` avec les droits de l'utilisateur (jamais les pièces d'identité),
enregistre le résultat dans `analyses_ia` et ne bloque jamais une
réservation (en cas d'échec : prix sur le questionnaire seul).

```bash
supabase functions deploy analyze-demande-menage
```

#### `analyze-signalement` — analyse IA (Groq), clé jamais côté client

C'était la faille de sécurité la plus importante trouvée à l'audit : la clé
Groq était auparavant embarquée dans l'app mobile (récupérable par
rétro-ingénierie de l'APK/IPA). Elle vit maintenant uniquement côté serveur.

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase secrets set GROQ_API_KEY=<votre-clé-groq>
supabase secrets set GROQ_VISION_MODEL=qwen/qwen3.8-27b   # facultatif
supabase functions deploy analyze-signalement
```

#### `send-push-notification` — envoi FCM

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
supabase functions deploy send-push-notification
```

(`service-account.json` : Firebase Console > Paramètres du projet > Comptes
de service > Générer une nouvelle clé privée — à ne jamais committer.)

## Notifications push (Firebase Cloud Messaging)

Le code client (`lib/core/notifications/push_notification_service.dart`) est
prêt mais **inactif** tant que Firebase n'est pas connecté, pour ne pas
casser le build en attendant. Trois étapes pour l'activer :

1. Créer un projet Firebase, ajouter une app Android/iOS, télécharger
   `google-services.json` → `android/app/google-services.json` (et
   `GoogleService-Info.plist` → `ios/Runner/` pour iOS).
2. Appliquer le plugin Gradle `com.google.gms.google-services` dans
   `android/build.gradle` (classpath) et `android/app/build.gradle` (plugin) —
   uniquement possible une fois le fichier JSON présent.
3. Dans `lib/main.dart`, appeler
   `await PushNotificationService.initializeFirebase();` juste après
   `WidgetsFlutterBinding.ensureInitialized();`.

L'enregistrement du token par utilisateur (`registerDeviceForUser`) est déjà
branché après connexion citoyen/prestataire (`POST /api/moi/appareils`).
Côté serveur, renseigner `FCM_COMPTE_SERVICE` dans `backend/.env` (chemin
du fichier de compte de service Firebase, jamais commité) : sans lui, les
notifications sont seulement enregistrées en base.

## Sécurité — actions manuelles restantes

- **Clé Google Maps** (`android/app/src/main/AndroidManifest.xml`) : elle a
  été poussée sur GitHub avant l'audit. Vérifier/ajouter les restrictions
  (empreinte SHA-1 + nom de package) dans Google Cloud Console — aucune
  modification de code nécessaire.
- **Signature de release Android** : le projet lit maintenant
  `android/key.properties` s'il existe (sinon retombe sur la clé debug pour
  ne pas casser `flutter run --release` en local). Pour publier :
  ```bash
  keytool -genkey -v -keystore ~/wanda-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias wanda
  ```
  puis créer `android/key.properties` (jamais commité) :
  ```
  storePassword=...
  keyPassword=...
  keyAlias=wanda
  storeFile=/chemin/absolu/vers/wanda-release.jks
  ```

## Hors périmètre (documenté, non implémenté)

- Paiement Mobile Money (CinetPay ou équivalent), pour les prestations
  comme pour l'abonnement des prestataires à WANDA — l'essai gratuit
  existant (`particuliers.abonnement_expire_at`) reste tel quel ; les
  forfaits payants affichent « bientôt disponible ». À ne pas confondre avec
  la formule « abonnement » d'une demande de service (hebdomadaire ou
  mensuelle), qui ne concerne que la fréquence des passages.
- Visuels des stores et pages légales (CGU / politique de
  confidentialité) — à prévoir avant soumission sur les stores. L'icône de
  l'app est le logo WANDA (`flutter_launcher_icons`, voir `pubspec.yaml`).

## Tests

```bash
flutter analyze   # doit rester sans erreur
flutter test
cd backend && .venv/Scripts/python manage.py test
```

Parcours complet contre un serveur lancé en local (connexion du client et
du prestataire, prix identique app/serveur, photo, réservation,
acceptation, ajustement, fin, note) :

```bash
flutter test test_e2e --dart-define=E2E_API=http://127.0.0.1:8000/api/
```

Le calcul du prix est couvert par `test/data/pricing/tarification_test.dart`
(cas partagés avec le calcul du serveur, `backend/tarification`).
