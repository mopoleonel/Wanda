// dashboard_entreprise_page.dart
// -----------------------------------------------------------------------------
// Tableau de bord entreprise : missions (signalements attribués à
// l'entreprise ou de son secteur), carte, historique, profil.
// -----------------------------------------------------------------------------

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/status_views.dart';
import '../../data/models/entreprise.dart';
import '../../data/models/secteur.dart';
import '../../data/models/signalement.dart';
import 'map_interne_page.dart';

class DashboardEntreprisePage extends ConsumerStatefulWidget {
  const DashboardEntreprisePage({super.key});

  @override
  ConsumerState<DashboardEntreprisePage> createState() =>
      _DashboardEntreprisePageState();
}

class _DashboardEntreprisePageState
    extends ConsumerState<DashboardEntreprisePage> {
  int _selectedIndex = 0;

  Entreprise? entreprise;
  List<Signalement> signalements = [];
  bool isLoading = true;
  bool _loadError = false;

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nomController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String get _userId => ref.read(authRepositoryProvider).currentUserId ?? '';

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    showAppSnackBar(context, message, isError: isError);
  }

  Future<void> _loadData() async {
    if (_userId.isEmpty) return;
    try {
      final ent =
          await ref.read(profileRepositoryProvider).fetchEntreprise(_userId);
      if (ent == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final sigs = await ref
          .read(signalementRepositoryProvider)
          .fetchForEntreprise(_userId, typesDuSecteur(ent.secteurActivite));

      if (mounted) {
        setState(() {
          entreprise = ent;
          _nomController.text = ent.nomEntreprise;
          _phoneController.text = ent.telephone;
          signalements = sigs;
          isLoading = false;
          _loadError = false;
        });
      }
    } on AppException catch (e) {
      // Pas de liste vide trompeuse (« aucune mission ») : on le dit.
      if (mounted) {
        setState(() {
          isLoading = false;
          _loadError = true;
        });
      }
      _showSnackBar(e.message);
    }
  }

  Future<void> _updateLogo() async {
    try {
      final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 70);
      if (image == null) return;
      setState(() => isLoading = true);
      await ref
          .read(profileRepositoryProvider)
          .envoyerPhotoProfil(File(image.path));
      _showSnackBar("Logo mis à jour !", isError: false);
      _loadData();
    } on AppException catch (e) {
      _showSnackBar(e.message);
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    try {
      setState(() => isLoading = true);
      await ref.read(profileRepositoryProvider).updateEntreprise(
            id: _userId,
            nomEntreprise: _nomController.text.trim(),
            // Le numéro est l'identifiant de connexion : non modifiable ici.
            telephone: entreprise?.telephone ?? _phoneController.text,
          );
      _showSnackBar("Profil mis à jour", isError: false);
      _loadData();
    } on AppException catch (e) {
      _showSnackBar(e.message);
      setState(() => isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    if (mounted) context.go(AppRoutes.home);
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded,
            color: AppColors.danger, size: 32),
        title: const Text('Supprimer définitivement ?'),
        content: const Text(
            'Votre entreprise sera retirée de la plateforme et ne recevra plus de missions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Garder')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(profileRepositoryProvider).deleteEntreprise(_userId);
        await _signOut();
      } on AppException catch (e) {
        _showSnackBar(e.message);
      }
    }
  }

  Future<void> _updateStatut(String id, String newStatut) async {
    try {
      await ref.read(signalementRepositoryProvider).updateStatut(id, newStatut);
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showSnackBar(
          switch (newStatut) {
            'en_cours' => 'Mission prise en charge.',
            'resolu' => 'Mission clôturée.',
            'rejete' => 'Signalement rejeté.',
            _ => 'Statut mis à jour.',
          },
          isError: false);
      _loadData();
    } on AppException catch (e) {
      _showSnackBar(e.message);
    }
  }

  /// Rejet (photo hors sujet, doublon, hors secteur) : demande confirmation,
  /// le signalement passe à l'historique avec le tampon REJETÉ.
  Future<void> _confirmReject(Signalement signal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rejeter ce signalement ?'),
        content: const Text(
            'À utiliser pour un doublon, une photo hors sujet ou un incident '
            'qui ne relève pas de votre secteur. Il passera dans '
            "l'historique."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Rejeter')),
        ],
      ),
    );
    if (ok == true) await _updateStatut(signal.id, 'rejete');
  }

  static bool _isActive(Signalement s) =>
      s.statut == 'en_attente' || s.statut == 'en_cours';

  void _launchMaps(double lat, double lng) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => MapInternePage(
                showBack: true,
                destLat: lat,
                destLng: lng,
                allSignalements: signalements)));
  }
  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final body = isLoading
        ? const Center(child: CircularProgressIndicator())
        : switch (_selectedIndex) {
            1 => MapInternePage(allSignalements: signalements),
            2 => _buildHistoryPage(),
            3 => _buildProfilePage(),
            _ => _buildMainDashboard(),
          };
    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.rule)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _countFor('en_attente') > 0,
                label: Text('${_countFor('en_attente')}'),
                child: const Icon(Icons.inbox_outlined),
              ),
              selectedIcon: const Icon(Icons.inbox_rounded),
              label: 'Missions',
            ),
            const NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Carte',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'Historique',
            ),
            const NavigationDestination(
              icon: Icon(Icons.apartment_outlined),
              selectedIcon: Icon(Icons.apartment_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }

  int _countFor(String statut) =>
      signalements.where((s) => s.statut == statut).length;

  Widget _buildMainDashboard() {
    final active = signalements.where(_isActive).toList();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Letterhead(
            overline: entreprise?.secteurActivite ?? 'Espace entreprise',
            title: entreprise?.nomEntreprise ?? 'Entreprise',
            trailing: IdPhoto(
              url: entreprise?.logoUrl,
              size: 44,
              tint: Colors.white,
              fallbackIcon: Icons.apartment_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.xl, AppSpace.gutter, 0),
            child: _buildStatusStrip(),
          ),
          SectionTitle('Missions actives', trailing: '${active.length}'),
          if (_loadError && signalements.isEmpty)
            ErrorStateView(
              message: 'Impossible de charger vos missions.',
              onRetry: () {
                setState(() => isLoading = true);
                _loadData();
              },
            )
          else if (active.isEmpty)
            const EmptyStateView(
              icon: Icons.inbox_outlined,
              title: 'Aucune mission active',
              subtitle:
                  'Les signalements de votre secteur arriveront ici. Tirez vers le bas pour actualiser.',
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
              child: Column(children: [
                for (final s in active) ...[
                  _SignalFiche(signal: s, onTap: () => _showMissionDetails(s)),
                  const SizedBox(height: AppSpace.sm),
                ],
              ]),
            ),
        ],
      ),
    );
  }

  /// Trois cases : reçus / en cours / résolus, à l'encre de leur tampon.
  Widget _buildStatusStrip() {
    Widget cell(FicheStatus status, int count) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            child: Column(children: [
              Text('$count',
                  style: AppText.number.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: status.ink)),
              const SizedBox(height: 2),
              Text(status.label,
                  style: AppText.stamp.copyWith(
                      color: status.ink, fontSize: 12, letterSpacing: 1.2)),
            ]),
          ),
        );

    return FicheCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(children: [
          cell(FicheStatus.signalement('en_attente'), _countFor('en_attente')),
          const VerticalDivider(width: 1),
          cell(FicheStatus.signalement('en_cours'), _countFor('en_cours')),
          const VerticalDivider(width: 1),
          cell(FicheStatus.signalement('resolu'), _countFor('resolu')),
        ]),
      ),
    );
  }

  void _showMissionDetails(Signalement signal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (signal.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.network(signal.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                            color: AppColors.surfaceSunk,
                            child: Icon(Icons.broken_image_outlined))),
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FicheNumber(signal.id),
                      Text(signal.typeProbleme, style: AppText.heading),
                    ],
                  ),
                ),
                StatusStamp(FicheStatus.signalement(signal.statut),
                    large: true),
              ]),
              if (signal.createdAt != null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Signalé le ${DateFormat('dd/MM/yyyy à HH:mm').format(signal.createdAt!.toLocal())}',
                  style: AppText.caption,
                ),
              ],
              if ((signal.iaValidationDetails ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpace.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.stampVioletTint,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 18, color: AppColors.stampViolet),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(signal.iaValidationDetails!,
                            style: AppText.body.copyWith(color: AppColors.ink)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              if (signal.statut == 'en_attente')
                FilledButton.icon(
                  onPressed: () => _updateStatut(signal.id, 'en_cours'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54)),
                  icon: const Icon(Icons.engineering_rounded, size: 20),
                  label: const Text('Prendre en charge'),
                ),
              if (signal.statut == 'en_attente') ...[
                const SizedBox(height: AppSpace.sm),
                TextButton.icon(
                  onPressed: () => _confirmReject(signal),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      minimumSize: const Size(double.infinity, 48)),
                  icon: const Icon(Icons.block_rounded, size: 20),
                  label: const Text('Rejeter le signalement'),
                ),
              ],
              if (signal.statut == 'en_cours')
                FilledButton.icon(
                  onPressed: () => _updateStatut(signal.id, 'resolu'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.done,
                      minimumSize: const Size(double.infinity, 54)),
                  icon: const Icon(Icons.task_alt_rounded, size: 20),
                  label: const Text('Marquer comme résolu'),
                ),
              const SizedBox(height: AppSpace.md),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _launchMaps(signal.latitude, signal.longitude);
                },
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                icon: const Icon(Icons.map_outlined, size: 20),
                label: const Text('Voir sur la carte'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryPage() {
    // Clôturées ou rejetées : tout ce qui n'est plus à traiter.
    final historyData = signalements.where((s) => !_isActive(s)).toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Letterhead(
          title: 'Historique',
          subtitle: historyData.isEmpty
              ? 'Les missions que vous clôturez apparaîtront ici.'
              : '${historyData.length} signalement${historyData.length > 1 ? 's' : ''} traité${historyData.length > 1 ? 's' : ''} (résolus ou rejetés).',
        ),
        if (historyData.isEmpty)
          const EmptyStateView(
            icon: Icons.history_rounded,
            title: 'Aucun historique',
            subtitle: 'Clôturez une mission pour la retrouver ici.',
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xl),
            child: Column(children: [
              for (final s in historyData) ...[
                _SignalFiche(signal: s, onTap: () => _showMissionDetails(s)),
                const SizedBox(height: AppSpace.sm),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _buildProfilePage() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Letterhead(
          title: 'Fiche entreprise',
          subtitle: 'Nom et contact affichés sur vos interventions.',
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
                  label: 'Changer le logo',
                  child: InkWell(
                    onTap: _updateLogo,
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(clipBehavior: Clip.none, children: [
                      IdPhoto(
                          url: entreprise?.logoUrl,
                          size: 96,
                          fallbackIcon: Icons.apartment_rounded),
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
                      Text(entreprise?.nomEntreprise ?? 'Entreprise',
                          style: AppText.sectionTitle),
                      const SizedBox(height: 4),
                      Text(entreprise?.secteurActivite ?? '',
                          style: AppText.caption),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xl),
              _buildEditableField(
                  "Nom de l'entreprise", _nomController, Icons.business),
              const SizedBox(height: AppSpace.lg),
              TextField(
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
              const SizedBox(height: AppSpace.xl),
              FilledButton(
                onPressed: _updateProfile,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54)),
                child: const Text('Enregistrer'),
              ),
              const SizedBox(height: AppSpace.md),
              OutlinedButton.icon(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Se déconnecter'),
              ),
              const SizedBox(height: AppSpace.xl),
              const Divider(),
              const SizedBox(height: AppSpace.sm),
              TextButton.icon(
                onPressed: _deleteAccount,
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text("Supprimer l'entreprise"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditableField(
      String label, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }
}

/// Fiche de signalement côté entreprise.
class _SignalFiche extends StatelessWidget {
  final Signalement signal;
  final VoidCallback onTap;
  const _SignalFiche({required this.signal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = signal.createdAt;
    return FicheCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 64,
            height: 64,
            child: signal.imageUrl.isNotEmpty
                ? Image.network(signal.imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                        color: AppColors.surfaceSunk,
                        child: Icon(Icons.image_outlined,
                            color: AppColors.inkMuted)))
                : const ColoredBox(
                    color: AppColors.surfaceSunk,
                    child:
                        Icon(Icons.image_outlined, color: AppColors.inkMuted)),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(signal.typeProbleme,
                  style: AppText.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                // Flexible : sur petit écran, à côté d'un tampon large, le
                // numéro passe à la ligne au lieu de déborder.
                Flexible(child: FicheNumber(signal.id)),
                if (date != null)
                  Flexible(
                    child: Text(
                      ' · ${DateFormat('dd/MM HH:mm').format(date.toLocal())}',
                      style: AppText.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        StatusStamp(FicheStatus.signalement(signal.statut)),
      ]),
    );
  }
}
