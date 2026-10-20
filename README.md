# Wanda

Application Flutter + Supabase de signalement d'incidents urbains et de mise
en relation citoyens ↔ prestataires de services (Cameroun).

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
                    Sollicitation, AvisPrestataire) avec fromMap/toMap.
    repositories/  Toute la logique Supabase (auth, profils, stockage,
                    sollicitations, signalements, avis, notifications) passe
                    par ici — aucun écran n'appelle Supabase directement.
  features/        Un dossier par écran (auth, home, citoyen, services,
                    signalement, dashboard_particulier, dashboard_entreprise).
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
   facultative des artisans (CNI + selfie) : table de traçabilité, journal
   d'audit, bucket privé `identites`, et badge « Identité vérifiée »
   (`particuliers.identite_verifiee`) mis à jour à la validation. Les
   dossiers se traitent depuis la vue `verifications_a_traiter` (requêtes
   d'exemple en fin de fichier).

## Edge Functions (Supabase CLI)

### `analyze-signalement` — analyse IA (Groq), clé jamais côté client

C'était la faille de sécurité la plus importante trouvée à l'audit : la clé
Groq était auparavant embarquée dans l'app mobile (récupérable par
rétro-ingénierie de l'APK/IPA). Elle vit maintenant uniquement côté serveur.

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase secrets set GROQ_API_KEY=<votre-clé-groq>
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

- Paiement / abonnement Mobile Money (CinetPay ou équivalent) — le schéma
  d'essai gratuit existant (`particuliers.abonnement_expire_at`) reste tel
  quel ; les forfaits payants affichent un message "bientôt disponible" au
  lieu d'un bouton silencieusement inactif.
- Icônes d'application et assets stores, pages légales (CGU / politique de
  confidentialité) — à prévoir avant soumission sur les stores.

## Tests

```bash
flutter analyze   # doit rester sans erreur
flutter test
```
