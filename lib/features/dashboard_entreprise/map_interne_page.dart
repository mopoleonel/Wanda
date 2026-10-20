import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/bordereau.dart';
import '../../data/models/signalement.dart';

/// Carte des signalements d'une entreprise. Les marqueurs prennent la
/// couleur du tampon de statut (reçu / en cours / résolu). Quand
/// [destLat]/[destLng] sont fournis, la carte s'ouvre centrée sur ce point.
class MapInternePage extends StatefulWidget {
  final double? destLat;
  final double? destLng;
  final List<Signalement> allSignalements;
  final bool showBack;

  const MapInternePage({
    super.key,
    this.destLat,
    this.destLng,
    required this.allSignalements,
    this.showBack = false,
  });

  @override
  State<MapInternePage> createState() => _MapInternePageState();
}

class _MapInternePageState extends State<MapInternePage> {
  static const _yaounde = LatLng(3.848, 11.502);

  LatLng? userPos;
  bool loading = true;
  Set<Marker> _markers = {};
  MapType _currentMapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    _setupMap();
  }

  double _hueFor(String statut) => switch (statut) {
        'en_cours' => BitmapDescriptor.hueOrange,
        'resolu' => BitmapDescriptor.hueGreen,
        _ => BitmapDescriptor.hueViolet,
      };

  Future<void> _setupMap() async {
    final markers = <Marker>{
      for (final sig in widget.allSignalements)
        Marker(
          markerId: MarkerId(sig.id),
          position: LatLng(sig.latitude, sig.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(sig.statut)),
          onTap: () => _showMarkerDetails(sig),
        ),
    };
    LatLng? pos;
    try {
      final p = await Geolocator.getCurrentPosition();
      pos = LatLng(p.latitude, p.longitude);
    } catch (_) {
      // Sans position, la carte s'ouvre sur la destination ou sur Yaoundé.
    }
    if (mounted) {
      setState(() {
        userPos = pos;
        _markers = markers;
        loading = false;
      });
    }
  }

  void _showMarkerDetails(Signalement sig) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sig.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Image.network(sig.imageUrl,
                      height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              const SizedBox(height: AppSpace.lg),
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FicheNumber(sig.id),
                      Text(sig.typeProbleme, style: AppText.sectionTitle),
                    ],
                  ),
                ),
                StatusStamp(FicheStatus.signalement(sig.statut)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final dest = widget.destLat != null && widget.destLng != null
        ? LatLng(widget.destLat!, widget.destLng!)
        : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: dest ?? userPos ?? _yaounde,
                    zoom: dest != null ? 16 : 13,
                  ),
                  mapType: _currentMapType,
                  myLocationEnabled: userPos != null,
                  zoomControlsEnabled: false,
                  markers: _markers,
                  padding: EdgeInsets.only(top: topInset + 80),
                ),
                Positioned(
                  top: topInset + AppSpace.md,
                  left: AppSpace.gutter,
                  right: AppSpace.gutter,
                  child: FicheCard(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Row(children: [
                      if (widget.showBack)
                        IconButton(
                          tooltip: 'Retour',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      else
                        const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.allSignalements.length} signalement${widget.allSignalements.length > 1 ? 's' : ''}',
                          style: AppText.cardTitle,
                        ),
                      ),
                      SegmentedButton<MapType>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity:
                              VisualDensity(horizontal: -3, vertical: -1),
                        ),
                        segments: const [
                          ButtonSegment(
                              value: MapType.normal, label: Text('Plan')),
                          ButtonSegment(
                              value: MapType.hybrid, label: Text('Satellite')),
                        ],
                        selected: {_currentMapType},
                        onSelectionChanged: (s) =>
                            setState(() => _currentMapType = s.first),
                      ),
                    ]),
                  ),
                ),
              ]),
      ),
    );
  }
}
