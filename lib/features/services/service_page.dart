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
import '../../data/models/ajustement.dart';
import '../../data/models/avis_prestataire.dart';
import '../../data/models/categorie_service.dart';
import '../../data/models/citoyen.dart';
import '../../data/models/demande_menage.dart';
import '../../data/models/particulier.dart';
import '../../data/models/sollicitation.dart';
import '../../data/pricing/tarification.dart';
import '../demande/demande_page.dart';
import 'prestataire_marker_factory.dart';

class ServicePage extends ConsumerStatefulWidget {
  /// Service présélectionné (code, ex. `menage`) quand on arrive depuis une
  /// tuile de service.
  final String? initialCategory;

  const ServicePage({super.key, this.initialCategory});
  @override
  ConsumerState<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends ConsumerState<ServicePage> {
  int _selectedIndex = 0;

  String selectedCategory = ServiceStyle.tousCode;
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

  final List<String> categories = ServiceStyle.codes;
  Timer? _clock;

  // Flux temps réel : un seul abonnement par écran (et non un par
  // reconstruction), les dernières données sont gardées ici.
  StreamSubscription<List<Particulier>>? _providersSub;
  List<Particulier> _allProviders = const [];
  bool _providersLoaded = false;
  bool _providersError = false;

  StreamSubscription<List<Sollicitation>>? _ordersSub;
  final _suiviSubs = <StreamSubscription<void>>[];
  bool _historiqueOuvert = false;
  List<Sollicitation>? _orders;
  bool _ordersError = false;

  /// Ajustement en attente de réponse, par demande.
  Map<String, Ajustement> _ajustements = const {};

  /// Passages pointés, par abonnement confirmé.
  Map<String, int> _passages = const {};

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
    _listenSuivi();
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
    for (final s in _suiviSubs) {
      s.cancel();
    }
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
    // Sans position connue : les mieux notés d'abord.
    withoutDistance.sort((a, b) {
      final ra = _ratingFor(a.id), rb = _ratingFor(b.id);
      final parNote = rb.average.compareTo(ra.average);
      return parNote != 0 ? parNote : rb.count.compareTo(ra.count);
    });
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
          // Un compte sans service (ancien métier, profil inachevé) n'est
          // pas réservable : on ne le montre pas comme disponible.
          _allProviders =
              providers.where((p) => p.services.isNotEmpty).toList();
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

  /// Prestataires du service choisi, du plus proche au plus éloigné.
  List<Particulier> get _visibleProviders =>
      _sortByDistance(selectedCategory == ServiceStyle.tousCode
          ? _allProviders
          : _allProviders
              .where((p) => p.services.contains(selectedCategory))
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
            '${p.id}:${p.photoProUrl}:${p.isAvailable}:${p.services.join(',')}')
        .join('|');
    if (signature == _markersSignature) return;
    _markersSignature = signature;

    final markers = <Marker>{};
    for (final p in withLocation) {
      final icon = await PrestataireMarkerFactory.build(
        id: p.id,
        photoUrl: p.photoProUrl,
        service: p.services.isEmpty ? null : p.services.first,
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
          _signalerChangements(orders);
          setState(() {
            _orders = orders;
            _ordersError = false;
          });
          _chargerSuivi(orders);
        }
      },
      onError: (Object _) {
        if (mounted) setState(() => _ordersError = true);
      },
    );
  }

  /// Statut connu de chaque demande, pour annoncer ce que fait le prestataire.
  Map<String, String>? _statutsVus;

  /// Le prestataire confirme, refuse ou termine : on le dit au client, avec
  /// un bouton qui mène directement à la suite.
  void _signalerChangements(List<Sollicitation> orders) {
    final avant = _statutsVus;
    _statutsVus = {for (final o in orders) o.id: o.statut};
    if (avant == null) return;
    for (final o in orders) {
      final ancien = avant[o.id];
      if (ancien == null || ancien == o.statut) continue;
      final prenom = o.expert?.prenom?.trim() ?? '';
      final qui = prenom.isNotEmpty ? prenom : 'Le prestataire';
      final (String message, VoidCallback action, String label) =
          switch (o.statut) {
        'accepte' => (
            '$qui a confirmé votre demande ${ficheNumber(o.id)}.',
            () => setState(() => _selectedIndex = 1),
            'Voir',
          ),
        'refuse' => (
            "$qui n'est pas disponible pour ${ficheNumber(o.id)}.",
            () => _reprendre(o),
            'Autre prestataire',
          ),
        'termine' => (
            'Mission ${ficheNumber(o.id)} terminée : notez $qui.',
            () => _ratingModal(o),
            'Noter',
          ),
        _ => ('', () {}, ''),
      };
      if (message.isEmpty) continue;
      showAppSnackBar(context, message,
          isError: false, actionLabel: label, action: action);
      return;
    }
  }

  /// Un ajustement demandé ou un passage pointé ne modifie pas la demande :
  /// on écoute ces tables à part pour que le client le voie aussitôt.
  void _listenSuivi() {
    final repo = ref.read(demandeRepositoryProvider);
    for (final table in const ['ajustements', 'passages']) {
      _suiviSubs.add(repo.changementsSuivi(table).listen(
            (_) => _chargerSuivi(_orders ?? const []),
            // Sans temps réel, le suivi se met à jour au rafraîchissement.
            onError: (Object _) {},
          ));
    }
  }

  /// Ajustements en attente et passages d'abonnement des demandes en cours.
  Future<void> _chargerSuivi(List<Sollicitation> orders) async {
    final repo = ref.read(demandeRepositoryProvider);
    final confirmees = orders
        .where((o) => o.estDemandeMenage && o.statut == 'accepte')
        .toList();
    try {
      final ajustements =
          await repo.ajustements([for (final o in confirmees) o.id]);
      final passages = <String, int>{};
      for (final o
          in confirmees.where((o) => o.formule == Formule.abonnement)) {
        passages[o.id] = (await repo.passages(o.id)).length;
      }
      if (!mounted) return;
      setState(() {
        _ajustements = {
          for (final a in ajustements.where((a) => a.enAttente))
            a.sollicitationId: a,
        };
        _passages = passages;
      });
    } on AppException catch (_) {
      // Le suivi détaillé reste à jour au prochain rafraîchissement.
    }
  }

  Future<void> _repondreAjustement(Ajustement a, bool accepte) async {
    try {
      await ref
          .read(demandeRepositoryProvider)
          .repondreAjustement(a.id, accepte: accepte);
      if (!mounted) return;
      showAppSnackBar(
          context,
          accepte
              ? 'Ajustement accepté : +${fcfa(a.prixSupp)}.'
              : 'Ajustement refusé : le prix initial reste dû.',
          isError: false);
      setState(
          () => _ajustements = {..._ajustements}..remove(a.sollicitationId));
      // Le prix total a changé côté serveur : on relit la fiche.
      if (accepte) _listenOrders();
    } on AppException catch (e) {
      _showErrorSnackBar(e.message);
    }
  }

  /// Photo jointe à un ajustement (privée : URL signée de courte durée).
  Future<void> _voirPhoto(String chemin) async {
    try {
      final url = await ref.read(demandeRepositoryProvider).urlPhoto(chemin);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpace.md),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            InteractiveViewer(
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(AppSpace.xl),
                        child: Text('Photo indisponible.'),
                      )),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ]),
        ),
      );
    } on AppException catch (e) {
      _showErrorSnackBar(e.message);
    }
  }

  /// Ouvre la réservation ; revient sur « Mes demandes » une fois envoyée.
  Future<void> _reserver(DemandeArgs args) async {
    final envoyee =
        await context.push<bool>(AppRoutes.citoyenDemande, extra: args);
    if (envoyee == true && mounted) {
      setState(() => _selectedIndex = 1);
      showAppSnackBar(context,
          'Demande envoyée : vous êtes prévenu dès que le prestataire répond.',
          isError: false);
      // Le temps réel n'est pas garanti sur toutes les bases : on recharge
      // pour que la nouvelle fiche apparaisse tout de suite.
      _listenOrders();
    }
  }

  /// Demande refusée : mêmes réponses et photos, autre prestataire.
  void _reprendre(Sollicitation o) {
    final d = o.demande;
    if (d == null) return;
    _reserver(DemandeArgs(d.service,
        reprise: d,
        photosEnvoyees: o.photos,
        analyseId: null,
        exclu: o.prestataireId,
        date: o.dateSouhaitee,
        creneau: o.creneau));
  }

  // ================= UTILS =================

  String _getTimerOrEnd(Sollicitation order) {
    try {
      if ((order.statut == 'termine' || order.statut == 'archive') &&
          order.dateFin != null) {
        return "Terminée à ${DateFormat('HH:mm').format(order.dateFin!.toLocal())}";
      }
      if (order.statut == 'accepte') return 'Prestataire confirmé';
      if (order.statut == 'refuse') return 'Prestataire indisponible';
      if (order.statut == 'annule') return 'Demande annulée';
      // La date d'envoi figure déjà en tête de fiche : on dit ce qu'on attend.
      return 'Attend la réponse du prestataire';
    } catch (e) {
      return "Statut mis à jour";
    }
  }

  /// Tant que le prestataire n'a pas répondu, le client annule librement.
  /// Une fois la demande confirmée, il s'est organisé : 2 h de délai.
  bool _canCancel(Sollicitation o) {
    if (o.statut == 'en_attente') return true;
    final date = o.dateSollicitation;
    if (date == null) return false;
    return DateTime.now().difference(date).inMinutes >= 120;
  }

  Future<void> _call(String? t) async {
    if (t == null || t.isEmpty) {
      _showErrorSnackBar('Numéro du prestataire non disponible');
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

  Future<void> _archiveOrder(String id) async {
    try {
      await ref.read(sollicitationRepositoryProvider).archive(id);
      _listenOrders();
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
      body: () {
        final contenu = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          child: KeyedSubtree(key: ValueKey(_selectedIndex), child: body),
        );
        // La carte s'affiche en plein écran, sous la barre d'état.
        return _selectedIndex == 0 && _showMap
            ? contenu
            : BandeauBarreEtat(child: contenu);
      }(),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.rule)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Accueil',
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

  /// Accueil : les prestataires en ligne, tout de suite. Chaque fiche montre
  /// ses services ; un toucher sur un service ouvre la réservation avec ce
  /// prestataire déjà choisi.
  Widget _buildListView(List<Particulier> all, bool isLoading, bool hasError) {
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
          SliverToBoxAdapter(child: _buildSuiviEntry()),
          if (_locationOff) SliverToBoxAdapter(child: _buildLocationBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.lg, AppSpace.gutter, 0),
              child: Row(children: [
                Expanded(
                  child: Text('Prestataires en ligne',
                      style: AppText.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: AppSpace.sm),
                _viewModeToggle(),
              ]),
            ),
          ),
          SliverToBoxAdapter(child: _buildTradeTabs()),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
          if (hasError)
            SliverToBoxAdapter(
              child: ErrorStateView(
                message: 'Impossible de charger les prestataires.',
                onRetry: _listenProviders,
              ),
            )
          else if (isLoading)
            const SliverToBoxAdapter(child: LoadingView())
          else if (all.isEmpty)
            SliverToBoxAdapter(
              child: EmptyStateView(
                icon: Icons.person_search_rounded,
                title: selectedCategory == ServiceStyle.tousCode
                    ? 'Aucun prestataire en ligne'
                    : 'Personne en ligne pour ce service',
                subtitle:
                    'Les prestataires se connectent tout au long de la journée.',
                action: selectedCategory == ServiceStyle.tousCode
                    ? null
                    : OutlinedButton(
                        onPressed: () => setState(
                            () => selectedCategory = ServiceStyle.tousCode),
                        child: const Text('Voir tous les services'),
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
                    serviceEnAvant: selectedCategory,
                    onTap: () => _showDetails(p),
                    onReserver: (c) =>
                        _reserver(DemandeArgs(c, prestataire: p)),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(child: _buildReportEntry()),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        ],
      ),
    );
  }

  Widget _buildHeader(int onlineCount, bool isLoading) {
    // Le nom saisi au récapitulatif suffit quand le prénom manque.
    final prenom = _prenomController.text.trim().isNotEmpty
        ? _prenomController.text.trim()
        : _nomController.text.trim();
    return Letterhead(
      overline: prenom.isNotEmpty ? 'Bonjour, $prenom' : 'Bonjour',
      title: 'Qui peut vous aider ?',
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
                ? 'Recherche des prestataires en ligne…'
                : onlineCount > 0
                    ? '$onlineCount prestataire${onlineCount > 1 ? 's' : ''} en ligne près de vous'
                    : 'Aucun prestataire en ligne pour le moment',
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
                'Activez la localisation pour voir les prestataires les plus proches',
                style: AppText.caption.copyWith(color: AppColors.ink)),
          ),
          Text('Activer',
              style: AppText.label.copyWith(color: AppColors.letterhead)),
        ]),
      ),
    );
  }

  /// Demande la plus urgente à suivre, en tête de l'accueil : le client voit
  /// où elle en est sans chercher l'onglet « Mes demandes ».
  Widget _buildSuiviEntry() {
    final orders = _orders ?? const <Sollicitation>[];
    Sollicitation? premier(bool Function(Sollicitation) f) =>
        orders.where(f).firstOrNull;
    final aj = premier((o) => _ajustements.containsKey(o.id));
    final aNoter = premier((o) => o.statut == 'termine');
    final refusee = premier((o) => o.statut == 'refuse' && o.estDemandeMenage);
    final confirmee = premier((o) => o.statut == 'accepte');
    final enAttente = premier((o) => o.statut == 'en_attente');
    final (Sollicitation? o, String detail, FicheStatus status) = aj != null
        ? (
            aj,
            'Ajustement à valider : +${fcfa(_ajustements[aj.id]!.prixSupp)}',
            FicheStatus.ajustement
          )
        : aNoter != null
            ? (
                aNoter,
                'Terminé : notez le prestataire',
                FicheStatus.sollicitation('termine')
              )
            : refusee != null
                ? (
                    refusee,
                    'Indisponible : choisissez un autre prestataire',
                    FicheStatus.sollicitation('refuse')
                  )
                : confirmee != null
                    ? (
                        confirmee,
                        confirmee.quand.isEmpty
                            ? 'Prestataire confirmé'
                            : 'Confirmé pour ${confirmee.quand}',
                        FicheStatus.sollicitation('accepte')
                      )
                    : enAttente != null
                        ? (
                            enAttente,
                            'Attend la réponse du prestataire',
                            FicheStatus.sollicitation('en_attente')
                          )
                        : (null, '', FicheStatus.sollicitation(''));
    if (o == null) return const SizedBox.shrink();
    final style = ServiceStyle.of(o.service?.code);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.lg, AppSpace.gutter, 0),
      child: Semantics(
        button: true,
        label: 'Suivre ma demande : $detail',
        child: FicheCard(
          // La carte mène droit à ce qu'elle annonce : noter, choisir un
          // autre prestataire, ou sinon la fiche dans « Mes demandes ».
          onTap: o == aNoter && aj == null
              ? () => _ratingModal(o)
              : o == refusee && aj == null
                  ? () => _reprendre(o)
                  : () => setState(() => _selectedIndex = 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(style.icon, color: style.ink, size: 22),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${style.label} · ${ficheNumber(o.id)}',
                      style: AppText.cardTitle.copyWith(fontSize: 15)),
                  Text(detail, style: AppText.caption),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            StatusStamp(status, angle: -3),
          ]),
        ),
      ),
    );
  }

  /// Accès direct au signalement d'incident (service public gratuit, à ne
  /// pas confondre avec le ramassage de poubelles à domicile). En bas de
  /// l'accueil : l'écran sert d'abord à trouver un prestataire.
  Widget _buildReportEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.md, AppSpace.gutter, 0),
      child: Semantics(
        button: true,
        child: FicheCard(
          onTap: () => context.push(AppRoutes.citoyenSignal),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.greenTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.campaign_rounded,
                  color: AppColors.letterheadDeep, size: 22),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Signaler un incident',
                      style: AppText.cardTitle.copyWith(fontSize: 15)),
                  Text('Gratuit : dépôt sauvage, fuite, panne dans le quartier',
                      style: AppText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.letterheadDeep),
          ]),
        ),
      ),
    );
  }

  /// Onglets de service : une copie carbone colorée par service.
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
            style: ServiceStyle.of(cat),
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
                    Text('Prestataires autour de vous',
                        style: AppText.cardTitle),
                    Text(
                      '${all.length} en ligne · ${ServiceStyle.of(selectedCategory).label}',
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
        int compte(bool Function(String) f) =>
            orders?.where((o) => f(o.statut)).length ?? 0;
        final active =
            compte((s) => !const ['archive', 'annule', 'termine'].contains(s));
        final aNoter = compte((s) => s == 'termine');
        final aussi = aNoter > 0 ? ', $aNoter à noter' : '';
        // Les fiches classées ou annulées passent dans un historique replié.
        bool ancienne(Sollicitation o) =>
            o.statut == 'archive' || o.statut == 'annule';
        final actives = [...?orders?.where((o) => !ancienne(o))];
        final anciennes = [...?orders?.where(ancienne)];
        return RefreshIndicator(
          onRefresh: () async => _listenOrders(),
          child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Letterhead(
                    title: 'Mes demandes',
                    subtitle: orders == null
                        ? 'Chargement de vos fiches…'
                        : active > 0
                            ? '$active demande${active > 1 ? 's' : ''} en cours$aussi. Le tampon indique où en est chacune.'
                            : aNoter > 0
                                ? '$aNoter mission${aNoter > 1 ? 's' : ''} terminée${aNoter > 1 ? 's' : ''} : notez le prestataire pour clore.'
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
                          'Réservez un service : votre demande apparaîtra ici avec son numéro.',
                      action: FilledButton(
                        onPressed: () => setState(() => _selectedIndex = 0),
                        child: const Text('Réserver un service'),
                      ),
                    ),
                  )
                else ...[
                  if (actives.isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyStateView(
                        icon: Icons.receipt_long_rounded,
                        title: 'Aucune demande en cours',
                        subtitle:
                            "Vos fiches classées restent dans l'historique.",
                        action: FilledButton(
                          onPressed: () => setState(() => _selectedIndex = 0),
                          child: const Text('Réserver un service'),
                        ),
                      ),
                    )
                  else
                    _listeFiches(actives),
                  if (anciennes.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.gutter),
                        child: TextButton.icon(
                          onPressed: () => setState(
                              () => _historiqueOuvert = !_historiqueOuvert),
                          icon: Icon(_historiqueOuvert
                              ? Icons.expand_less_rounded
                              : Icons.history_rounded),
                          label: Text(_historiqueOuvert
                              ? "Masquer l'historique"
                              : 'Historique · ${anciennes.length} fiche${anciennes.length > 1 ? 's' : ''}'),
                        ),
                      ),
                    ),
                    if (_historiqueOuvert) _listeFiches(anciennes),
                  ],
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpace.xl)),
                ],
              ]),
        );
      },
    );
  }

  Widget _listeFiches(List<Sollicitation> fiches) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.md),
        sliver: SliverList.separated(
          itemCount: fiches.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
          itemBuilder: (context, i) {
            final o = fiches[i];
            return _OrderFiche(
              order: o,
              ajustement: _ajustements[o.id],
              passages: _passages[o.id],
              onRepondre: _repondreAjustement,
              onVoirPhoto: _voirPhoto,
              onReprendre: () => _reprendre(o),
              timerLabel: _getTimerOrEnd(o),
              canCancel: _canCancel(o),
              onCall: () => _call(o.expert?.telephone),
              onArchive: () => _archiveOrder(o.id),
              onCancelPressed: () => _showCancelAlert(o),
              onTimeWarning: () => _showTimeWarning(o.dateSollicitation),
              onRate: () => _ratingModal(o),
            );
          },
        ),
      );

  // ================= DIALOGUES =================

  static const _libellesNote = [
    'Très décevant',
    'Décevant',
    'Correct',
    'Bien',
    'Excellent',
  ];

  void _ratingModal(Sollicitation o) {
    int r = 0;
    var envoi = false;
    final ctrl = TextEditingController();
    final userId = ref.read(authRepositoryProvider).currentUserId;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          title: const Text('Noter le prestataire'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${o.expert?.prenom ?? ''} ${o.expert?.nom ?? 'Prestataire'} · ${ficheNumber(o.id)}'
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
              Center(
                child: Text(
                  r == 0 ? 'Touchez une étoile' : _libellesNote[r - 1],
                  style: AppText.caption,
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
              // Actif dès qu'une étoile est choisie ; un seul envoi à la fois.
              onPressed: r == 0 || envoi || userId == null
                  ? null
                  : () async {
                      setD(() => envoi = true);
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
                        if (mounted) {
                          showAppSnackBar(context,
                              'Merci ! Votre avis aide les autres clients.',
                              isError: false);
                        }
                      } on AppException catch (e) {
                        _showErrorSnackBar(e.message);
                        if (dialogContext.mounted) setD(() => envoi = false);
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
          "Le prestataire s'est peut-être déjà organisé. Vous pourrez annuler librement dans $restant min.",
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
            'Le prestataire sera prévenu. Cette action ne peut pas être annulée.'),
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
                _listenOrders();
                if (mounted) {
                  showAppSnackBar(context, 'Demande annulée.', isError: false);
                }
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
    final trade = ServiceStyle.ofServices(p.services);
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
                      ServiceTags(p.services),
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
              _detailLine(Icons.sell_outlined,
                  'Prix fixé par WANDA selon votre demande, affiché avant de réserver.'),
              const SizedBox(height: AppSpace.lg),
              if (p.services.length > 1) ...[
                Text('Quel service ?', style: AppText.label),
                const SizedBox(height: AppSpace.sm),
              ],
              for (final code in p.services)
                if (CategorieService.fromCode(code) case final c?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _reserver(DemandeArgs(c, prestataire: p));
                      },
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54)),
                      icon: Icon(ServiceStyle.ofCategorie(c).icon, size: 20),
                      label: Text(p.services.length > 1
                          ? 'Réserver : ${c.court}'
                          : 'Réserver ${p.prenom.isNotEmpty ? p.prenom : 'ce prestataire'}'),
                    ),
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
              ? 'Ajoutez votre nom pour pouvoir réserver un service.'
              : 'Ces informations sont transmises aux prestataires que vous réservez.',
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
      final img = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 60);
      if (img == null) return;
      final url = await ref
          .read(profileRepositoryProvider)
          .envoyerPhotoProfil(File(img.path));
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
              "Bientôt : décrivez votre besoin, l'assistant vous orientera vers le bon service.",
        ),
        EmptyStateView(
          icon: Icons.auto_awesome_rounded,
          title: "L'assistant arrive",
          subtitle:
              'En attendant, utilisez les onglets Services et Mes demandes.',
        ),
      ],
    );
  }
}

// =============================================================================
// COMPOSANTS
// =============================================================================

class _TradeTab extends StatelessWidget {
  final ServiceStyle style;
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

/// Fiche prestataire de l'accueil : qui il est (photo, nom, note, distance)
/// et ce qu'il propose. Chaque service est un bouton qui ouvre directement la
/// réservation ; le reste de la fiche ouvre son profil.
class _ExpertRow extends StatelessWidget {
  final Particulier data;
  final RatingSummary rating;
  final String? distanceLabel;
  final String serviceEnAvant;
  final VoidCallback onTap;
  final ValueChanged<CategorieService> onReserver;

  const _ExpertRow({
    required this.data,
    required this.rating,
    required this.distanceLabel,
    required this.serviceEnAvant,
    required this.onTap,
    required this.onReserver,
  });

  @override
  Widget build(BuildContext context) {
    final trade = ServiceStyle.ofServices(data.services);
    final services = [
      for (final code in data.services)
        if (CategorieService.fromCode(code) case final c?) c,
    ];
    return FicheCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Voir le profil de ${data.prenom} ${data.nom}'.trim(),
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
                    const SizedBox(height: 4),
                    RatingInline(rating),
                  ],
                ),
              ),
              if (distanceLabel != null) ...[
                const SizedBox(width: AppSpace.sm),
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
              ],
            ]),
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final c in services)
                  _BoutonService(
                    categorie: c,
                    enAvant: c.code == serviceEnAvant,
                    onTap: () => onReserver(c),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Service proposé par un prestataire, aux couleurs du service : un toucher
/// ouvre la réservation.
class _BoutonService extends StatelessWidget {
  final CategorieService categorie;
  final bool enAvant;
  final VoidCallback onTap;
  const _BoutonService(
      {required this.categorie, required this.enAvant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = ServiceStyle.ofCategorie(categorie);
    return Semantics(
      button: true,
      label: 'Réserver : ${categorie.libelle}',
      excludeSemantics: true,
      child: Material(
        color: style.tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: BorderSide(
            color: enAvant ? style.ink : style.ink.withValues(alpha: 0.25),
            width: enAvant ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(style.icon, size: 18, color: style.ink),
                const SizedBox(width: 6),
                Text(categorie.court,
                    style: AppText.label.copyWith(
                        color: style.ink, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 16, color: style.ink),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderFiche extends StatelessWidget {
  final Sollicitation order;
  final Ajustement? ajustement;
  final int? passages;
  final void Function(Ajustement, bool) onRepondre;
  final ValueChanged<String> onVoirPhoto;
  final VoidCallback onReprendre;
  final String timerLabel;
  final bool canCancel;
  final VoidCallback onCall;
  final VoidCallback onArchive;
  final VoidCallback onCancelPressed;
  final VoidCallback onTimeWarning;
  final VoidCallback onRate;

  const _OrderFiche({
    required this.order,
    required this.ajustement,
    required this.passages,
    required this.onRepondre,
    required this.onVoirPhoto,
    required this.onReprendre,
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
    final isRefused = status == 'refuse';
    final isFinal = status == 'archive' || status == 'annule' || isRefused;
    final date = order.dateSollicitation;
    final trade = order.service != null
        ? ServiceStyle.ofCategorie(order.service!)
        : ServiceStyle.ofServices(expert?.services ?? const []);
    final aj = ajustement;

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
            StatusStamp(aj != null
                ? FicheStatus.ajustement
                : FicheStatus.sollicitation(status)),
          ]),
        ),
        if (order.estDemandeMenage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ResumeDemande(order: order, passages: passages),
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
                    '${expert?.prenom ?? ''} ${expert?.nom ?? 'Prestataire'}'
                        .trim(),
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
                tooltip: 'Appeler le prestataire',
                onPressed: onCall,
                icon: const Icon(Icons.call_rounded),
              )
            else if (isFinal && status != 'archive')
              TextButton.icon(
                onPressed: onArchive,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Classer'),
              ),
          ]),
        ),
        if (aj != null)
          _BandeauAjustement(
              ajustement: aj, onRepondre: onRepondre, onVoirPhoto: onVoirPhoto),
        if (isRefused && order.estDemandeMenage) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((order.motifRefus ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Text('« ${order.motifRefus} »',
                        style: AppText.body.copyWith(color: AppColors.inkSoft)),
                  ),
                FilledButton.icon(
                  onPressed: onReprendre,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.person_search_rounded, size: 20),
                  label: const Text('Choisir un autre prestataire'),
                ),
              ],
            ),
          ),
        ],
        if (!isFinal) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            // Une mission terminée ne s'annule plus : il reste à la noter.
            child: SizedBox(
              width: double.infinity,
              child: isDone
                  ? FilledButton(
                      onPressed: onRate,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                      child: const Text('Noter et clore'),
                    )
                  : OutlinedButton(
                      onPressed: canCancel ? onCancelPressed : onTimeWarning,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor:
                            canCancel ? AppColors.danger : AppColors.inkMuted,
                      ),
                      child: const Text('Annuler la demande'),
                    ),
            ),
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
    final trade = ServiceStyle.ofServices(data.services);
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
                  ServiceTags(data.services),
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

/// Tuile de réservation d'un service (copie carbone).
/// Service, formule, date et prix d'une demande ménagère.
class _ResumeDemande extends StatelessWidget {
  final Sollicitation order;
  final int? passages;
  const _ResumeDemande({required this.order, this.passages});

  @override
  Widget build(BuildContext context) {
    final quand = order.quand.isEmpty ? null : order.quand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ServiceTag(order.service?.code),
              const SizedBox(height: 4),
              Text(
                  [
                    order.demande?.libelleFormule,
                    if (quand != null) 'Prévu $quand',
                    if (passages != null)
                      '$passages passage${passages! > 1 ? 's' : ''} effectué${passages! > 1 ? 's' : ''}',
                  ].whereType<String>().join(sepDetail),
                  style: AppText.caption),
            ],
          ),
        ),
        if (order.prixTotal != null)
          Text(fcfa(order.prixTotal!),
              style: AppText.number.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
      ],
    );
  }
}

/// Le prestataire demande un ajustement : le client accepte ou refuse.
class _BandeauAjustement extends StatelessWidget {
  final Ajustement ajustement;
  final void Function(Ajustement, bool) onRepondre;
  final ValueChanged<String> onVoirPhoto;
  const _BandeauAjustement(
      {required this.ajustement,
      required this.onRepondre,
      required this.onVoirPhoto});

  @override
  Widget build(BuildContext context) {
    final a = ajustement;
    final quoi = [
      if (a.minutesSupp > 0) '+${duree(a.minutesSupp)} de travail',
      if (a.produitsSupp > 0) '+${fcfa(a.produitsSupp)} de produits',
    ].join(', ');
    return Container(
      margin:
          const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.stampVioletTint,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('Ajustement demandé',
                  style:
                      AppText.cardTitle.copyWith(color: AppColors.stampViolet)),
            ),
            Text('+${fcfa(a.prixSupp)}',
                style: AppText.number.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.stampViolet)),
          ]),
          const SizedBox(height: 4),
          Text(quoi, style: AppText.bodyStrong),
          Text('« ${a.motif} »', style: AppText.body),
          if (a.photos.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onVoirPhoto(a.photos.first),
                icon: const Icon(Icons.image_outlined, size: 20),
                label: const Text('Voir la photo du prestataire'),
              ),
            ),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => onRepondre(a, false),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Refuser'),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: FilledButton(
                onPressed: () => onRepondre(a, true),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Accepter'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
