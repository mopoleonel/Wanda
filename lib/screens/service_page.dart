// service_page.dart
// -----------------------------------------------------------------------------
// Redesign notes:
// - Same functionality, same data flow, same Supabase logic as the original.
// - Visual system upgraded: refined color tokens, Manrope/Inter typography
//   (via google_fonts), status badges instead of plain colored text, softer
//   glass-surface cards with real shadows instead of flat borders only,
//   avatars with an accent ring, and a floating pill bottom nav with an
//   animated sliding indicator.
// - Add to pubspec.yaml:  google_fonts: ^6.2.1
// -----------------------------------------------------------------------------

import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// IMPORT DE TA PAGE D'ACCUEIL
import 'package:wanda/screens/homepage.dart';

// =============================================================================
// DESIGN TOKENS
// =============================================================================
class AppColors {
  AppColors._();

  static const bgTop = Color(0xFF06150F);
  static const bgMid = Color(0xFF0B2118);
  static const bgBottom = Color(0xFF123A28);

  // Primary accent: a slightly desaturated emerald/teal, more "product" than
  // a raw neon greenAccent.
  static const accent = Color(0xFF2FE0A8);
  static const accentDeep = Color(0xFF17B686);

  // Secondary accent used sparingly for ratings / premium highlights.
  static const gold = Color(0xFFE0B84B);

  static const danger = Color(0xFFFF6B6B);
  static const warning = Color(0xFFF2B84B);

  static Color surface = Colors.white.withOpacity(0.045);
  static Color surfaceStrong = Colors.white.withOpacity(0.08);
  static Color border = Colors.white.withOpacity(0.09);

  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFB9C9C0);
  static const textMuted = Color(0xFF6F8479);
}

class AppText {
  AppText._();

  static TextStyle heading = GoogleFonts.manrope(
    color: AppColors.textPrimary,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static TextStyle sectionTitle = GoogleFonts.manrope(
    color: AppColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle cardTitle = GoogleFonts.manrope(
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  static TextStyle body = GoogleFonts.inter(
    color: AppColors.textSecondary,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
  );

  static TextStyle caption = GoogleFonts.inter(
    color: AppColors.textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  static TextStyle button = GoogleFonts.manrope(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.3,
  );
}

class AppRadius {
  AppRadius._();
  static const card = 22.0;
  static const sheet = 32.0;
  static const chip = 14.0;
  static const pill = 40.0;
}

// =============================================================================
// PAGE
// =============================================================================
class ServicePage extends StatefulWidget {
  const ServicePage({super.key});
  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  final supabase = Supabase.instance.client;
  int _selectedIndex = 0;

  String selectedCategory = "Tous";
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _photoUrl;

  final List<String> categories = [
    "Tous",
    "Plombier",
    "Électricien",
    "Maçon",
    "Froid & Clim"
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.grid_view_rounded, label: "Accueil"),
    _NavItem(icon: Icons.receipt_long_rounded, label: "Suivi"),
    _NavItem(icon: Icons.person_pin_rounded, label: "Profil"),
    _NavItem(icon: Icons.smart_toy_rounded, label: "IA"),
  ];

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _fetchCitizenData();
    // Refresh périodique pour les timers de l'interface
    Timer.periodic(const Duration(minutes: 1), (t) {
      if (mounted && _selectedIndex == 1) setState(() {});
    });
  }

  // ================= SÉCURITÉ & CONNECTIVITÉ =================

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: AppText.body.copyWith(color: Colors.white))),
        ]),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _checkInitialConnectivity() async {
    var result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) {
      _showErrorSnackBar(
          "Aucune connexion Internet. Vérifiez vos données mobiles.");
    }
  }

  // ================= LOGIQUE DONNÉES (PROFIL) =================

  Future<void> _fetchCitizenData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await supabase
          .from('citoyens')
          .select()
          .eq('citoyen_id', user.id)
          .single()
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _nomController.text = data['nom'] ?? "";
          _prenomController.text = data['prenom'] ?? "";
          _phoneController.text = data['telephone'] ?? "";
          _photoUrl = data['photo_url'];
        });
      }
    } on PostgrestException catch (e) {
      debugPrint("Erreur Supabase: ${e.message}");
    } catch (e) {
      debugPrint("Erreur inattendue: $e");
    }
  }

  // ================= STREAMS TEMPS RÉEL =================

  Stream<List<Map<String, dynamic>>> _getProvidersStream() {
    return supabase
        .from('particuliers')
        .stream(primaryKey: ['id'])
        .eq('is_available', true)
        .handleError(
            (err) => _showErrorSnackBar("Erreur de flux experts: $err"))
        .map((data) {
          if (selectedCategory == "Tous") return data;
          return data
              .where((p) => p['service_propose'] == selectedCategory)
              .toList();
        });
  }

  Stream<List<Map<String, dynamic>>> _getOrdersStream() {
    final user = supabase.auth.currentUser;
    return supabase
        .from('sollicitations')
        .stream(primaryKey: ['id'])
        .eq('citoyen_id', user!.id)
        .order('date_sollicitation', ascending: false)
        .asyncMap((data) async {
          List<Map<String, dynamic>> ordersWithDetails = [];
          for (var order in data) {
            try {
              final expertData = await supabase
                  .from('particuliers')
                  .select(
                      'nom, prenom, telephone, service_propose, photo_pro_url, avis_prestataires(note)')
                  .eq('id', order['prestataire_id'])
                  .single();
              order['expert'] = expertData;
            } catch (e) {
              order['expert'] = null;
            }
            ordersWithDetails.add(order);
          }
          return ordersWithDetails;
        });
  }

  // ================= UTILS =================

  String _getTimerOrEnd(Map order) {
    try {
      if ((order['statut'] == 'termine' || order['statut'] == 'archive') &&
          order['date_fin'] != null) {
        final dateFin = DateTime.parse(order['date_fin']).toLocal();
        return "Fini à ${DateFormat('HH:mm').format(dateFin)}";
      }
      if (order['statut'] == 'accepte') return "L'expert est en route...";
      if (order['date_sollicitation'] == null) return "Calcul...";
      final diff = DateTime.now()
          .difference(DateTime.parse(order['date_sollicitation']));
      return "Lancé il y a ${diff.inHours}h ${diff.inMinutes % 60}m";
    } catch (e) {
      return "Statut mis à jour";
    }
  }

  bool _canCancel(String? dateIso) {
    if (dateIso == null) return false;
    return DateTime.now().difference(DateTime.parse(dateIso)).inMinutes >= 120;
  }

  Future<void> _call(String? t) async {
    if (t == null || t.isEmpty) {
      _showErrorSnackBar("Numéro de l'expert non disponible");
      return;
    }
    try {
      await launchUrl(Uri.parse("tel:$t"));
    } catch (e) {
      _showErrorSnackBar("Impossible de lancer l'appel");
    }
  }

  // ================= ACTIONS & SÉCURITÉ =================

  Future<void> _solicit(Map p) async {
    if (_nomController.text.isEmpty || _phoneController.text.isEmpty) {
      Navigator.pop(context);
      _showErrorSnackBar(
          "Complétez votre profil (Nom et Tel) avant de commander");
      setState(() => _selectedIndex = 2);
      return;
    }

    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('sollicitations').insert({
        'prestataire_id': p['id'],
        'citoyen_id': userId,
        'nom_citoyen': _nomController.text.trim(),
        'prenom_citoyen': _prenomController.text.trim(),
        'numero_citoyen': _phoneController.text.trim(),
        'date_sollicitation': DateTime.now().toIso8601String(),
        'statut': 'en_attente'
      }).timeout(const Duration(seconds: 15));

      Navigator.pop(context);
      setState(() => _selectedIndex = 1);
    } catch (e) {
      Navigator.pop(context);
      _showErrorSnackBar("Erreur lors de la commande. Réessayez.");
    }
  }

  Future<void> _archiveOrder(String id) async {
    try {
      await supabase
          .from('sollicitations')
          .update({'statut': 'archive'}).eq('id', id);
    } catch (e) {
      _showErrorSnackBar("Erreur d'archivage");
    }
  }

  // ================= NAVIGATION PRINCIPALE =================

  @override
  Widget build(BuildContext context) {
    Widget currentBody;
    switch (_selectedIndex) {
      case 0:
        currentBody = _buildHome();
        break;
      case 1:
        currentBody = _buildOrders();
        break;
      case 2:
        currentBody = _buildProfile();
        break;
      case 3:
        currentBody = _buildAiPlaceholder();
        break;
      default:
        currentBody = _buildHome();
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.bgTop, AppColors.bgMid, AppColors.bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                    key: ValueKey(_selectedIndex), child: currentBody),
              ),
            ),
            _buildBottomNavBar(),
          ]),
        ),
      ),
    );
  }

  Widget _buildAiPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: AppColors.accent, size: 34),
          ),
          const SizedBox(height: 16),
          Text("Assistant WANDA AI", style: AppText.sectionTitle),
          const SizedBox(height: 6),
          Text("Bientôt disponible", style: AppText.caption),
        ],
      ),
    );
  }

  // --- VUE 1 : ACCUEIL ---
  // Structure : header d'accroche (salutation + statut live) -> grille de
  // catégories en icônes -> carrousel "Recommandés" (mise en avant) ->
  // liste complète filtrée. L'objectif est de donner un vrai point d'entrée
  // visuel plutôt qu'une simple liste sous un titre.
  Widget _buildHome() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getProvidersStream(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;
        final all = snapshot.data ?? [];
        final featured = all.take(6).toList();

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeroHeader(all.length)),
            SliverToBoxAdapter(child: _buildCategoryGrid()),
            if (!isLoading && !hasError && featured.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _sectionHeader(
                    "Recommandés pour vous", "Les mieux notés du moment"),
              ),
              SliverToBoxAdapter(child: _buildFeaturedCarousel(featured)),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
            SliverToBoxAdapter(
              child: _sectionHeader(
                "Tous les experts",
                isLoading
                    ? "Chargement..."
                    : "${all.length} disponible${all.length > 1 ? 's' : ''}",
              ),
            ),
            if (hasError)
              SliverToBoxAdapter(
                  child: _buildErrorState("Erreur de chargement"))
            else if (isLoading)
              SliverToBoxAdapter(child: _buildLoadingState())
            else if (all.isEmpty)
              SliverToBoxAdapter(
                child: _buildEmptyState(
                  icon: Icons.person_search_rounded,
                  title: "Aucun expert en ligne",
                  subtitle: "Revenez dans quelques instants",
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final p = all[index];
                      return _ProviderCard(
                          data: p, onDetails: () => _showDetails(p, 5.0));
                    },
                    childCount: all.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // --- Header d'accroche ---
  Widget _buildHeroHeader(int onlineCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _prenomController.text.isNotEmpty
                          ? "Bonjour, ${_prenomController.text} 👋"
                          : "Bonjour 👋",
                      style: AppText.caption.copyWith(
                          fontSize: 13.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text("De quoi avez-vous besoin ?",
                        style: AppText.heading
                            .copyWith(fontSize: 24, height: 1.15)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => setState(() => _selectedIndex = 2),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.accentDeep]),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.bgMid,
                    backgroundImage:
                        _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                    child: _photoUrl == null
                        ? const Icon(Icons.person_rounded,
                            color: AppColors.textMuted, size: 22)
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withOpacity(0.25)),
            ),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  onlineCount > 0
                      ? "$onlineCount expert${onlineCount > 1 ? 's' : ''} en ligne actuellement"
                      : "Recherche d'experts en cours...",
                  style: AppText.body.copyWith(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppColors.accent, size: 16),
            ]),
          ),
        ],
      ),
    );
  }

  // --- Grille de catégories en icônes ---
  Widget _buildCategoryGrid() {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSel = selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _CategoryTile(
              label: cat,
              icon: _iconForCategory(cat),
              selected: isSel,
              onTap: () => setState(() => selectedCategory = cat),
            ),
          );
        },
      ),
    );
  }

  IconData _iconForCategory(String cat) {
    switch (cat) {
      case "Plombier":
        return Icons.plumbing_rounded;
      case "Électricien":
        return Icons.electrical_services_rounded;
      case "Maçon":
        return Icons.construction_rounded;
      case "Froid & Clim":
        return Icons.ac_unit_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppText.sectionTitle),
          Text(subtitle, style: AppText.caption),
        ],
      ),
    );
  }

  // --- Carrousel "Recommandés" ---
  Widget _buildFeaturedCarousel(List<Map<String, dynamic>> items) {
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final p = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _FeaturedCard(data: p, onTap: () => _showDetails(p, 5.0)),
          );
        },
      ),
    );
  }

  // --- VUE 2 : SUIVI ---
  Widget _buildOrders() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Suivi d'Activités", style: AppText.heading),
              const SizedBox(height: 2),
              Text("Vos missions en cours et passées", style: AppText.caption),
            ],
          ),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getOrdersStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return _buildLoadingState();
            final myOrders = snapshot.data!;
            if (myOrders.isEmpty) {
              return _buildEmptyState(
                icon: Icons.receipt_long_rounded,
                title: "Aucune mission active",
                subtitle: "Vos demandes apparaîtront ici",
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: myOrders.length,
              itemBuilder: (context, i) {
                final o = myOrders[i];
                return _OrderCard(
                  order: o,
                  timerLabel: _getTimerOrEnd(o),
                  canCancel: _canCancel(o['date_sollicitation']),
                  onCall: () => _call(o['expert']?['telephone']),
                  onArchive: () => _archiveOrder(o['id']),
                  onCancelPressed: () => _showCancelAlert(o),
                  onTimeWarning: () =>
                      _showTimeWarning(o['date_sollicitation']),
                  onRate: () => _ratingModal(o),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  // --- ETATS PARTAGÉS ---

  Widget _buildLoadingState() {
    return const Center(
      child: SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(
            color: AppColors.accent, strokeWidth: 2.4),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child:
          Text(message, style: AppText.body.copyWith(color: AppColors.danger)),
    );
  }

  Widget _buildEmptyState(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.textMuted, size: 28),
          ),
          const SizedBox(height: 14),
          Text(title,
              style:
                  AppText.cardTitle.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(subtitle, style: AppText.caption),
        ],
      ),
    );
  }

  // --- UI DIALOGUES ---

  void _ratingModal(Map o) {
    int r = 0;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 12))
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Noter l'expert", style: AppText.sectionTitle),
              const SizedBox(height: 4),
              Text("Comment s'est passée la mission ?", style: AppText.caption),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    icon: Icon(
                        i < r ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: AppColors.gold,
                        size: 30),
                    onPressed: () => setD(() => r = i + 1),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: ctrl,
                  style: AppText.body.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Laissez un avis (optionnel)",
                    hintStyle: AppText.caption,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (r == 0) {
                      _showErrorSnackBar("Veuillez sélectionner une note");
                      return;
                    }
                    await supabase.from('avis_prestataires').insert({
                      'sollicitation_id': o['id'],
                      'prestataire_id': o['prestataire_id'],
                      'citoyen_id': supabase.auth.currentUser!.id,
                      'note': r,
                      'commentaire': ctrl.text
                    });
                    _archiveOrder(o['id']);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text("VALIDER",
                      style: AppText.button.copyWith(color: Colors.black)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showTimeWarning(String? d) {
    if (d == null) return;
    final diff = DateTime.now().difference(DateTime.parse(d));
    final restant = 120 - diff.inMinutes;
    _showInfoDialog(
      icon: Icons.schedule_rounded,
      iconColor: AppColors.warning,
      title: "Délai de sécurité",
      message:
          "L'expert a déjà mobilisé son temps. Vous pourrez annuler librement dans $restant minutes.",
      primaryLabel: "PATIENTER",
      onPrimary: () => Navigator.pop(context),
    );
  }

  void _showCancelAlert(Map order) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.bgMid,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 26),
            ),
            const SizedBox(height: 14),
            Text("Annuler la mission ?", style: AppText.sectionTitle),
            const SizedBox(height: 8),
            Text(
              "L'expert a peut-être déjà commencé sa route. Voulez-vous vraiment annuler ?",
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text("RETOUR",
                      style: AppText.button
                          .copyWith(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await supabase
                        .from('sollicitations')
                        .update({'statut': 'annule'}).eq('id', order['id']);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text("OUI, ANNULER",
                      style: AppText.button.copyWith(color: Colors.white)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showInfoDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String primaryLabel,
    required VoidCallback onPrimary,
  }) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.bgMid,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, style: AppText.sectionTitle),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: AppText.body),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(primaryLabel,
                    style: AppText.button.copyWith(color: Colors.black)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // --- PROFIL & NAV ---

  Widget _buildProfile() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: Column(children: [
        Text("Mon Profil", style: AppText.heading),
        const SizedBox(height: 4),
        Text("Gérez vos informations personnelles", style: AppText.caption),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: _pickImg,
          child: Stack(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.accentDeep]),
              ),
              child: CircleAvatar(
                radius: 56,
                backgroundColor: AppColors.bgMid,
                backgroundImage:
                    _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                child: _photoUrl == null
                    ? const Icon(Icons.person_rounded,
                        color: AppColors.textMuted, size: 46)
                    : null,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bgMid, width: 3),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.black, size: 16),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 32),
        _input("Nom complet", _nomController, Icons.badge_outlined),
        _input("Prénom", _prenomController, Icons.person_outline_rounded),
        _input("Téléphone mobile", _phoneController, Icons.phone_outlined),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _updateProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              elevation: 0,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Text("SAUVEGARDER",
                style:
                    AppText.button.copyWith(color: Colors.black, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await supabase.auth.signOut();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => HomePage(
                      onSelectRole: (r) {}, onPrestataireClick: () {})),
              (r) => false,
            );
          },
          child: Text("DÉCONNEXION",
              style: AppText.caption.copyWith(letterSpacing: 0.5)),
        ),
      ]),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      height: 68,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.bgTop.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: LayoutBuilder(builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / _navItems.length;
            return Stack(children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  -1 + (2 * _selectedIndex) / (_navItems.length - 1),
                  0,
                ),
                child: Container(
                  width: itemWidth,
                  height: double.infinity,
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border:
                          Border.all(color: AppColors.accent.withOpacity(0.4)),
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(
                    _navItems.length, (idx) => _navIcon(idx, itemWidth)),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _navIcon(int idx, double width) {
    final isSel = _selectedIndex == idx;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => setState(() => _selectedIndex = idx),
        child: Icon(
          _navItems[idx].icon,
          color: isSel ? AppColors.accent : AppColors.textMuted,
          size: 24,
        ),
      ),
    );
  }

  void _showDetails(Map p, double avg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 30),
          decoration: BoxDecoration(
            color: AppColors.bgTop.withOpacity(0.97),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 22),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4)),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.accentDeep]),
              ),
              child: CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.bgMid,
                backgroundImage: p['photo_pro_url'] != null
                    ? NetworkImage(p['photo_pro_url'])
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text("${p['nom']} ${p['prenom'] ?? ''}",
                style: AppText.sectionTitle),
            const SizedBox(height: 4),
            Text(p['service_propose'] ?? "Expert",
                style: AppText.body.copyWith(color: AppColors.accent)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, color: AppColors.gold, size: 18),
                const SizedBox(width: 4),
                Text("${avg.toStringAsFixed(1)} / 5",
                    style: AppText.cardTitle
                        .copyWith(color: AppColors.gold, fontSize: 14)),
              ]),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _solicit(p),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text("SOLLICITER CE PRESTATAIRE",
                    style: AppText.button.copyWith(color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 58),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _updateProfile() async {
    try {
      await supabase
          .from('citoyens')
          .update({
            'nom': _nomController.text.trim(),
            'prenom': _prenomController.text.trim(),
            'telephone': _phoneController.text.trim()
          })
          .eq('citoyen_id', supabase.auth.currentUser!.id)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Text("Profil synchronisé avec succès",
              style: AppText.body.copyWith(color: Colors.white)),
        ]),
        backgroundColor: AppColors.accentDeep,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ));
    } catch (e) {
      _showErrorSnackBar("Erreur de sauvegarde. Vérifiez votre connexion.");
    }
  }

  Future<void> _pickImg() async {
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (img != null) {
        final userId = supabase.auth.currentUser!.id;
        final file = File(img.path);
        await supabase.storage.from('profils').upload(
            'citoyen_$userId.jpg', file,
            fileOptions: const FileOptions(upsert: true));
        final url = supabase.storage
            .from('profils')
            .getPublicUrl('citoyen_$userId.jpg');
        await supabase
            .from('citoyens')
            .update({'photo_url': url}).eq('citoyen_id', userId);
        setState(() => _photoUrl = url);
      }
    } catch (e) {
      _showErrorSnackBar("Erreur lors de la mise à jour de la photo");
    }
  }

  Widget _input(String l, TextEditingController c, IconData i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: TextField(
          controller: c,
          style: AppText.body.copyWith(color: Colors.white, fontSize: 14.5),
          decoration: InputDecoration(
            labelText: l,
            labelStyle: AppText.caption,
            prefixIcon: Icon(i, color: AppColors.accent, size: 20),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

// =============================================================================
// COMPOSANTS RÉUTILISABLES
// =============================================================================

/// Carte expert affichée dans la liste d'accueil.
/// Tuile de catégorie en icône (grille horizontale sur l'accueil).
class _CategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? AppColors.accent : AppColors.border),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.accent.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? Colors.black : AppColors.accent, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: selected ? Colors.black : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte de mise en avant du carrousel "Recommandés" en haut de l'accueil.
class _FeaturedCard extends StatelessWidget {
  final Map data;
  final VoidCallback onTap;
  const _FeaturedCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = data['photo_pro_url'] != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 165,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 8))
          ],
          image: hasPhoto
              ? DecorationImage(
                  image: NetworkImage(data['photo_pro_url']), fit: BoxFit.cover)
              : null,
          gradient: hasPhoto
              ? null
              : const LinearGradient(
                  colors: [AppColors.accentDeep, AppColors.bgMid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.35, 1.0],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.gold, size: 13),
                    const SizedBox(width: 2),
                    Text("5.0",
                        style: AppText.caption
                            .copyWith(color: Colors.white, fontSize: 10.5)),
                  ]),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${data['nom']} ${data['prenom'] ?? ''}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle.copyWith(fontSize: 14.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data['service_propose'] ?? "Expert",
                    style: AppText.caption
                        .copyWith(color: AppColors.accent, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final Map data;
  final VoidCallback onDetails;
  const _ProviderCard({required this.data, required this.onDetails});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                colors: [AppColors.accent, AppColors.accentDeep]),
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.bgMid,
            backgroundImage: data['photo_pro_url'] != null
                ? NetworkImage(data['photo_pro_url'])
                : null,
            child: data['photo_pro_url'] == null
                ? const Icon(Icons.person_rounded,
                    color: AppColors.textMuted, size: 26)
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${data['nom']} ${data['prenom'] ?? ''}",
                  style: AppText.cardTitle),
              const SizedBox(height: 3),
              Text(data['service_propose'] ?? "Expert",
                  style: AppText.body
                      .copyWith(color: AppColors.accent, fontSize: 12.5)),
              const SizedBox(height: 5),
              Row(children: [
                const Icon(Icons.star_rounded, color: AppColors.gold, size: 15),
                const SizedBox(width: 2),
                Text("5.0",
                    style: AppText.caption
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text("Disponible", style: AppText.caption),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onDetails,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceStrong,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text("Détails",
                style: AppText.body.copyWith(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

/// Badge de statut coloré pour les commandes.
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  ({String label, Color color}) get _meta {
    switch (status) {
      case 'accepte':
        return (label: "En route", color: AppColors.accent);
      case 'termine':
        return (label: "Terminé", color: AppColors.gold);
      case 'archive':
        return (label: "Archivé", color: AppColors.textMuted);
      case 'annule':
        return (label: "Annulé", color: AppColors.danger);
      default:
        return (label: "En attente", color: AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: m.color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: m.color.withOpacity(0.35)),
      ),
      child: Text(
        m.label,
        style: AppText.caption.copyWith(
            color: m.color, fontWeight: FontWeight.w700, fontSize: 10.5),
      ),
    );
  }
}

/// Carte de mission affichée dans le suivi d'activités.
class _OrderCard extends StatelessWidget {
  final Map order;
  final String timerLabel;
  final bool canCancel;
  final VoidCallback onCall;
  final VoidCallback onArchive;
  final VoidCallback onCancelPressed;
  final VoidCallback onTimeWarning;
  final VoidCallback onRate;

  const _OrderCard({
    required this.order,
    required this.timerLabel,
    required this.canCancel,
    required this.onCall,
    required this.onArchive,
    required this.onCancelPressed,
    required this.onTimeWarning,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final expert = order['expert'];
    final status = order['statut'];
    final isAccepted = status == 'accepte';
    final isDoneByPro = status == 'termine';
    final isArchived = status == 'archive';
    final isCanceled = status == 'annule';
    final isFinalState = isArchived || isCanceled;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: (isAccepted || isDoneByPro)
              ? AppColors.accent.withOpacity(0.3)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.surfaceStrong,
            backgroundImage: expert?['photo_pro_url'] != null
                ? NetworkImage(expert?['photo_pro_url'])
                : null,
            child: expert?['photo_pro_url'] == null
                ? const Icon(Icons.person_rounded,
                    color: AppColors.accent, size: 22)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      "${expert?['nom'] ?? 'Expert'} ${expert?['prenom'] ?? ''}",
                      style: AppText.cardTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusBadge(status: status),
                ]),
                const SizedBox(height: 4),
                Text(expert?['service_propose'] ?? "WANDA Expert",
                    style: AppText.body
                        .copyWith(color: AppColors.accent, fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                  timerLabel,
                  style: AppText.caption.copyWith(
                    color: (isAccepted || isDoneByPro || isArchived)
                        ? AppColors.accent
                        : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          if (isFinalState)
            IconButton(
              icon: const Icon(Icons.archive_outlined,
                  color: AppColors.textMuted, size: 20),
              onPressed: onArchive,
            )
          else if (isAccepted || isDoneByPro)
            IconButton(
              icon: const Icon(Icons.call_rounded,
                  color: AppColors.accent, size: 20),
              onPressed: onCall,
            ),
        ]),
        if (!isFinalState) ...[
          const SizedBox(height: 14),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canCancel ? onCancelPressed : onTimeWarning,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: canCancel
                          ? AppColors.danger.withOpacity(0.4)
                          : AppColors.border),
                  backgroundColor: canCancel
                      ? AppColors.danger.withOpacity(0.08)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text("ANNULER",
                    style: AppText.button.copyWith(
                        color:
                            canCancel ? AppColors.danger : AppColors.textMuted,
                        fontSize: 11.5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: status == 'termine' ? onRate : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: status == 'termine'
                      ? AppColors.accent
                      : AppColors.surfaceStrong,
                  disabledBackgroundColor: AppColors.surfaceStrong,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text("NOTER & FINIR",
                    style: AppText.button.copyWith(
                        color: status == 'termine'
                            ? Colors.black
                            : AppColors.textMuted,
                        fontSize: 11.5)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
