// dashboard_particulier_page.dart
// -----------------------------------------------------------------------------
// Tableau de bord du prestataire indépendant (particulier) : missions
// reçues, disponibilité, profil, abonnement.
//
// Changements vs original :
// - Repositories au lieu d'appels Supabase directs.
// - La note affichée est la vraie moyenne agrégée (avant : "5.0" en dur).
// - Passer "en ligne" capture la position GPS, utilisée pour le tri par
//   proximité côté citoyen (avant : aucune position stockée).
// - Les forfaits payants (non implémentés, paiement hors périmètre) montrent
//   un message clair au lieu d'un bouton qui ne faisait rien.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/city_backdrop.dart';
import '../../core/widgets/status_views.dart';
import '../../data/models/avis_prestataire.dart';
import '../../data/models/categorie_service.dart';
import '../../data/models/particulier.dart';
import '../../data/models/sollicitation.dart';
import '../../data/models/verification_identite.dart';

class DashboardParticulierPage extends ConsumerStatefulWidget {
  const DashboardParticulierPage({super.key});

  @override
  ConsumerState<DashboardParticulierPage> createState() =>
      _DashboardParticulierPageState();
}

class _DashboardParticulierPageState
    extends ConsumerState<DashboardParticulierPage> {
  int _selectedIndex = 0;

  Particulier? particulier;
  bool isAvailable = false;
  bool isLoading = true;
  String statusMessage = "Vérification...";
  RatingSummary rating = RatingSummary.empty;

  /// Dernière vérification d'identité (null : jamais envoyée).
  VerificationIdentite? verification;

  /// Faux si la table de vérification n'existe pas encore (migration 005
  /// non appliquée) : on ne bloque alors pas les artisans existants.
  bool _verificationEnabled = true;

  /// État de la certification (null : fonction indisponible, migration
  /// 005 non appliquée).
  _IdentityState? get _identityState {
    if (!_verificationEnabled) return null;
    if (particulier?.identiteVerifiee == true) return _IdentityState.ok;
    return switch (verification?.statut) {
      null => _IdentityState.none,
      VerificationStatut.enAttente => _IdentityState.pending,
      VerificationStatut.rejete => _IdentityState.rejected,
      VerificationStatut.valide => _IdentityState.ok,
    };
  }

  /// Nom, prénom et numéro figés, services seulement complétables :
  /// certification en cours ou obtenue (voir [Particulier.champsFiges]).
  bool get _identityFrozen =>
      particulier?.identiteFigee(
          verificationEnCours: _identityState == _IdentityState.pending) ??
      false;

  /// Le rappel de certification s'affiche une fois par ouverture de
  /// l'espace (donc à chaque connexion), tant que le compte n'est pas
  /// certifié.
  bool _certificationPromptShown = false;

  /// Éléments du profil encore manquants. La certification d'identité
  /// n'est possible qu'une fois le profil complet.
  List<String> get _missingProfile => particulier?.profilManquant ?? const [];

  static const int _profileItems = Particulier.profilElements;

  /// Le minimum pour être visible des citoyens (nom, prénom, services).
  List<String> get _visibilityMissing =>
      particulier?.infosVisibiliteManquantes ?? const [];

  static const _servicesAChoisir = 'Services à choisir';

  List<Sollicitation> sollicitations = [];
  List<FlSpot> graphSpots = [];

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  /// Services cochés dans le profil (codes), avant enregistrement.
  List<String> _editedServices = const [];
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchSollicitations();
    _clock = Timer.periodic(const Duration(minutes: 1), (t) {
      if (mounted && _selectedIndex == 1) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _nomController.dispose();
    _prenomController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    showAppSnackBar(context, message, isError: isError);
  }

  String get _userId => ref.read(authRepositoryProvider).currentUserId ?? '';

  Future<void> _loadData() async {
    if (_userId.isEmpty) return;
    try {
      final data =
          await ref.read(profileRepositoryProvider).fetchParticulier(_userId);
      if (data == null) return;

      String status;
      if (data.hasValidSubscription) {
        final remaining = data.joursRestants();
        status =
            "Pro (${data.typeAbonnement}) · $remaining jour${remaining > 1 ? 's' : ''} restant${remaining > 1 ? 's' : ''}";
      } else {
        status = "Abonnement requis pour passer en ligne";
      }

      final avg =
          await ref.read(avisRepositoryProvider).averageForPrestataire(_userId);

      VerificationIdentite? verif;
      var verifEnabled = true;
      try {
        verif =
            await ref.read(verificationRepositoryProvider).latestFor(_userId);
      } on AppException catch (_) {
        verifEnabled = false;
      }

      // Sans abonnement valide, on ne peut pas être en ligne : si la base
      // dit encore « disponible » (abonnement expiré depuis), on corrige
      // pour que les citoyens ne voient plus ce prestataire.
      final canBeOnline = data.hasValidSubscription;
      if (data.isAvailable && !canBeOnline) {
        try {
          await ref
              .read(prestataireRepositoryProvider)
              .setAvailability(_userId, false);
        } on AppException catch (_) {
          // Réessayé au prochain chargement ; l'interface reste hors ligne.
        }
      }

      if (mounted) {
        setState(() {
          particulier = data;
          verification = verif;
          _verificationEnabled = verifEnabled;
          isAvailable = data.isAvailable && canBeOnline;
          statusMessage = status;
          rating = avg;
          _nomController.text = data.nom;
          _prenomController.text = data.prenom;
          _phoneController.text = data.telephone;
          _editedServices = List.of(data.services);
          isLoading = false;
        });
        _maybePromptCertification();
      }
    } on AppException catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnackBar(e.message);
    }
  }

  Future<void> _fetchSollicitations() async {
    if (_userId.isEmpty) return;
    try {
      final rows = await ref
          .read(sollicitationRepositoryProvider)
          .fetchForPrestataire(_userId, pageSize: 50);
      if (mounted) {
        setState(() {
          sollicitations = rows;
          _generateGraphSpots();
        });
      }
    } on AppException catch (_) {
      // Le tableau reste simplement vide ; pas bloquant pour le reste du dashboard.
    }
  }

  Future<void> _updateMissionStatus(String id, String newStatus,
      {String? phone}) async {
    try {
      await ref.read(sollicitationRepositoryProvider).updateStatus(
            id,
            newStatus,
            dateFin: newStatus == 'termine' ? DateTime.now() : null,
          );

      if (newStatus == 'accepte') {
        await ref
            .read(prestataireRepositoryProvider)
            .setAvailability(_userId, false);
        setState(() => isAvailable = false);
        if (phone != null) _callClient(phone);
      }

      if (newStatus == 'termine') {
        // On ne repasse en ligne que si l'abonnement le permet encore.
        if (particulier?.hasValidSubscription == true) {
          await ref
              .read(prestataireRepositoryProvider)
              .setAvailability(_userId, true);
          setState(() => isAvailable = true);
          _showSnackBar("Mission terminée ! Vous êtes de nouveau en ligne.",
              isError: false);
        } else {
          _showSnackBar(
              "Mission terminée. Renouvelez votre abonnement pour repasser en ligne.",
              isError: false);
        }
      }
      _fetchSollicitations();
    } on AppException catch (e) {
      _showSnackBar(e.message);
    }
  }

  void _generateGraphSpots() {
    final dailyCounts = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};
    final now = DateTime.now();
    for (final s in sollicitations) {
      if (s.dateSollicitation == null) continue;
      final diff = now.difference(s.dateSollicitation!).inDays;
      if (diff >= 0 && diff < 7) {
        dailyCounts[6 - diff] = (dailyCounts[6 - diff] ?? 0) + 1;
      }
    }
    setState(() {
      graphSpots = dailyCounts.entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
          .toList();
    });
  }

  String _getTimeDisplay(Sollicitation item) {
    if (item.statut == 'termine' && item.dateFin != null) {
      return "Terminé à ${DateFormat('HH:mm').format(item.dateFin!.toLocal())}";
    }
    if (item.dateSollicitation == null) return "Inconnue";
    return 'Reçue ${sinceLabel(item.dateSollicitation!)}';
  }

  Future<void> _callClient(String? t) async {
    if (t == null || t.isEmpty) {
      _showSnackBar("Numéro introuvable.");
      return;
    }
    try {
      await launchUrl(Uri.parse("tel:$t"));
    } catch (e) {
      _showSnackBar("Impossible d'appeler.");
    }
  }

  void _maybePromptCertification() {
    final state = _identityState;
    if (_certificationPromptShown ||
        state == null ||
        state == _IdentityState.ok ||
        state == _IdentityState.pending) {
      return;
    }
    _certificationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showCertificationPrompt(state);
    });
  }

  Future<void> _showCertificationPrompt(_IdentityState state) {
    final missing = _missingProfile;
    final refused = state == _IdentityState.rejected && missing.isEmpty;
    final reason = verification?.motifRejet;
    final (title, text, action) = missing.isNotEmpty
        ? (
            'Complétez votre profil, puis certifiez votre compte',
            "Il manque : ${missing.join(', ')}. Une fois votre fiche complète, "
                'certifiez votre identité (CNI + selfie, 2 min) pour obtenir '
                'le badge « Identité vérifiée ».',
            'Compléter mon profil',
          )
        : refused
            ? (
                'Votre certification a été refusée',
                reason?.isNotEmpty == true
                    ? 'Motif : $reason. Recommencez avec des photos nettes '
                        'pour obtenir le badge « Identité vérifiée ».'
                    : 'Recommencez avec des photos nettes pour obtenir le '
                        'badge « Identité vérifiée ».',
                'Recommencer',
              )
            : (
                'Faites certifier votre compte',
                'CNI + selfie, environ 2 minutes. Les citoyens voient le '
                    'badge « Identité vérifiée » sur votre fiche et '
                    'choisissent plus volontiers un prestataire certifié.',
                'Certifier mon compte',
              );

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: refused ? AppColors.dangerTint : AppColors.greenTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      refused
                          ? Icons.error_outline_rounded
                          : Icons.verified_outlined,
                      color: refused ? AppColors.danger : AppColors.letterhead,
                      size: 28),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(child: Text(title, style: AppText.sectionTitle)),
              ]),
              const SizedBox(height: AppSpace.md),
              Text(text, style: AppText.body),
              const SizedBox(height: AppSpace.md),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 18, color: AppColors.inkMuted),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                      'Après certification, vos nom, prénom et numéro ne '
                      'pourront plus être modifiés, et vos services ne pourront '
                      'plus être retirés.',
                      style: AppText.caption),
                ),
              ]),
              const SizedBox(height: AppSpace.xl),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (missing.isNotEmpty) {
                    setState(() => _selectedIndex = 2);
                  } else {
                    _openIdentityVerification();
                  }
                },
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54)),
                child: Text(action),
              ),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                child: const Text('Plus tard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openIdentityVerification() async {
    if (_missingProfile.isNotEmpty) {
      setState(() => _selectedIndex = 2);
      _showSnackBar(
          "Complétez d'abord votre profil : ${_missingProfile.join(', ')}.");
      return;
    }
    final sent = await context.push<bool>(AppRoutes.identityVerification);
    if (sent == true) _loadData();
  }

  Future<void> _toggleVisibility(bool value) async {
    // Inscrit avec son seul numéro : pas visible des citoyens tant que la
    // fiche n'a ni nom ni service.
    final manquant = _visibilityMissing;
    if (value && manquant.isNotEmpty) {
      setState(() => _selectedIndex = 2);
      _showSnackBar(
          "Pour être visible, complétez votre profil : ${manquant.join(', ')}.");
      return;
    }
    if (particulier?.hasValidSubscription != true) {
      _showSubscriptionMenu();
      return;
    }
    setState(() => isAvailable = value);
    try {
      double? lat;
      double? lng;
      if (value) {
        try {
          final pos = await Geolocator.getCurrentPosition();
          lat = pos.latitude;
          lng = pos.longitude;
        } catch (_) {
          // Le prestataire reste "disponible" même sans position : il sera
          // simplement affiché en fin de liste côté citoyen (pas de tri).
        }
      }
      await ref
          .read(prestataireRepositoryProvider)
          .setAvailability(_userId, value, latitude: lat, longitude: lng);
    } on AppException catch (e) {
      setState(() => isAvailable = !value);
      _showSnackBar(e.message);
    }
  }

  Future<void> _updateProfileInfo() async {
    final frozen = _identityFrozen;
    if (frozen &&
        !(particulier?.servicesModifiables(_editedServices,
                verificationEnCours:
                    _identityState == _IdentityState.pending) ??
            true)) {
      _showSnackBar(
          'Compte certifié : vous pouvez ajouter des services, pas en retirer.');
      return;
    }
    if (_nomController.text.trim().isEmpty ||
        _prenomController.text.trim().isEmpty) {
      _showSnackBar("Le nom et le prénom sont obligatoires.");
      return;
    }
    if (_editedServices.isEmpty) {
      _showSnackBar('Choisissez au moins un service.');
      return;
    }
    setState(() => isLoading = true);
    try {
      await ref.read(profileRepositoryProvider).updateParticulierInfo(
            id: _userId,
            nom: _nomController.text.trim(),
            prenom: _prenomController.text.trim(),
            services: CategorieService.codesValides(_editedServices),
            // Le numéro est l'identifiant de connexion : non modifiable ici.
            telephone: particulier?.telephone ?? _phoneController.text.trim(),
          );
      _showSnackBar("Profil mis à jour !", isError: false);
      _loadData();
    } on AppException catch (e) {
      _showSnackBar(e.message);
      setState(() => isLoading = false);
    }
  }
  // ================= UI =================

  /// Filtre de l'onglet Missions : 0 à traiter, 1 en cours, 2 historique.
  int _missionFilter = 0;

  @override
  Widget build(BuildContext context) {
    final body = isLoading
        ? const Center(child: CircularProgressIndicator())
        : switch (_selectedIndex) {
            1 => _buildMissionsView(),
            2 => _buildProfilePage(),
            _ => _buildHomeView(),
          };
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
              key: ValueKey('$_selectedIndex$isLoading'), child: body),
        ),
        // Bande verte fixe sous la barre d'état : quand on fait défiler, le
        // contenu ne passe pas sous les icônes blanches du système.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topInset,
          child: const ColoredBox(color: AppColors.letterhead),
        ),
      ]),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.rule)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            setState(() => _selectedIndex = i);
            if (i == 1) _fetchSollicitations();
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Mon activité',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _pendingCount > 0,
                label: Text('$_pendingCount'),
                child: const Icon(Icons.assignment_outlined),
              ),
              selectedIcon: const Icon(Icons.assignment_rounded),
              label: 'Missions',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }

  int _countStatus(String statut) =>
      sollicitations.where((s) => s.statut == statut).length;
  int get _pendingCount => _countStatus('en_attente');

  String get _displayName {
    final p = particulier;
    if (p == null) return 'Prestataire';
    final full = '${p.prenom} ${p.nom}'.trim();
    return full.isEmpty ? 'Prestataire' : full;
  }

  String get _firstName {
    final p = particulier;
    if (p == null) return '';
    return p.prenom.trim().isNotEmpty ? p.prenom.trim() : p.nom.trim();
  }

  void _openMissions(int filter) {
    setState(() {
      _selectedIndex = 1;
      _missionFilter = filter;
    });
    _fetchSollicitations();
  }

  static const double _overlap = 40;

  Widget _buildHomeView() {
    final pending =
        sollicitations.where((s) => s.statut == 'en_attente').toList();
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadData(), _fetchSollicitations()]);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHero(),
          // L'enseigne chevauche le bord perforé de l'en-tête.
          Transform.translate(
            offset: const Offset(0, -_overlap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
              child: _ShopSign(
                online: isAvailable,
                subscribed: particulier?.hasValidSubscription ?? false,
                trialAvailable: !(particulier?.essaiUtilise ?? true),
                subscriptionLabel: _subscriptionLabel,
                subscriptionProgress: _subscriptionProgress,
                onToggle: () => _toggleVisibility(!isAvailable),
                onActivateTrial: _activateTrial,
                onChoosePlan: _showSubscriptionMenu,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -_overlap + AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Inscrit avec son seul numéro : d'abord compléter la fiche
                // (indépendant de la certification, qui peut être absente).
                if (_visibilityMissing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
                    child: _ProfileProgress(
                      done: _profileItems - _missingProfile.length,
                      total: _profileItems,
                      missing: _missingProfile,
                      onTap: () => setState(() => _selectedIndex = 2),
                    ),
                  )
                else if (_identityState != null &&
                    _identityState != _IdentityState.ok)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
                    child: _CertificationCard(
                      state: _identityState!,
                      rejectReason: verification?.motifRejet,
                      missing: _missingProfile,
                      onTap: _openIdentityVerification,
                    ),
                  ),
                const SectionTitle('Mes missions'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                  child: Row(children: [
                    Expanded(
                      child: _CountTile(
                        status: FicheStatus.sollicitation('en_attente'),
                        label: 'À traiter',
                        count: _pendingCount,
                        onTap: () => _openMissions(0),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: _CountTile(
                        status: FicheStatus.sollicitation('accepte'),
                        label: 'En cours',
                        count: _countStatus('accepte'),
                        onTap: () => _openMissions(1),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: _CountTile(
                        status: FicheStatus.sollicitation('termine'),
                        label: 'Terminées',
                        count:
                            _countStatus('termine') + _countStatus('archive'),
                        onTap: () => _openMissions(2),
                      ),
                    ),
                  ]),
                ),
                if (pending.isNotEmpty) ...[
                  SectionTitle('Nouvelle demande',
                      trailing: pending.length > 1
                          ? '+${pending.length - 1} autre${pending.length > 2 ? 's' : ''}'
                          : null),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                    child: _MissionFiche(
                      item: pending.first,
                      timeLabel: _getTimeDisplay(pending.first),
                      onAccept: () => _updateMissionStatus(
                          pending.first.id, 'accepte',
                          phone: pending.first.numeroCitoyen),
                      onFinish: () =>
                          _updateMissionStatus(pending.first.id, 'termine'),
                      onCall: () => _callClient(pending.first.numeroCitoyen),
                    ),
                  ),
                ],
                const SectionTitle('Demandes reçues sur 7 jours'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                  child: _buildActivityChart(),
                ),
                const SectionTitle('Réputation'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
                  child: _buildReputation(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// En-tête : la ville en duotone, le nom du prestataire et ses services.
  Widget _buildHero() {
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: SizedBox(
        height: topInset + 196,
        child: Stack(fit: StackFit.expand, children: [
          const CityBackdrop(images: ['assets/images/city3.jpg']),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.gutter,
                topInset + AppSpace.md, AppSpace.gutter, _overlap + 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Espace prestataire',
                          style: AppText.label
                              .copyWith(color: AppColors.onLetterheadSoft)),
                      const SizedBox(height: 6),
                      Text(
                        _firstName.isEmpty ? 'Bonjour' : 'Bonjour, $_firstName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.display.copyWith(
                            color: Colors.white, fontSize: 28, height: 1.1),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      if (_identityState == _IdentityState.ok)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.verified_rounded,
                                size: 16, color: AppColors.brandLeaf),
                            const SizedBox(width: 4),
                            Text('Identité vérifiée',
                                style: AppText.caption.copyWith(
                                    color: AppColors.brandLeaf,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      // Passe à la ligne si les services et la note ne tiennent
                      // pas côte à côte (petit écran, texte agrandi).
                      Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ServiceTags(particulier?.services ?? const [],
                                max: 3, emptyLabel: _servicesAChoisir),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.star_rounded,
                                  size: 16,
                                  color: rating.count > 0
                                      ? const Color(0xFFFFD25E)
                                      : AppColors.onLetterheadSoft),
                              const SizedBox(width: 2),
                              Text(
                                rating.count > 0
                                    ? '${rating.average.toStringAsFixed(1).replaceAll('.', ',')} (${rating.count} avis)'
                                    : 'Pas encore d\'avis',
                                style: AppText.caption.copyWith(
                                    color: AppColors.onLetterheadSoft),
                              ),
                            ]),
                          ]),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Semantics(
                  button: true,
                  label: 'Mon profil',
                  child: InkWell(
                    onTap: () => setState(() => _selectedIndex = 2),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IdPhoto(
                          url: particulier?.photoProUrl,
                          size: 56,
                          tint: ServiceStyle.ofServices(
                                  particulier?.services ?? const [])
                              .tint),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
              left: 0, right: 0, bottom: 0, child: PerforatedEdge()),
        ]),
      ),
    );
  }

  String? get _subscriptionLabel {
    final p = particulier;
    if (p == null || !p.hasValidSubscription) return null;
    final days = p.joursRestants();
    final plan = (p.typeAbonnement ?? 'Pro') == 'ESSAI'
        ? 'Essai gratuit'
        : 'Forfait ${p.typeAbonnement ?? 'Pro'}';
    return days <= 0
        ? '$plan · expire aujourd\'hui'
        : '$plan · $days jour${days > 1 ? 's' : ''} restant${days > 1 ? 's' : ''}';
  }

  /// Part restante de l'abonnement (essai : sur 14 jours, sinon sur 30).
  double? get _subscriptionProgress {
    final p = particulier;
    if (p == null || !p.hasValidSubscription) return null;
    final days =
        p.abonnementExpireAt!.difference(DateTime.now()).inHours / 24.0;
    final total = (p.typeAbonnement ?? '') == 'ESSAI' ? 14.0 : 30.0;
    return (days / total).clamp(0.0, 1.0);
  }

  Widget _buildReputation() {
    final hasRating = rating.count > 0;
    return FicheCard(
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3D1),
            borderRadius: BorderRadius.circular(14),
          ),
          child:
              const Icon(Icons.star_rounded, color: AppColors.gold, size: 32),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasRating
                    ? '${rating.average.toStringAsFixed(1).replaceAll('.', ',')} / 5'
                    : 'Pas encore de note',
                style: hasRating
                    ? AppText.number
                        .copyWith(fontSize: 22, fontWeight: FontWeight.w700)
                    : AppText.cardTitle,
              ),
              Text(
                hasRating
                    ? '${rating.count} avis de citoyens'
                    : 'Terminez une mission : le citoyen pourra vous noter.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildActivityChart() {
    final now = DateTime.now();
    final dayLabels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return const ['L', 'M', 'M', 'J', 'V', 'S', 'D'][d.weekday - 1];
    });
    final maxY = graphSpots.isEmpty
        ? 1.0
        : graphSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // Sans données, une ligne suffit : pas de grand cadre vide.
    if (graphSpots.isEmpty || graphSpots.every((s) => s.y == 0)) {
      return FicheCard(
        child: Row(children: [
          Icon(
              graphSpots.isEmpty
                  ? Icons.hourglass_empty_rounded
                  : Icons.bar_chart_rounded,
              color: AppColors.inkMuted),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
                graphSpots.isEmpty
                    ? 'Chargement…'
                    : 'Aucune demande ces 7 derniers jours.',
                style: AppText.body.copyWith(color: AppColors.inkSoft)),
          ),
        ]),
      );
    }
    return FicheCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      child: SizedBox(
        height: 168,
        child: BarChart(
          BarChartData(
            maxY: (maxY < 1 ? 1 : maxY) + 1,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 1,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.rule, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.ink,
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${rod.toY.toInt()} demande${rod.toY > 1 ? 's' : ''}',
                  AppText.caption.copyWith(color: Colors.white),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dayLabels[value.toInt()],
                      style: AppText.number.copyWith(
                        fontSize: 13,
                        color: value.toInt() == 6
                            ? AppColors.ink
                            : AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            barGroups: graphSpots
                .map((s) => BarChartGroupData(x: s.x.toInt(), barRods: [
                      BarChartRodData(
                        toY: s.y,
                        width: 18,
                        color: s.x.toInt() == 6
                            ? AppColors.letterhead
                            : AppColors.letterhead.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ]))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMissionsView() {
    final groups = <List<Sollicitation>>[
      sollicitations.where((s) => s.statut == 'en_attente').toList(),
      sollicitations.where((s) => s.statut == 'accepte').toList(),
      sollicitations
          .where((s) => s.statut != 'en_attente' && s.statut != 'accepte')
          .toList(),
    ];
    final shown = groups[_missionFilter];
    const empties = [
      (
        'Aucune demande à traiter',
        'Les nouvelles demandes des citoyens arrivent ici.'
      ),
      ('Aucune mission en cours', 'Acceptez une demande pour la voir ici.'),
      (
        'Pas encore d\'historique',
        'Vos missions terminées seront listées ici.'
      ),
    ];

    return RefreshIndicator(
      onRefresh: _fetchSollicitations,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Letterhead(
            title: 'Missions',
            subtitle: isAvailable
                ? 'Vous êtes en ligne : les demandes arrivent ici.'
                : 'Vous êtes hors ligne : passez en ligne pour recevoir des demandes.',
            bottom: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
                  backgroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected)
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.1)),
                  foregroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected)
                          ? AppColors.letterheadDeep
                          : Colors.white),
                  side: WidgetStatePropertyAll(
                      BorderSide(color: Colors.white.withValues(alpha: 0.4))),
                ),
                segments: [
                  ButtonSegment(
                      value: 0, label: Text('À traiter (${groups[0].length})')),
                  ButtonSegment(
                      value: 1, label: Text('En cours (${groups[1].length})')),
                  const ButtonSegment(value: 2, label: Text('Historique')),
                ],
                selected: {_missionFilter},
                onSelectionChanged: (s) =>
                    setState(() => _missionFilter = s.first),
              ),
            ),
          ),
          if (shown.isEmpty)
            EmptyStateView(
              icon: Icons.assignment_outlined,
              title: empties[_missionFilter].$1,
              subtitle: empties[_missionFilter].$2,
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xl),
              child: Column(children: [
                for (final item in shown) ...[
                  _MissionFiche(
                    item: item,
                    timeLabel: _getTimeDisplay(item),
                    onAccept: () => _updateMissionStatus(item.id, 'accepte',
                        phone: item.numeroCitoyen),
                    onFinish: () => _updateMissionStatus(item.id, 'termine'),
                    onCall: () => _callClient(item.numeroCitoyen),
                  ),
                  const SizedBox(height: AppSpace.md),
                ],
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    final hasValidSubscription = particulier?.hasValidSubscription ?? false;
    final frozen = _identityFrozen;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Letterhead(
          title: 'Ma fiche prestataire',
          subtitle: 'Ces informations sont visibles par les citoyens.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Semantics(
                  button: true,
                  label: 'Changer ma photo professionnelle',
                  child: InkWell(
                    onTap: _pickImg,
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(clipBehavior: Clip.none, children: [
                      IdPhoto(url: particulier?.photoProUrl, size: 96),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.letterhead,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.paper, width: 3),
                          ),
                          child: const Icon(Icons.photo_camera_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_displayName, style: AppText.sectionTitle),
                      const SizedBox(height: 6),
                      ServiceTags(particulier?.services ?? const [],
                          max: 4, emptyLabel: _servicesAChoisir),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xl),
              _ProfileProgress(
                  done: _profileItems - _missingProfile.length,
                  total: _profileItems,
                  missing: _missingProfile),
              const SizedBox(height: AppSpace.xl),
              if (frozen) ...[
                const _FrozenNotice(),
                const SizedBox(height: AppSpace.lg),
              ],
              _buildInputField('Nom', _nomController, Icons.badge_outlined,
                  locked: frozen),
              _buildInputField(
                  'Prénom', _prenomController, Icons.person_outline_rounded,
                  locked: frozen),
              Text('Vos services', style: AppText.label),
              const SizedBox(height: 2),
              Text(
                  frozen
                      ? 'Compte certifié : vous pouvez ajouter des services, pas en retirer.'
                      : 'Cochez tout ce que vous proposez.',
                  style: AppText.caption),
              const SizedBox(height: AppSpace.sm),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpace.sm,
                crossAxisSpacing: AppSpace.sm,
                childAspectRatio: 2.6,
                children: [
                  for (final c in CategorieService.values)
                    Builder(builder: (context) {
                      final selected = _editedServices.contains(c.code);
                      // Certifié : un service déjà enregistré reste coché.
                      final locked = frozen &&
                          (particulier?.services.contains(c.code) ?? false);
                      return ServiceChoiceTile(
                        style: ServiceStyle.ofCategorie(c),
                        selected: selected,
                        locked: locked,
                        onTap: () {
                          if (locked) return;
                          setState(() => _editedServices = selected
                              ? (List.of(_editedServices)..remove(c.code))
                              : [..._editedServices, c.code]);
                        },
                      );
                    }),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.lg),
                child: TextField(
                  controller: _phoneController,
                  readOnly: true,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone (identifiant de connexion)',
                    helperText:
                        "Pour changer de numéro, contactez l'équipe WANDA.",
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                  ),
                ),
              ),
              FilledButton(
                onPressed: _updateProfileInfo,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54)),
                child: const Text('Enregistrer'),
              ),
              const SizedBox(height: AppSpace.xl),
              if (_identityState != null) ...[
                Text('Badge de confiance', style: AppText.sectionTitle),
                const SizedBox(height: AppSpace.md),
                _CertificationCard(
                  state: _identityState!,
                  rejectReason: verification?.motifRejet,
                  missing: _missingProfile,
                  onTap: _openIdentityVerification,
                ),
                const SizedBox(height: AppSpace.xl),
              ],
              Text('Abonnement', style: AppText.sectionTitle),
              const SizedBox(height: AppSpace.md),
              FicheCard(
                onTap: _showSubscriptionMenu,
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasValidSubscription
                              ? 'Compte Pro ${particulier?.typeAbonnement ?? ''}'
                              : 'Devenir membre Pro',
                          style: AppText.cardTitle,
                        ),
                        const SizedBox(height: 4),
                        Text(statusMessage, style: AppText.caption),
                      ],
                    ),
                  ),
                  StatusStamp(
                    hasValidSubscription
                        ? const FicheStatus('ACTIF', StampTone.done)
                        : const FicheStatus('INACTIF', StampTone.cancelled),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.inkMuted),
                ]),
              ),
              const SizedBox(height: AppSpace.xl),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  if (mounted) context.go(AppRoutes.home);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickImg() async {
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 60);
      if (img == null) return;
      final url = await ref.read(storageRepositoryProvider).uploadImage(
            bucket: 'profils',
            path: 'pro_$_userId.jpg',
            file: File(img.path),
            upsert: true,
          );
      await ref
          .read(profileRepositoryProvider)
          .updateParticulierPhoto(_userId, url);
      _loadData();
    } catch (e) {
      _showSnackBar("Erreur lors de l'envoi de la photo.");
    }
  }

  Widget _buildInputField(String l, TextEditingController c, IconData i,
      {TextInputType keyboardType = TextInputType.text, bool locked = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        readOnly: locked,
        enabled: !locked,
        decoration: InputDecoration(
          labelText: l,
          prefixIcon: Icon(i, size: 20),
          suffixIcon:
              locked ? const Icon(Icons.lock_outline_rounded, size: 18) : null,
        ),
      ),
    );
  }

  void _showSubscriptionMenu() {
    final trialAlreadyUsed = particulier?.essaiUtilise ?? false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choisissez votre forfait Pro', style: AppText.heading),
              const SizedBox(height: 4),
              Text(
                  'Être Pro vous permet de passer en ligne et de recevoir des missions.',
                  style: AppText.body),
              const SizedBox(height: AppSpace.lg),
              if (!trialAlreadyUsed)
                _subOption('Essai gratuit', '14 jours offerts', highlight: true,
                    onTap: () {
                  Navigator.pop(sheetContext);
                  _activateTrial();
                }),
              _subOption('1 semaine', '3 000 FCFA',
                  onTap: _showPaymentComingSoon),
              _subOption('2 semaines', '5 000 FCFA',
                  onTap: _showPaymentComingSoon),
              _subOption('1 mois', '8 000 FCFA', onTap: _showPaymentComingSoon),
              _subOption('3 mois', '15 000 FCFA',
                  onTap: _showPaymentComingSoon),
              const SizedBox(height: AppSpace.md),
              Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.inkMuted),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('Paiement Mobile Money bientôt disponible.',
                      style: AppText.caption),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentComingSoon() {
    Navigator.pop(context);
    _showSnackBar(
        "Le paiement Mobile Money arrive bientôt. Utilisez l'essai gratuit en attendant.",
        isError: false);
  }

  Widget _subOption(String title, String price,
      {required VoidCallback onTap, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: FicheCard(
        color: highlight ? AppColors.greenTint : null,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: AppText.cardTitle.copyWith(
                    color: highlight ? AppColors.letterheadDeep : null)),
          ),
          Text(price,
              style: AppText.number.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: highlight ? AppColors.letterheadDeep : AppColors.ink)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
        ]),
      ),
    );
  }

  Future<void> _activateTrial() async {
    setState(() => isLoading = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .startFreeTrial(_userId, duration: const Duration(days: 14));
      _loadData();
      _showSnackBar("Période d'essai activée !", isError: false);
    } on AppException catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnackBar(e.message);
    }
  }
}

/// Bordereau de mission côté artisan.
class _MissionFiche extends StatelessWidget {
  final Sollicitation item;
  final String timeLabel;
  final VoidCallback onAccept;
  final VoidCallback onFinish;
  final VoidCallback onCall;

  const _MissionFiche({
    required this.item,
    required this.timeLabel,
    required this.onAccept,
    required this.onFinish,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final status = item.statut;
    final client = '${item.prenomCitoyen ?? ''} ${item.nomCitoyen}'.trim();
    final isFinal = status != 'en_attente' && status != 'accepte';
    return FicheCard(
      color: isFinal ? AppColors.paper : null,
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 0),
          child: Row(children: [
            FicheNumber(item.id, color: AppColors.ink),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text('· $timeLabel',
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            StatusStamp(FicheStatus.sollicitation(status)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            const IdPhoto(url: null, size: 44),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client.isEmpty ? 'Client WANDA' : client,
                      style: AppText.cardTitle),
                  if (status == 'accepte' && item.numeroCitoyen.isNotEmpty)
                    Text(item.numeroCitoyen, style: AppText.number),
                ],
              ),
            ),
            if (status == 'accepte')
              IconButton.filledTonal(
                tooltip: 'Appeler le client',
                onPressed: onCall,
                icon: const Icon(Icons.call_rounded),
              ),
          ]),
        ),
        if (!isFinal) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: status == 'en_attente'
                ? FilledButton.icon(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50)),
                    icon: const Icon(Icons.phone_forwarded_rounded, size: 20),
                    label: const Text('Accepter et appeler'),
                  )
                : OutlinedButton.icon(
                    onPressed: onFinish,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50)),
                    icon: const Icon(Icons.task_alt_rounded, size: 20),
                    label: const Text('Terminer la mission'),
                  ),
          ),
        ],
      ]),
    );
  }
}

/// L'enseigne de l'artisan, comme la pancarte OUVERT / FERMÉ d'une boutique.
/// Trois états : en ligne, hors ligne, abonnement requis (verrouillé).
enum _IdentityState { ok, none, pending, rejected }

class _ShopSign extends StatefulWidget {
  final bool online;
  final bool subscribed;
  final bool trialAvailable;
  final String? subscriptionLabel;
  final double? subscriptionProgress;
  final VoidCallback onToggle;
  final VoidCallback onActivateTrial;
  final VoidCallback onChoosePlan;

  const _ShopSign({
    required this.online,
    required this.subscribed,
    required this.trialAvailable,
    required this.subscriptionLabel,
    required this.subscriptionProgress,
    required this.onToggle,
    required this.onActivateTrial,
    required this.onChoosePlan,
  });

  @override
  State<_ShopSign> createState() => _ShopSignState();
}

class _ShopSignState extends State<_ShopSign>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _ShopSign oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    final animate = widget.online &&
        widget.subscribed &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!animate && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = !widget.subscribed;
    final online = widget.online && !locked;

    final (bg, fg, soft) = online
        ? (AppColors.letterhead, Colors.white, AppColors.onLetterheadSoft)
        : (AppColors.surface, AppColors.ink, AppColors.inkSoft);
    final (title, text) = locked
        ? (
            'Abonnement requis',
            'Sans abonnement actif, les citoyens ne vous voient pas.'
          )
        : online
            ? (
                'Vous êtes en ligne',
                'Les citoyens proches vous voient et peuvent vous solliciter.'
              )
            : (
                'Vous êtes hors ligne',
                'Passez en ligne pour recevoir des demandes près de chez vous.'
              );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(AppSpace.lg + 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card + 4),
        border: Border.all(color: online ? bg : AppColors.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            _powerButton(online: online, locked: locked),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusStamp(
                    locked
                        ? const FicheStatus('VERROUILLÉ', StampTone.cancelled)
                        : online
                            ? const FicheStatus('EN LIGNE', StampTone.live)
                            : const FicheStatus(
                                'HORS LIGNE', StampTone.archived),
                    angle: -3,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(title, style: AppText.sectionTitle.copyWith(color: fg)),
                  const SizedBox(height: 2),
                  Text(text, style: AppText.caption.copyWith(color: soft)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: AppSpace.lg),
          if (locked) ...[
            FilledButton.icon(
              onPressed: widget.trialAvailable
                  ? widget.onActivateTrial
                  : widget.onChoosePlan,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              icon: Icon(
                  widget.trialAvailable
                      ? Icons.card_giftcard_rounded
                      : Icons.workspace_premium_rounded,
                  size: 20),
              label: Text(widget.trialAvailable
                  ? 'Activer l\'essai gratuit (14 jours)'
                  : 'Choisir un forfait'),
            ),
            if (widget.trialAvailable)
              TextButton(
                onPressed: widget.onChoosePlan,
                child: const Text('Voir les forfaits'),
              ),
          ] else ...[
            if (online)
              OutlinedButton.icon(
                onPressed: widget.onToggle,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                ),
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 20),
                label: const Text('Passer hors ligne'),
              )
            else
              FilledButton.icon(
                onPressed: widget.onToggle,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                icon: const Icon(Icons.power_settings_new_rounded, size: 20),
                label: const Text('Passer en ligne'),
              ),
            if (widget.subscriptionLabel != null) ...[
              const SizedBox(height: AppSpace.md),
              Row(children: [
                Icon(Icons.workspace_premium_rounded, size: 16, color: soft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.subscriptionLabel!,
                      style: AppText.caption.copyWith(color: soft)),
                ),
                InkWell(
                  onTap: widget.onChoosePlan,
                  child: Text('Prolonger',
                      style: AppText.label.copyWith(
                          color: online
                              ? AppColors.brandLeaf
                              : AppColors.letterhead)),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: widget.subscriptionProgress,
                  minHeight: 5,
                  color: online ? AppColors.brandLeaf : AppColors.letterhead,
                  backgroundColor: online
                      ? Colors.white.withValues(alpha: 0.18)
                      : AppColors.surfaceSunk,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Gros bouton rond : en ligne il pulse, verrouillé il montre un cadenas.
  Widget _powerButton({required bool online, required bool locked}) {
    const size = 76.0;
    final color = locked
        ? AppColors.danger
        : online
            ? AppColors.brandLeaf
            : AppColors.inkMuted;
    return Semantics(
      button: !locked,
      label: locked
          ? 'Abonnement requis'
          : online
              ? 'Passer hors ligne'
              : 'Passer en ligne',
      child: GestureDetector(
        onTap: locked ? null : widget.onToggle,
        child: SizedBox(
          width: size + 16,
          height: size + 16,
          child: Stack(alignment: Alignment.center, children: [
            if (online)
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Container(
                  width: size + 16 * _pulse.value,
                  height: size + 16 * _pulse.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandLeaf
                        .withValues(alpha: 0.35 * (1 - _pulse.value)),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online
                    ? Colors.white.withValues(alpha: 0.12)
                    : color.withValues(alpha: 0.1),
                border: Border.all(color: color, width: 3),
              ),
              child: Icon(
                locked ? Icons.lock_rounded : Icons.power_settings_new_rounded,
                color: color,
                size: 36,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Compteur de missions par statut, à l'encre de son tampon.
class _CountTile extends StatelessWidget {
  final FicheStatus status;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _CountTile({
    required this.status,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$count $label',
      excludeSemantics: true,
      child: FicheCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(children: [
          Text('$count',
              style: AppText.number.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: count > 0 ? status.ink : AppColors.inkMuted)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                  color: count > 0 ? AppColors.ink : AppColors.inkMuted,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Rappel en tête du profil certifié : pourquoi les champs sont figés.
class _FrozenNotice extends StatelessWidget {
  const _FrozenNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.rule),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lock_person_rounded,
            color: AppColors.letterheadDeep, size: 20),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            'Compte certifié : nom, prénom et numéro correspondent à votre '
            "pièce d'identité et ne peuvent plus être modifiés ; vos services "
            "peuvent être complétés, pas retirés. Pour une correction, "
            "contactez l'équipe WANDA.",
            style: AppText.caption.copyWith(color: AppColors.ink),
          ),
        ),
      ]),
    );
  }
}

/// Certification facultative : badge « Identité vérifiée » pour les
/// citoyens. Affichée sur l'accueil et dans le profil.
class _CertificationCard extends StatelessWidget {
  final _IdentityState state;
  final String? rejectReason;
  final VoidCallback onTap;

  /// Éléments du profil manquants : tant qu'il y en a, la certification est
  /// verrouillée (sauf si elle est déjà en cours ou obtenue).
  final List<String> missing;
  const _CertificationCard(
      {required this.state,
      required this.rejectReason,
      required this.onTap,
      this.missing = const []});

  @override
  Widget build(BuildContext context) {
    final locked = missing.isNotEmpty &&
        (state == _IdentityState.none || state == _IdentityState.rejected);
    final (icon, color, tint, title, text, action) = locked
        ? (
            Icons.lock_outline_rounded,
            AppColors.inkSoft,
            AppColors.surfaceSunk,
            'Badge de confiance verrouillé',
            "Complétez d'abord votre profil (${missing.join(', ')}) pour pouvoir certifier votre identité.",
            'Compléter mon profil',
          )
        : switch (state) {
            _IdentityState.ok => (
                Icons.verified_rounded,
                AppColors.done,
                AppColors.doneTint,
                'Identité vérifiée',
                'Le badge de confiance est affiché sur votre fiche.',
                null,
              ),
            _IdentityState.pending => (
                Icons.hourglass_top_rounded,
                AppColors.stampViolet,
                AppColors.stampVioletTint,
                'Certification en cours',
                'Nous vérifions votre pièce, généralement sous 48 h.',
                null,
              ),
            _IdentityState.rejected => (
                Icons.error_outline_rounded,
                AppColors.danger,
                AppColors.dangerTint,
                'Certification refusée',
                rejectReason?.isNotEmpty == true
                    ? 'Motif : $rejectReason. Vous pouvez recommencer.'
                    : 'Vous pouvez recommencer avec des photos plus nettes.',
                'Recommencer',
              ),
            _IdentityState.none => (
                Icons.verified_outlined,
                AppColors.letterhead,
                AppColors.greenTint,
                'Obtenez le badge de confiance',
                'Facultatif : certifiez votre identité (CNI + selfie, 2 min). Les citoyens choisissent plus volontiers un prestataire vérifié.',
                'Certifier mon compte',
              ),
          };

    return FicheCard(
      onTap: action != null ? onTap : null,
      color: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.cardTitle.copyWith(color: color)),
                  const SizedBox(height: 2),
                  Text(text,
                      style: AppText.caption.copyWith(color: AppColors.ink)),
                ],
              ),
            ),
          ]),
          if (action != null) ...[
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(action),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Avancement du profil : la certification s'ouvre à 100 %.
class _ProfileProgress extends StatelessWidget {
  final int done;
  final int total;
  final List<String> missing;
  final VoidCallback? onTap;
  const _ProfileProgress(
      {required this.done,
      required this.total,
      required this.missing,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final complete = missing.isEmpty;
    return FicheCard(
      onTap: onTap,
      color: complete ? AppColors.doneTint : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                complete ? 'Profil complet' : 'Profil à compléter',
                style: AppText.cardTitle
                    .copyWith(color: complete ? AppColors.done : AppColors.ink),
              ),
            ),
            Text('$done/$total',
                style: AppText.cardTitle.copyWith(
                    color: complete ? AppColors.done : AppColors.letterhead)),
          ]),
          const SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: complete ? AppColors.done : AppColors.letterhead,
              backgroundColor: AppColors.surfaceSunk,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            complete
                ? 'Vous pouvez demander le badge « Identité vérifiée ».'
                : 'Manque : ${missing.join(', ')}. Un profil complet débloque la certification.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}
