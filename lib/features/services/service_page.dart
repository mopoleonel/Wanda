// service_page.dart
// -----------------------------------------------------------------------------
// Marketplace citoyen : experts disponibles en temps réel (liste ou carte),
// sollicitation, suivi des demandes (fiches numérotées et tamponnées),
// profil, assistant.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/status_views.dart';
import '../../data/models/avis_prestataire.dart';
import '../../data/models/citoyen.dart';
import '../../data/models/particulier.dart';
import '../../data/models/sollicitation.dart';
import 'prestataire_marker_factory.dart';

class ServicePage extends ConsumerStatefulWidget {
  /// Métier présélectionné (ex. « Plombier ») quand on arrive depuis une
  /// tuile métier de l'espace citoyen.
  final String? initialCategory;

  const ServicePage({super.key, this.initialCategory});
  @override
  ConsumerState<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends ConsumerState<ServicePage> {
  int _selectedIndex = 0;

  String selectedCategory = "Tous";
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String? _photoUrl;

  Position? _myPosition;
  Map<String, RatingSummary> _ratings = {};
  bool _showMap = false;
  Set<Marker> _mapMarkers = {};
  String? _markersSignature;
  GoogleMapController? _mapController;
  BitmapDescriptor? _userIcon;
  List<Particulier> _mapProviders = const [];
  final PageController _carousel = PageController(viewportFraction: 0.88);
  bool _locationOff = false;

  final List<String> categories = TradeStyle.names;
  Timer? _clock;

  // Flux temps réel : un seul abonnement par écran (et non un par
  // reconstruction), les dernières données sont gardées ici.
  StreamSubscription<List<Particulier>>? _providersSub;
  List<Particulier> _allProviders = const [];
  bool _providersLoaded = false;
  bool _providersError = false;

  StreamSubscription<List<Sollicitation>>? _ordersSub;
  List<Sollicitation>? _orders;
  bool _ordersError = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null && categories.contains(initial)) {
      selectedCategory = initial;
    }
    _checkInitialConnectivity();
    _fetchCitizenData();
    _fetchMyPosition();
    _listenProviders();
    _listenOrders();
    PrestataireMarkerFactory.buildUser().then((icon) {
      if (mounted) setState(() => _userIcon = icon);
    });
    // Rafraîchit les durées affichées dans l'onglet Suivi.
    _clock = Timer.periodic(const Duration(minutes: 1), (t) {
      if (mounted && _selectedIndex == 1) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _providersSub?.cancel();
    _ordersSub?.cancel();
    _nomController.dispose();
    _prenomController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _mapController?.dispose();
    _carousel.dispose();
    super.dispose();
  }

  // ================= SÉCURITÉ & CONNECTIVITÉ =================

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    showAppSnackBar(context, message);
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) {
        _showErrorSnackBar(
            "Aucune connexion Internet. Vérifiez vos données mobiles.");
      }
    } catch (_) {
      // Vérification indicative : les erreurs réseau seront signalées
      // par les écrans eux-mêmes.
    }
  }

  // ================= LOCALISATION (matching par proximité) =================

  Future<void> _fetchMyPosition() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Le tri par distance est simplement désactivé ; on le signale.
        if (mounted) setState(() => _locationOff = true);
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _myPosition = position;
        _locationOff = false;
      });
      // La position arrive souvent après la carte : on recadre.
      _fitCameraToMarkers(_withLocation(_mapProviders));
    } catch (_) {
      // Pas bloquant : la liste reste utilisable sans tri par distance.
      if (mounted) setState(() => _locationOff = true);
    }
  }

  double? _distanceToMeters(Particulier p) {
    if (_myPosition == null || p.latitude == null || p.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
      _myPosition!.latitude,
      _myPosition!.longitude,
      p.latitude!,
      p.longitude!,
    );
  }

  List<Particulier> _sortByDistance(List<Particulier> providers) {
    final withDistance = <MapEntry<Particulier, double>>[];
    final withoutDistance = <Particulier>[];
    for (final p in providers) {
      final d = _distanceToMeters(p);
      if (d != null) {
        withDistance.add(MapEntry(p, d));
      } else {
        withoutDistance.add(p);
      }
    }
    withDistance.sort((a, b) => a.value.compareTo(b.value));
    return [...withDistance.map((e) => e.key), ...withoutDistance];
  }

  // ================= LOGIQUE DONNÉES (PROFIL) =================

  Future<void> _fetchCitizenData() async {
    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (userId == null) return;
    try {
      final data =
          await ref.read(profileRepositoryProvider).fetchCitoyen(userId);
      if (mounted && data != null) {
        setState(() {
          _nomController.text = data.nom;
          _prenomController.text = data.prenom;
          _phoneController.text = data.telephone;
          _emailController.text = data.email;
          _photoUrl = data.photoUrl;
        });
      }
    } on AppException catch (e) {
      debugPrint("Erreur profil citoyen: ${e.message}");
    }
  }

  // ================= STREAMS TEMPS RÉEL =================

  void _listenProviders() {
    _providersSub?.cancel();
    setState(() => _providersError = false);
    _providersSub =
        ref.read(prestataireRepositoryProvider).streamAvailable().listen(
      (providers) {
        if (!mounted) return;
        setState(() {
          _allProviders = providers;
          _providersLoaded = true;
          _providersError = false;
        });
        _refreshRatingsFor(providers);
      },
      onError: (Object _) {
        if (mounted) setState(() => _providersError = true);
      },
    );
  }

  /// Experts du métier choisi, du plus proche au plus éloigné.
  List<Particulier> get _visibleProviders =>
      _sortByDistance(selectedCategory == 'Tous'
          ? _allProviders
          : _allProviders
              .where((p) => p.servicePropose == selectedCategory)
              .toList());

  Future<void> _refreshRatingsFor(List<Particulier> providers) async {
    final missingIds = providers
        .map((p) => p.id)
        .where((id) => !_ratings.containsKey(id))
        .toList();
    if (missingIds.isEmpty) return;
    try {
      final fresh = await ref
          .read(avisRepositoryProvider)
          .averagesForPrestataires(missingIds);
      if (mounted && fresh.isNotEmpty) {
        setState(() => _ratings = {..._ratings, ...fresh});
      }
    } catch (_) {
      // La note s'affichera simplement comme "Nouveau" en attendant.
    }
  }

  RatingSummary _ratingFor(String prestataireId) =>
      _ratings[prestataireId] ?? RatingSummary.empty;

  // ================= CARTE : marqueurs prestataires =================

  /// Ne reconstruit les bitmaps de marqueurs que si la liste de prestataires
  /// géolocalisés a réellement changé — le rendu Canvas + le chargement des
  /// photos sont trop coûteux pour être refaits à chaque frame.
  Future<void> _rebuildMarkersIfNeeded(List<Particulier> providers) async {
    final withLocation = _withLocation(providers);
    final signature = withLocation
        .map((p) =>
            '${p.id}:${p.photoProUrl}:${p.isAvailable}:${p.servicePropose}')
        .join('|');
    if (signature == _markersSignature) return;
    _markersSignature = signature;

    final markers = <Marker>{};
    for (final p in withLocation) {
      final icon = await PrestataireMarkerFactory.build(
        id: p.id,
        photoUrl: p.photoProUrl,
        trade: p.servicePropose,
        isOnline: p.isAvailable,
      );
      markers.add(Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.latitude!, p.longitude!),
        icon: icon,
        anchor: const Offset(0.5, 0.62),
        // On gère nous-mêmes le toucher : fiche détaillée du prestataire.
        consumeTapEvents: true,
        onTap: () => _onProviderMarkerTap(p),
      ));
    }
    if (mounted) setState(() => _mapMarkers = markers);
    await _fitCameraToMarkers(withLocation);
  }

  List<Particulier> _withLocation(List<Particulier> providers) => providers
      .where((p) => p.latitude != null && p.longitude != null)
      .toList();

  /// Prestataires géolocalisés, du plus proche au plus éloigné.
  List<Particulier> _nearestFirst(List<Particulier> providers) =>
      _sortByDistance(_withLocation(providers));

  void _onProviderMarkerTap(Particulier p) {
    final index = _nearestFirst(_mapProviders).indexWhere((e) => e.id == p.id);
    if (index >= 0 && _carousel.hasClients) {
      _carousel.animateToPage(index,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _showDetails(p);
  }

  /// Cadrage : l'utilisateur reste au centre et la carte s'élargit juste
  /// assez pour montrer le maximum de prestataires proches (ceux à moins de
  /// [_nearbyRadiusM], ou à défaut les 3 plus proches). Sans position
  /// connue, on englobe simplement tous les prestataires.
  static const double _nearbyRadiusM = 15000;

  Future<void> _fitCameraToMarkers(List<Particulier> withLocation) async {
    final controller = _mapController;
    if (controller == null) return;
    final me = _myPosition;

    if (me == null) {
      if (withLocation.isEmpty) return;
      await _fitBounds(controller,
          [for (final p in withLocation) LatLng(p.latitude!, p.longitude!)]);
      return;
    }

    final sorted = _sortByDistance(withLocation);
    var framed = sorted
        .where(
            (p) => (_distanceToMeters(p) ?? double.infinity) <= _nearbyRadiusM)
        .toList();
    if (framed.isEmpty) framed = sorted.take(3).toList();

    final center = LatLng(me.latitude, me.longitude);
    if (framed.isEmpty) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(center, 15));
      return;
    }

    // Boîte symétrique autour de l'utilisateur pour le garder au centre.
    var dLat = 0.004, dLng = 0.004; // ~450 m minimum
    for (final p in framed) {
      dLat = math.max(dLat, (p.latitude! - me.latitude).abs());
      dLng = math.max(dLng, (p.longitude! - me.longitude).abs());
    }
    dLat *= 1.15;
    dLng *= 1.15;
    await _fitBounds(controller, [
      LatLng(me.latitude - dLat, me.longitude - dLng),
      LatLng(me.latitude + dLat, me.longitude + dLng),
    ]);
  }

  Future<void> _fitBounds(
      GoogleMapController controller, List<LatLng> points) async {
    if (points.length == 1) {
      await controller
          .animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final pt in points) {
      minLat = math.min(minLat, pt.latitude);
      maxLat = math.max(maxLat, pt.latitude);
      minLng = math.min(minLng, pt.longitude);
      maxLng = math.max(maxLng, pt.longitude);
    }
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        48,
      ));
    } catch (_) {
      // Bornes dégénérées : repli sur un zoom fixe.
      await controller.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2), 14));
    }
  }

  Future<void> _recenter() async {
    if (_myPosition == null) await _fetchMyPosition();
    await _fitCameraToMarkers(_withLocation(_mapProviders));
  }

  Widget _buildMapView(List<Particulier> providers) {
    _mapProviders = providers;
    _rebuildMarkersIfNeeded(providers);
    final me = _myPosition;
    final center = me != null
        ? LatLng(me.latitude, me.longitude)
        : (providers.isNotEmpty && providers.first.latitude != null
            ? LatLng(providers.first.latitude!, providers.first.longitude!)
            : const LatLng(3.848, 11.502)); // Yaoundé par défaut.

    final markers = <Marker>{
      ..._mapMarkers,
      if (me != null)
        Marker(
          markerId: const MarkerId('moi'),
          position: LatLng(me.latitude, me.longitude),
          icon: _userIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor:
              _userIcon != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1),
          zIndexInt: 10,
          infoWindow: const InfoWindow(title: 'Vous êtes ici'),
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 13.5),
      // Notre propre marqueur rouge remplace le point bleu de Google.
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      // Laisse la place au bandeau du haut et au carrousel du bas.
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 96,
        bottom: _carouselHeight + 24,
      ),
      markers: markers,
      onMapCreated: (controller) {
        _mapController = controller;
        _fitCameraToMarkers(_withLocation(providers));
      },
    );
  }

  void _listenOrders() {
    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (userId == null) {
      _orders = const [];
      return;
    }
    _ordersSub?.cancel();
    setState(() => _ordersError = false);
    _ordersSub = ref
        .read(sollicitationRepositoryProvider)
        .streamForCitoyen(userId)
        .listen(
      (orders) {
        if (mounted) {
          setState(() {
            _orders = orders;
            _ordersError = false;
          });
        }
      },
      onError: (Object _) {
        if (mounted) setState(() => _ordersError = true);
      },
    );
  }

  // ================= UTILS =================

  String _getTimerOrEnd(Sollicitation order) {
    try {
      if ((order.statut == 'termine' || order.statut == 'archive') &&
          order.dateFin != null) {
        return "Terminée à ${DateFormat('HH:mm').format(order.dateFin!.toLocal())}";
      }
      if (order.statut == 'accepte') return "L'expert est en route…";
      if (order.statut == 'annule') return 'Demande annulée';
      if (order.dateSollicitation == null) return 'Envoyée';
      return 'Envoyée ${sinceLabel(order.dateSollicitation!)}';
    } catch (e) {
      return "Statut mis à jour";
    }
  }

  bool _canCancel(DateTime? date) {
    if (date == null) return false;
    return DateTime.now().difference(date).inMinutes >= 120;
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

  String? _formatDistance(Particulier p) {
    final meters = _distanceToMeters(p);
    if (meters == null) return null;
    return distanceLabel(meters);
  }

  // ================= ACTIONS & SÉCURITÉ =================

  Future<void> _solicit(Particulier p) async {
    if (_nomController.text.isEmpty || _phoneController.text.isEmpty) {
      Navigator.pop(context);
      _showErrorSnackBar(
          "Complétez votre profil (Nom et Tel) avant de commander");
      setState(() => _selectedIndex = 2);
      return;
    }

    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (userId == null) return;

    try {
      await ref.read(sollicitationRepositoryProvider).create(
            prestataireId: p.id,
            citoyenId: userId,
            nomCitoyen: _nomController.text.trim(),
            prenomCitoyen: _prenomController.text.trim(),
            numeroCitoyen: _phoneController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _selectedIndex = 1);
    } on AppException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showErrorSnackBar(e.message);
    }
  }

  Future<void> _archiveOrder(String id) async {
    try {
      await ref.read(sollicitationRepositoryProvider).archive(id);
    } on AppException catch (e) {
      _showErrorSnackBar(e.message);
    }
  }

  // ================= NAVIGATION PRINCIPALE =================

  @override
  Widget build(BuildContext context) {
    final body = switch (_selectedIndex) {
      1 => _buildOrders(),
      2 => _buildProfile(),
      3 => _buildAssistant(),
      _ => _buildHome(),
    };

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        child: KeyedSubtree(key: ValueKey(_selectedIndex), child: body),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.rule)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.handyman_outlined),
              selectedIcon: Icon(Icons.handyman_rounded),
              label: 'Experts',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Mes demandes',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'Assistant',
            ),
          ],
        ),
      ),
    );
  }

  // ================= ONGLET EXPERTS =================

  Widget _buildHome() {
    final all = _visibleProviders;
    // Une erreur après un premier chargement n'efface pas la liste.
    final hasError = _providersError && !_providersLoaded;
    final isLoading = !_providersLoaded && !hasError;
    if (_showMap) return _buildMapScreen(all);
    return _buildListView(all, isLoading, hasError);
  }

  /// Experts les mieux notés (au moins un avis), pour la rangée du haut.
  List<Particulier> _topRated(List<Particulier> all) {
    final rated = all.where((p) => _ratingFor(p.id).count > 0).toList()
      ..sort((a, b) {
        final ra = _ratingFor(a.id), rb = _ratingFor(b.id);
        final byAvg = rb.average.compareTo(ra.average);
        return byAvg != 0 ? byAvg : rb.count.compareTo(ra.count);
      });
    return rated.take(6).toList();
  }

  Widget _buildListView(List<Particulier> all, bool isLoading, bool hasError) {
    final topRated = _topRated(all);
    return RefreshIndicator(
      onRefresh: () async {
        _ratings = {};
        await _fetchMyPosition();
        if (mounted) setState(() {});
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(all.length, isLoading)),
          SliverToBoxAdapter(child: _buildTradeTabs()),
          SliverToBoxAdapter(child: _buildReportEntry()),
          if (_locationOff) SliverToBoxAdapter(child: _buildLocationBanner()),
          if (!isLoading && !hasError && topRated.length >= 2) ...[
            const SliverToBoxAdapter(child: SectionTitle('Les mieux notés')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                  itemCount: topRated.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpace.md),
                  itemBuilder: (context, i) {
                    final p = topRated[i];
                    return _TopRatedFiche(
                      data: p,
                      rating: _ratingFor(p.id),
                      onTap: () => _showDetails(p),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.md),
              child: Row(children: [
                Expanded(
                  child: Text(
                    selectedCategory == 'Tous'
                        ? 'Experts disponibles'
                        : '${selectedCategory}s disponibles'
                            .replaceAll('Froid & Clims', 'Froid & Clim'),
                    style: AppText.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                _viewModeToggle(),
              ]),
            ),
          ),
          if (hasError)
            SliverToBoxAdapter(
              child: ErrorStateView(
                message: 'Impossible de charger les experts.',
                onRetry: _listenProviders,
              ),
            )
          else if (isLoading)
            const SliverToBoxAdapter(child: LoadingView())
          else if (all.isEmpty)
            SliverToBoxAdapter(
              child: EmptyStateView(
                icon: Icons.person_search_rounded,
                title: selectedCategory == 'Tous'
                    ? 'Aucun expert en ligne'
                    : 'Aucun ${selectedCategory.toLowerCase()} en ligne',
                subtitle:
                    'Les experts se connectent tout au long de la journée.',
                action: selectedCategory == 'Tous'
                    ? null
                    : OutlinedButton(
                        onPressed: () =>
                            setState(() => selectedCategory = 'Tous'),
                        child: const Text('Voir tous les métiers'),
                      ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
              sliver: SliverList.separated(
                itemCount: all.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpace.sm),
                itemBuilder: (context, index) {
                  final p = all[index];
                  return _ExpertRow(
                    data: p,
                    rating: _ratingFor(p.id),
                    distanceLabel: _formatDistance(p),
                    onTap: () => _showDetails(p),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(int onlineCount, bool isLoading) {
    final prenom = _prenomController.text.trim();
    return Letterhead(
      overline: prenom.isNotEmpty ? 'Bonjour, $prenom' : 'Bonjour',
      title: 'De quoi avez-vous besoin ?',
      trailing: Semantics(
        button: true,
        label: 'Mon profil',
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = 2),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: IdPhoto(url: _photoUrl, size: 40, tint: Colors.white),
          ),
        ),
      ),
      bottom: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: AppColors.brandLeaf, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isLoading
                ? 'Recherche des experts en ligne…'
                : onlineCount > 0
                    ? '$onlineCount expert${onlineCount > 1 ? 's' : ''} disponible${onlineCount > 1 ? 's' : ''} maintenant'
                    : 'Aucun expert en ligne pour le moment',
            style: AppText.label.copyWith(color: AppColors.onLetterheadSoft),
          ),
        ),
      ]),
    );
  }

  /// Sans localisation, pas de distances ni de tri par proximité : on le dit
  /// et on propose de réessayer (ou d'ouvrir les réglages).
  Widget _buildLocationBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.sm, AppSpace.gutter, 0),
      child: FicheCard(
        onTap: () async {
          final permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.deniedForever) {
            await Geolocator.openAppSettings();
          } else {
            await _fetchMyPosition();
          }
        },
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          const Icon(Icons.location_off_outlined,
              color: AppColors.inkSoft, size: 20),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
                'Activez la localisation pour voir les experts les plus proches',
                style: AppText.caption.copyWith(color: AppColors.ink)),
          ),
          Text('Activer',
              style: AppText.label.copyWith(color: AppColors.letterhead)),
        ]),
      ),
    );
  }

  /// Accès direct au signalement d'incident, juste sous les métiers :
  /// visible dès l'arrivée, sans passer devant la recherche d'artisan.
  Widget _buildReportEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
      child: Semantics(
        button: true,
        child: FicheCard(
          onTap: () => context.push(AppRoutes.citoyenSignal),
          color: const Color(0xFFFFF8DC),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF7E9A6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.campaign_rounded,
                  color: Color(0xFF6E5400), size: 22),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Un problème dans votre quartier ?',
                      style: AppText.caption),
                  Text('Signaler un incident',
                      style: AppText.cardTitle.copyWith(fontSize: 15)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF6E5400)),
          ]),
        ),
      ),
    );
  }

  /// Onglets métier : une copie carbone colorée par métier.
  Widget _buildTradeTabs() {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, 0),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, index) {
          final cat = categories[index];
          return _TradeTab(
            style: TradeStyle.of(cat),
            selected: selectedCategory == cat,
            onTap: () => setState(() => selectedCategory = cat),
          );
        },
      ),
    );
  }

  Widget _viewModeToggle() {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -2, vertical: -1),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      segments: const [
        ButtonSegment(
            value: false,
            icon: Icon(Icons.view_list_rounded, size: 18),
            label: Text('Liste')),
        ButtonSegment(
            value: true,
            icon: Icon(Icons.map_outlined, size: 18),
            label: Text('Carte')),
      ],
      selected: {_showMap},
      onSelectionChanged: (s) => setState(() => _showMap = s.first),
    );
  }

  static const double _carouselHeight = 104;

  Widget _buildMapScreen(List<Particulier> all) {
    final topInset = MediaQuery.paddingOf(context).top;
    final nearby = _nearestFirst(all);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Stack(children: [
        Positioned.fill(child: _buildMapView(all)),
        Positioned(
          top: topInset + AppSpace.md,
          left: AppSpace.gutter,
          right: AppSpace.gutter,
          child: FicheCard(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Experts autour de vous', style: AppText.cardTitle),
                    Text(
                      '${all.length} en ligne · ${TradeStyle.of(selectedCategory).label}',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              _viewModeToggle(),
            ]),
          ),
        ),
        // Recentrer sur soi et les prestataires proches.
        Positioned(
          right: AppSpace.gutter,
          bottom: (nearby.isEmpty ? 0 : _carouselHeight) + AppSpace.xl,
          child: FloatingActionButton.small(
            heroTag: 'recentrer',
            tooltip: 'Recentrer sur moi',
            onPressed: _recenter,
            backgroundColor: AppColors.surface,
            foregroundColor: const Color(0xFFD32F2F),
            elevation: 2,
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
        if (_myPosition == null)
          Positioned(
            left: AppSpace.gutter,
            right: 72,
            bottom: (nearby.isEmpty ? 0 : _carouselHeight) + AppSpace.xl,
            child: FicheCard(
              onTap: _recenter,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.location_off_outlined,
                    size: 18, color: AppColors.inkSoft),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                      'Activez la localisation pour vous voir sur la carte',
                      style: AppText.caption.copyWith(color: AppColors.ink)),
                ),
              ]),
            ),
          ),
        // Carrousel des prestataires, du plus proche au plus loin ; la carte
        // suit la fiche affichée.
        if (nearby.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpace.md,
            height: _carouselHeight,
            child: PageView.builder(
              controller: _carousel,
              itemCount: nearby.length,
              onPageChanged: (i) => _mapController?.animateCamera(
                CameraUpdate.newLatLng(
                    LatLng(nearby[i].latitude!, nearby[i].longitude!)),
              ),
              itemBuilder: (context, i) {
                final p = nearby[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _MapProviderCard(
                    data: p,
                    rating: _ratingFor(p.id),
                    distanceLabel: _formatDistance(p),
                    onTap: () => _showDetails(p),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }

  // ================= ONGLET MES DEMANDES =================

  Widget _buildOrders() {
    return Builder(
      builder: (context) {
        final orders = _orders;
        final active = orders
                ?.where((o) => o.statut != 'archive' && o.statut != 'annule')
                .length ??
            0;
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Letterhead(
              title: 'Mes demandes',
              subtitle: orders == null
                  ? 'Chargement de vos fiches…'
                  : active > 0
                      ? '$active demande${active > 1 ? 's' : ''} en cours. Le tampon indique où en est chacune.'
                      : 'Chaque demande reçoit un numéro de fiche et un tampon de statut.',
            ),
          ),
          if (_ordersError && orders == null)
            SliverToBoxAdapter(
                child: ErrorStateView(
                    message: 'Impossible de charger vos demandes.',
                    onRetry: _listenOrders))
          else if (orders == null)
            const SliverToBoxAdapter(child: LoadingView())
          else if (orders.isEmpty)
            SliverToBoxAdapter(
              child: EmptyStateView(
                icon: Icons.receipt_long_rounded,
                title: 'Aucune demande pour le moment',
                subtitle:
                    'Sollicitez un expert : sa fiche apparaîtra ici avec son numéro.',
                action: FilledButton(
                  onPressed: () => setState(() => _selectedIndex = 0),
                  child: const Text('Trouver un expert'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xl),
              sliver: SliverList.separated(
                itemCount: orders.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpace.md),
                itemBuilder: (context, i) {
                  final o = orders[i];
                  return _OrderFiche(
                    order: o,
                    timerLabel: _getTimerOrEnd(o),
                    canCancel: _canCancel(o.dateSollicitation),
                    onCall: () => _call(o.expert?.telephone),
                    onArchive: () => _archiveOrder(o.id),
                    onCancelPressed: () => _showCancelAlert(o),
                    onTimeWarning: () => _showTimeWarning(o.dateSollicitation),
                    onRate: () => _ratingModal(o),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }

  // ================= DIALOGUES =================

  void _ratingModal(Sollicitation o) {
    int r = 0;
    final ctrl = TextEditingController();
    final userId = ref.read(authRepositoryProvider).currentUserId;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          title: const Text("Noter l'expert"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${o.expert?.prenom ?? ''} ${o.expert?.nom ?? 'Expert'} · ${ficheNumber(o.id)}'
                    .trim(),
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: '${i + 1} étoile${i > 0 ? 's' : ''}',
                    iconSize: 34,
                    icon: Icon(
                      i < r ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i < r ? AppColors.gold : AppColors.inkMuted,
                    ),
                    onPressed: () => setD(() => r = i + 1),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: ctrl,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Votre avis (facultatif)',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () async {
                if (r == 0) {
                  _showErrorSnackBar('Choisissez une note de 1 à 5 étoiles.');
                  return;
                }
                if (userId == null) return;
                try {
                  await ref.read(avisRepositoryProvider).create(
                        sollicitationId: o.id,
                        prestataireId: o.prestataireId,
                        citoyenId: userId,
                        note: r,
                        commentaire: ctrl.text,
                      );
                  // La note vient de changer : recalcul au prochain affichage.
                  _ratings.remove(o.prestataireId);
                  await _archiveOrder(o.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } on AppException catch (e) {
                  _showErrorSnackBar(e.message);
                }
              },
              child: const Text('Valider et clore'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeWarning(DateTime? d) {
    if (d == null) return;
    final restant = 120 - DateTime.now().difference(d).inMinutes;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.schedule_rounded,
            color: AppColors.progress, size: 32),
        title: const Text('Annulation possible plus tard'),
        content: Text(
          "L'expert a peut-être déjà pris la route. Vous pourrez annuler librement dans $restant min.",
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("D'accord"),
          ),
        ],
      ),
    );
  }

  void _showCancelAlert(Sollicitation order) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined,
            color: AppColors.danger, size: 32),
        title: Text('Annuler la demande ${ficheNumber(order.id)} ?'),
        content: const Text(
            "L'expert sera prévenu. Cette action ne peut pas être annulée."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Garder'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref
                    .read(sollicitationRepositoryProvider)
                    .cancel(order.id);
              } on AppException catch (e) {
                _showErrorSnackBar(e.message);
              }
            },
            child: const Text('Annuler la demande'),
          ),
        ],
      ),
    );
  }

  void _showDetails(Particulier p) {
    final rating = _ratingFor(p.id);
    final distance = _formatDistance(p);
    final trade = TradeStyle.of(p.servicePropose);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IdPhoto(url: p.photoProUrl, size: 88, tint: trade.tint),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.prenom} ${p.nom}'.trim(),
                          style: AppText.heading.copyWith(fontSize: 22)),
                      const SizedBox(height: AppSpace.sm),
                      TradeTag(p.servicePropose),
                      const SizedBox(height: AppSpace.sm),
                      RatingInline(rating),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xl),
              const Divider(),
              if (p.identiteVerifiee)
                _detailLine(Icons.verified_rounded,
                    'Identité vérifiée par WANDA (pièce d\'identité contrôlée)',
                    iconColor: AppColors.done),
              _detailLine(Icons.circle, 'Disponible maintenant',
                  iconColor: AppColors.done, iconSize: 10),
              if (distance != null)
                _detailLine(Icons.near_me_rounded, 'À $distance de vous'),
              _detailLine(Icons.receipt_long_rounded,
                  'Votre demande recevra un numéro de fiche à suivre dans « Mes demandes ».'),
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: () => _solicit(p),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56)),
                icon: const Icon(Icons.send_rounded, size: 20),
                label: Text(
                    'Solliciter ${p.prenom.isNotEmpty ? p.prenom : 'cet expert'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(IconData icon, String text,
      {Color iconColor = AppColors.inkSoft, double iconSize = 18}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Center(child: Icon(icon, size: iconSize, color: iconColor)),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(child: Text(text, style: AppText.body)),
      ]),
    );
  }

  // ================= ONGLET PROFIL =================

  Widget _buildProfile() {
    final verified = ref.read(authRepositoryProvider).hasVerifiedPhone;
    final incomplete =
        _nomController.text.isEmpty || _prenomController.text.isEmpty;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Letterhead(
          title: incomplete ? 'Complétez votre fiche' : 'Ma fiche citoyen',
          subtitle: incomplete
              ? 'Ajoutez votre nom pour pouvoir solliciter un expert.'
              : 'Ces informations sont transmises aux experts que vous sollicitez.',
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
                  label: 'Changer ma photo',
                  child: InkWell(
                    onTap: _pickImg,
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(clipBehavior: Clip.none, children: [
                      IdPhoto(url: _photoUrl, size: 96),
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
                      Text(
                        incomplete
                            ? 'Citoyen'
                            : '${_prenomController.text} ${_nomController.text}',
                        style: AppText.sectionTitle,
                      ),
                      const SizedBox(height: 4),
                      Text(_phoneController.text, style: AppText.number),
                      if (verified) ...[
                        const SizedBox(height: 6),
                        const StatusStamp(
                            FicheStatus('WHATSAPP VÉRIFIÉ', StampTone.done),
                            angle: -2),
                      ],
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xl),
              _field('Nom', _nomController, Icons.badge_outlined),
              _field('Prénom', _prenomController, Icons.person_outline_rounded),
              // Le numéro WhatsApp vérifié sert d'identifiant : non modifiable.
              _field(
                verified ? 'Numéro WhatsApp' : 'Téléphone mobile',
                _phoneController,
                Icons.phone_outlined,
                enabled: !verified,
                helper: verified ? 'Vérifié, sert à vous connecter.' : null,
              ),
              _field('Email (facultatif)', _emailController,
                  Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: AppSpace.sm),
              FilledButton(
                onPressed: _updateProfile,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54)),
                child: const Text('Enregistrer'),
              ),
              const SizedBox(height: AppSpace.md),
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

  Widget _field(String label, TextEditingController c, IconData icon,
      {bool enabled = true,
      String? helper,
      TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: TextField(
        controller: c,
        enabled: enabled,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon:
              enabled ? null : const Icon(Icons.lock_outline_rounded, size: 18),
        ),
      ),
    );
  }

  Future<void> _updateProfile() async {
    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (userId == null) return;
    try {
      await ref.read(profileRepositoryProvider).updateCitoyen(Citoyen(
            citoyenId: userId,
            nom: _nomController.text.trim(),
            prenom: _prenomController.text.trim(),
            email: _emailController.text.trim(),
            telephone: _phoneController.text.trim(),
          ));
      if (!mounted) return;
      showAppSnackBar(context, 'Profil enregistré.', isError: false);
    } on AppException catch (e) {
      _showErrorSnackBar(e.message);
    }
  }

  Future<void> _pickImg() async {
    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (userId == null) return;
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 60);
      if (img == null) return;
      final url = await ref.read(storageRepositoryProvider).uploadImage(
            bucket: 'profils',
            path: 'citoyen_$userId.jpg',
            file: File(img.path),
            upsert: true,
          );
      await ref.read(profileRepositoryProvider).updateCitoyenPhoto(userId, url);
      if (mounted) setState(() => _photoUrl = url);
    } on AppException catch (e) {
      _showErrorSnackBar(e.message);
    }
  }

  // ================= ONGLET ASSISTANT =================

  Widget _buildAssistant() {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        Letterhead(
          title: 'Assistant WANDA',
          subtitle:
              "Bientôt : décrivez un problème, l'assistant vous orientera vers le bon expert ou le bon service.",
        ),
        EmptyStateView(
          icon: Icons.auto_awesome_rounded,
          title: "L'assistant arrive",
          subtitle:
              'En attendant, utilisez les onglets Experts et Mes demandes.',
        ),
      ],
    );
  }
}

// =============================================================================
// COMPOSANTS
// =============================================================================

class _TradeTab extends StatelessWidget {
  final TradeStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _TradeTab(
      {required this.style, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? style.tint : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: BorderSide(
            color: selected ? style.ink : AppColors.rule,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(style.icon,
                  size: 20, color: selected ? style.ink : AppColors.inkSoft),
              const SizedBox(width: 8),
              Text(
                style.label,
                style: AppText.label.copyWith(
                  color: selected ? style.ink : AppColors.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Fiche expert dans la liste : photo d'identité, nom, métier, note, et la
/// distance en gros chiffres (l'information qui fait choisir).
class _ExpertRow extends StatelessWidget {
  final Particulier data;
  final RatingSummary rating;
  final String? distanceLabel;
  final VoidCallback onTap;

  const _ExpertRow({
    required this.data,
    required this.rating,
    required this.distanceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trade = TradeStyle.of(data.servicePropose);
    return Semantics(
      button: true,
      label: 'Voir la fiche de ${data.prenom} ${data.nom}',
      child: FicheCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(children: [
          IdPhoto(url: data.photoProUrl, size: 60, tint: trade.tint),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      '${data.prenom} ${data.nom}'.trim(),
                      style: AppText.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (data.identiteVerifiee) ...[
                    const SizedBox(width: 4),
                    const VerifiedMark(),
                  ],
                ]),
                const SizedBox(height: 6),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TradeTag(data.servicePropose),
                    RatingInline(rating)
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          if (distanceLabel != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  distanceLabel!,
                  style: AppText.number
                      .copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                Text('de vous', style: AppText.caption),
              ],
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
        ]),
      ),
    );
  }
}

class _TopRatedFiche extends StatelessWidget {
  final Particulier data;
  final RatingSummary rating;
  final VoidCallback onTap;

  const _TopRatedFiche(
      {required this.data, required this.rating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final trade = TradeStyle.of(data.servicePropose);
    return SizedBox(
      width: 156,
      child: FicheCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IdPhoto(url: data.photoProUrl, size: 64, tint: trade.tint),
            const Spacer(),
            Row(children: [
              Flexible(
                child: Text(
                  '${data.prenom} ${data.nom}'.trim(),
                  style: AppText.cardTitle.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.identiteVerifiee) ...[
                const SizedBox(width: 4),
                const VerifiedMark(),
              ],
            ]),
            const SizedBox(height: 4),
            Text(trade.label,
                style: AppText.caption
                    .copyWith(color: trade.ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            RatingInline(rating),
          ],
        ),
      ),
    );
  }
}

/// Fiche de demande : numéro, date, tampon de statut, expert, actions.
class _OrderFiche extends StatelessWidget {
  final Sollicitation order;
  final String timerLabel;
  final bool canCancel;
  final VoidCallback onCall;
  final VoidCallback onArchive;
  final VoidCallback onCancelPressed;
  final VoidCallback onTimeWarning;
  final VoidCallback onRate;

  const _OrderFiche({
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
    final expert = order.expert;
    final status = order.statut;
    final isAccepted = status == 'accepte';
    final isDone = status == 'termine';
    final isFinal = status == 'archive' || status == 'annule';
    final date = order.dateSollicitation;
    final trade = TradeStyle.of(expert?.servicePropose);

    return FicheCard(
      color: isFinal ? AppColors.paper : null,
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 0),
          child: Row(children: [
            FicheNumber(order.id, color: AppColors.ink),
            if (date != null) ...[
              const SizedBox(width: AppSpace.sm),
              Text('· ${DateFormat('dd/MM HH:mm').format(date.toLocal())}',
                  style: AppText.caption),
            ],
            const Spacer(),
            StatusStamp(FicheStatus.sollicitation(status)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            IdPhoto(url: expert?.photoProUrl, size: 48, tint: trade.tint),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${expert?.prenom ?? ''} ${expert?.nom ?? 'Expert'}'.trim(),
                    style: AppText.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timerLabel,
                    style: AppText.caption.copyWith(
                      color: isAccepted ? AppColors.progress : null,
                      fontWeight: isAccepted ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (isAccepted || isDone)
              IconButton.filledTonal(
                tooltip: "Appeler l'expert",
                onPressed: onCall,
                icon: const Icon(Icons.call_rounded),
              )
            else if (isFinal)
              TextButton.icon(
                onPressed: onArchive,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Classer'),
              ),
          ]),
        ),
        if (!isFinal) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: canCancel ? onCancelPressed : onTimeWarning,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor:
                        canCancel ? AppColors.danger : AppColors.inkMuted,
                  ),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: FilledButton(
                  onPressed: isDone ? onRate : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Noter et clore'),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Fiche compacte d'un prestataire dans le carrousel de la carte.
class _MapProviderCard extends StatelessWidget {
  final Particulier data;
  final RatingSummary rating;
  final String? distanceLabel;
  final VoidCallback onTap;

  const _MapProviderCard({
    required this.data,
    required this.rating,
    required this.distanceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trade = TradeStyle.of(data.servicePropose);
    return Semantics(
      button: true,
      label: 'Voir la fiche de ${data.prenom} ${data.nom}',
      child: FicheCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(children: [
          IdPhoto(url: data.photoProUrl, size: 64, tint: trade.tint),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text('${data.prenom} ${data.nom}'.trim(),
                        style: AppText.cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (data.identiteVerifiee) ...[
                    const SizedBox(width: 4),
                    const VerifiedMark(),
                  ],
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  TradeTag(data.servicePropose),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(child: RatingInline(rating)),
                ]),
              ],
            ),
          ),
          if (distanceLabel != null) ...[
            const SizedBox(width: AppSpace.sm),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(distanceLabel!,
                    style: AppText.number
                        .copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('de vous', style: AppText.caption),
              ],
            ),
          ],
        ]),
      ),
    );
  }
}
