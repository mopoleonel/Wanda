# Wanda

Application Flutter + Supabase de **services ménagers à domicile** (ménage et
nettoyage, linge, ramassage des poubelles, lutte contre les nuisibles) au
**prix fixé par WANDA**, et de signalement d'incidents urbains (Cameroun).

## Architecture

```
lib/
  core/
    error/        AppException + mapError : toute erreur Supabase/réseau est
                   traduite en message français avant d'atteindre l'UI.
    notifications/ Service FCM (voir section Notifications push ci-dessous).
    providers/     Providers Riverpod exposant les repositories.
    router/        Routes nommées (go_router).
    theme/         Couleurs, styles de texte, dégradés partagés.
    widgets/       Composants UI réutilisables (snackbar, boutons, états vides...).
  data/
    models/        Modèles typés (Citoyen, Particulier, Entreprise, Signalement,
                    Sollicitation, AvisPrestataire, CategorieService,
                    DemandeMenage, Ajustement, AnalyseIa) avec fromMap.
    pricing/       Calcul du prix d'une demande (miroir exact de la fonction
                    SQL `calculer_prix`, pour l'estimation en direct).
    repositories/  Toute la logique Supabase (auth, profils, stockage,
                    sollicitations, signalements, avis, notifications) passe
                    par ici — aucun écran n'appelle Supabase directement.
  features/        Un dossier par écran (auth, home, services, demande,
                    signalement, certification, dashboard_particulier,
                    dashboard_entreprise).
supabase/
  functions/       Edge Functions (analyse IA, envoi de notifications push).
  sql/             Scripts SQL à exécuter manuellement dans le SQL Editor.
```

## Démarrage

1. `flutter pub get`
2. Copier `.env.example` vers `.env` et renseigner `SUPABASE_URL` /
   `SUPABASE_ANON_KEY` (valeurs disponibles dans Dashboard Supabase >
   Project Settings > API).
3. `flutter run`

## Migrations SQL à appliquer

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

### Services ménagers (à exécuter dans cet ordre, après 001 à 007)

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

Tous ces scripts sont relançables. Ils ont été exécutés et rejoués sur
PostgreSQL 15 avec un scénario complet (fraudes au prix refusées, prix
serveur, ajustement, passages).

### Modifier les tarifs (administrateur)

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

## Edge Functions (Supabase CLI)

Les deux fonctions IA lisent la clé `GROQ_API_KEY` et le modèle de vision
`GROQ_VISION_MODEL` (par défaut `qwen/qwen3.8-27b` ; `llama-4-scout` a été
arrêté par Groq le 17/07/2026) dans les secrets Supabase.

### `analyze-demande-menage` — vérification des photos d'une demande

Vérifie que les photos correspondent au service, estime l'état / le volume /
l'infestation et le compare au questionnaire. Lit uniquement le bucket privé
`demandes` avec les droits de l'utilisateur (jamais les pièces d'identité),
enregistre le résultat dans `analyses_ia` et ne bloque jamais une
réservation (en cas d'échec : prix sur le questionnaire seul).

```bash
supabase functions deploy analyze-demande-menage
```

### `analyze-signalement` — analyse IA (Groq), clé jamais côté client

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

### `send-push-notification` — envoi FCM

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
branché après connexion citoyen/prestataire — rien d'autre à faire côté code.

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
- Icônes d'application et assets stores, pages légales (CGU / politique de
  confidentialité) — à prévoir avant soumission sur les stores.

## Tests

```bash
flutter analyze   # doit rester sans erreur
flutter test
```

Le calcul du prix est couvert par `test/data/pricing/tarification_test.dart`
(cas partagés avec le contrôle SQL de la migration 009).
