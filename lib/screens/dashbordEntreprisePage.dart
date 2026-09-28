import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// IMPORT DE TA PAGE D'ACCUEIL (Vérifie bien le chemin)
import 'package:wanda/screens/homepage.dart';

class DashbordEntreprisePage extends StatefulWidget {
  const DashbordEntreprisePage({super.key});

  @override
  State<DashbordEntreprisePage> createState() => _DashbordEntreprisePageState();
}

class _DashbordEntreprisePageState extends State<DashbordEntreprisePage> {
  int _selectedIndex = 0;
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? entrepriseData;
  List<Map<String, dynamic>> signalements = [];
  bool isLoading = true;

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final Map<String, List<String>> sectorMapping = {
    "Hydraulique (Fuites d'eau, etc.)": ["Fuite d'eau"],
    "Électricité (Pannes, Poteaux, etc.)": ["Électricité"],
    "Environnement (Déchets, etc.)": ["Dépôt d'ordures"],
    "BTP / Voirie (Nids de poule, etc.)": ["BTP / Voirie"],
    "Sécurité Publique": ["Sécurité Publique", "Autre (IA)"],
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final ent = await supabase
          .from('entreprises')
          .select()
          .eq('id', user.id)
          .single();
      String monSecteur = ent['secteur_activite'] ?? "";
      List<String> problemesAssocies =
          sectorMapping[monSecteur] ?? [monSecteur];

      final sigs = await supabase
          .from('signalements')
          .select()
          .inFilter('type_probleme', problemesAssocies)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          entrepriseData = ent;
          _nomController.text = ent['nom_entreprise'] ?? "";
          _phoneController.text = ent['telephone'] ?? "";
          signalements = List<Map<String, dynamic>>.from(sigs);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _updateLogo() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      setState(() => isLoading = true);
      final file = File(image.path);
      final fileName = 'logo_${supabase.auth.currentUser!.id}.jpg';
      final path = 'logos/$fileName';
      await supabase.storage
          .from('entreprise_assets')
          .upload(path, file, fileOptions: const FileOptions(upsert: true));
      final String publicUrl =
          supabase.storage.from('entreprise_assets').getPublicUrl(path);
      await supabase.from('entreprises').update({'logo_url': publicUrl}).eq(
          'id', supabase.auth.currentUser!.id);
      _showSnackBar("Logo mis à jour !", isError: false);
      _loadData();
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    try {
      setState(() => isLoading = true);
      await supabase.from('entreprises').update({
        'nom_entreprise': _nomController.text,
        'telephone': _phoneController.text,
      }).eq('id', supabase.auth.currentUser!.id);
      _showSnackBar("Profil mis à jour", isError: false);
      _loadData();
    } catch (e) {
      _showSnackBar("Erreur de mise à jour");
      setState(() => isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  HomePage(onSelectRole: (r) {}, onPrestataireClick: () {})),
          (route) => false);
    }
  }

  Future<void> _deleteAccount() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F2E23),
        title: const Text("Supprimer définitivement ?",
            style: TextStyle(color: Colors.white)),
        content: const Text(
            "Cette action supprimera votre entreprise de la plateforme.",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ANNULER")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("SUPPRIMER",
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      await supabase
          .from('entreprises')
          .delete()
          .eq('id', supabase.auth.currentUser!.id);
      _signOut();
    }
  }

  Future<void> _updateStatut(String id, String newStatut) async {
    try {
      await supabase
          .from('signalements')
          .update({'statut': newStatut}).eq('id', id);
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showSnackBar("Statut mis à jour.", isError: false);
      _loadData();
    } catch (e) {
      _showSnackBar("Erreur : $e");
    }
  }

  void _launchMaps(dynamic lat, dynamic lng) {
    if (lat == null || lng == null) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => MapInternePage(
                destLat: double.parse(lat.toString()),
                destLng: double.parse(lng.toString()),
                allSignalements: signalements)));
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildMainDashboard(),
      MapInternePage(allSignalements: signalements),
      _buildHistoryPage(),
      _buildProfilePage()
    ];

    return Scaffold(
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [
          Color(0xFF081F17),
          Color(0xFF0F2E23),
          Color(0xFF1B5E20)
        ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.greenAccent))
            : SafeArea(child: pages[_selectedIndex]),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMainDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(),
        _buildAnalyticsSection(),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text("Missions actives",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold))),
        _buildMissionsList(false)
      ]),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white10,
            backgroundImage: entrepriseData?['logo_url'] != null
                ? NetworkImage(entrepriseData!['logo_url'])
                : null,
            child: entrepriseData?['logo_url'] == null
                ? const Icon(Icons.business, color: Colors.greenAccent)
                : null),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entrepriseData?['nom_entreprise'] ?? "Entreprise",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text(entrepriseData?['secteur_activite'] ?? "",
              style: const TextStyle(color: Colors.white70, fontSize: 12))
        ])),
      ]),
    );
  }

  Widget _buildAnalyticsSection() {
    int resolus = signalements.where((s) => s['statut'] == 'resolu').length;
    int enCours = signalements.where((s) => s['statut'] == 'en_cours').length;
    int attente = signalements.where((s) => s['statut'] == 'en_attente').length;
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      height: 220,
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10)),
      child: Row(children: [
        Expanded(
            flex: 2,
            child: PieChart(PieChartData(
                sectionsSpace: 5,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(
                      value: (resolus == 0 && enCours == 0 && attente == 0)
                          ? 1
                          : resolus.toDouble(),
                      color: Colors.greenAccent,
                      radius: 15,
                      showTitle: false),
                  PieChartSectionData(
                      value: enCours.toDouble(),
                      color: Colors.blueAccent,
                      radius: 15,
                      showTitle: false),
                  PieChartSectionData(
                      value: attente.toDouble(),
                      color: Colors.orangeAccent,
                      radius: 15,
                      showTitle: false),
                ]))),
        Expanded(
            flex: 3,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendItem("Réussies", Colors.greenAccent, resolus),
                  _legendItem("En cours", Colors.blueAccent, enCours),
                  _legendItem("Alertes", Colors.orangeAccent, attente)
                ]))
      ]),
    );
  }

  Widget _buildMissionsList(bool isHistory) {
    final data = isHistory
        ? signalements.where((s) => s['statut'] == 'resolu').toList()
        : signalements.where((s) => s['statut'] != 'resolu').toList();
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: data.isEmpty ? 1 : data.length,
      itemBuilder: (context, index) {
        if (data.isEmpty)
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text("Aucune mission",
                      style: TextStyle(color: Colors.white24))));
        return _buildMissionCard(data[index]);
      },
    );
  }

  Widget _buildMissionCard(Map<String, dynamic> signal) {
    Color statusColor = signal['statut'] == 'resolu'
        ? Colors.greenAccent
        : (signal['statut'] == 'en_cours'
            ? Colors.blueAccent
            : Colors.orangeAccent);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: ListTile(
        onTap: () => _showMissionDetails(signal),
        leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: signal['image_url'] != null
                ? Image.network(signal['image_url'],
                    width: 50, height: 50, fit: BoxFit.cover)
                : const Icon(Icons.image, color: Colors.white10)),
        title: Text(signal['type_probleme'],
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        subtitle: Text(signal['statut'].toString().toUpperCase(),
            style:
                TextStyle(color: statusColor, fontSize: 10, letterSpacing: 1)),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: Colors.white24, size: 12),
      ),
    );
  }

  void _showMissionDetails(Map<String, dynamic> signal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F2E23),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(signal['image_url'],
                  height: 200, width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 25),
          Row(children: [
            if (signal['statut'] == 'en_attente')
              Expanded(
                  child: _actionBtn("INTERVENIR", Colors.blueAccent,
                      () => _updateStatut(signal['id'], 'en_cours'))),
            if (signal['statut'] == 'en_cours')
              Expanded(
                  child: _actionBtn("TERMINER", Colors.greenAccent,
                      () => _updateStatut(signal['id'], 'resolu'))),
          ]),
          const SizedBox(height: 15),
          ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _launchMaps(signal['latitude'], signal['longitude']);
              },
              icon: const Icon(Icons.map_rounded),
              label: const Text("VOIR L'ITINÉRAIRE"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _buildHistoryPage() {
    final historyData =
        signalements.where((s) => s['statut'] == 'resolu').toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        const Text("Historique des interventions",
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            "Voici la liste de toutes les missions terminées et validées par votre entreprise.",
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        const SizedBox(height: 30),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: historyData.isEmpty ? 1 : historyData.length,
          itemBuilder: (context, index) {
            if (historyData.isEmpty)
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(50),
                      child: Text("Aucun historique",
                          style: TextStyle(color: Colors.white24))));
            return _buildMissionCard(historyData[index]);
          },
        ),
        const SizedBox(height: 100),
      ]),
    );
  }

  Widget _buildProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      child: Column(children: [
        const Text("Profil Entreprise",
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        GestureDetector(
          onTap: _updateLogo,
          child: Stack(children: [
            CircleAvatar(
                radius: 60,
                backgroundColor: Colors.white10,
                backgroundImage: entrepriseData?['logo_url'] != null
                    ? NetworkImage(entrepriseData!['logo_url'])
                    : null,
                child: entrepriseData?['logo_url'] == null
                    ? const Icon(Icons.business,
                        size: 40, color: Colors.greenAccent)
                    : null),
            Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.greenAccent, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt,
                        size: 20, color: Colors.black))),
          ]),
        ),
        const SizedBox(height: 40),
        _buildEditableField(
            "Nom de l'entreprise", _nomController, Icons.business),
        const SizedBox(height: 15),
        _buildEditableField("Téléphone", _phoneController, Icons.phone),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _updateProfile,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15))),
          child: const Text("ENREGISTRER LES MODIFICATIONS",
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _signOut,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white10,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15))),
          child: const Text("SE DÉCONNECTER",
              style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 15),
        TextButton(
            onPressed: _deleteAccount,
            child: const Text("Supprimer le compte",
                style: TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 100),
      ]),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      height: 65,
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5))
          ]),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _navIcon(Icons.analytics_outlined, 0),
            _navIcon(Icons.map_outlined, 1),
            _navIcon(Icons.history_rounded, 2),
            _navIcon(Icons.person_outline, 3)
          ]),
    );
  }

  Widget _navIcon(IconData icon, int index) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        child: Icon(icon,
            size: 28, color: isSelected ? Colors.greenAccent : Colors.white24));
  }

  Widget _buildEditableField(
      String label, TextEditingController controller, IconData icon) {
    return TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: Icon(icon, color: Colors.greenAccent),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Colors.white10)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Colors.greenAccent))));
  }

  Widget _legendItem(String t, Color c, int count) {
    return Row(children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Text(t, style: const TextStyle(color: Colors.white70)),
      const Spacer(),
      Text(count.toString(), style: const TextStyle(color: Colors.white))
    ]);
  }

  Widget _actionBtn(String t, Color c, VoidCallback on) {
    return ElevatedButton(
        onPressed: on,
        style: ElevatedButton.styleFrom(
            backgroundColor: c, foregroundColor: Colors.black),
        child: Text(t));
  }
}

// ================= PAGE MAP (BOUTONS À GAUCHE + MODES) =================
class MapInternePage extends StatefulWidget {
  final double? destLat;
  final double? destLng;
  final List<Map<String, dynamic>> allSignalements;
  const MapInternePage(
      {super.key, this.destLat, this.destLng, required this.allSignalements});
  @override
  State<MapInternePage> createState() => _MapInternePageState();
}

class _MapInternePageState extends State<MapInternePage> {
  LatLng? userPos;
  bool loading = true;
  Set<Marker> _markers = {};
  MapType _currentMapType = MapType.normal;
  bool _isDarkMode = true;

  final String _darkMapStyle =
      '''[{"elementType": "geometry","stylers": [{"color": "#212121"}]},{"elementType": "labels.icon","stylers": [{"visibility": "off"}]},{"elementType": "labels.text.fill","stylers": [{"color": "#757575"}]},{"elementType": "labels.text.stroke","stylers": [{"color": "#212121"}]},{"featureType": "road","elementType": "geometry.fill","stylers": [{"color": "#2c2c2c"}]},{"featureType": "water","elementType": "geometry","stylers": [{"color": "#000000"}]}]''';

  @override
  void initState() {
    super.initState();
    _setupMap();
  }

  Future<void> _setupMap() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      LatLng uPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        userPos = uPos;
        for (var sig in widget.allSignalements) {
          _markers.add(Marker(
              markerId: MarkerId(sig['id'].toString()),
              position: LatLng(double.parse(sig['latitude'].toString()),
                  double.parse(sig['longitude'].toString())),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
              onTap: () => _showMarkerDetails(sig)));
        }
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
    }
  }

  void _showTypePicker() {
    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0F2E23),
        builder: (context) => Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _mType(MapType.normal, "Plan", Icons.map),
                  _mType(MapType.satellite, "Satellite", Icons.satellite),
                  _mType(MapType.hybrid, "Hybride", Icons.layers)
                ])));
  }

  Widget _mType(MapType t, String l, IconData i) => GestureDetector(
      onTap: () {
        setState(() => _currentMapType = t);
        Navigator.pop(context);
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
            backgroundColor:
                _currentMapType == t ? Colors.greenAccent : Colors.white10,
            child: Icon(i,
                color: _currentMapType == t ? Colors.black : Colors.white)),
        Text(l, style: const TextStyle(color: Colors.white))
      ]));

  void _showMarkerDetails(Map<String, dynamic> sig) {
    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0F2E23),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (ctx) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sig['image_url'] != null)
                    ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.network(sig['image_url'],
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover)),
                  const SizedBox(height: 15),
                  Text(sig['type_probleme'],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(sig['description'] ?? 'Pas de description',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Text("Statut: ${sig['statut']}",
                      style: const TextStyle(color: Colors.greenAccent)),
                ])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                    target: userPos ?? const LatLng(0, 0), zoom: 13),
                mapType: _currentMapType,
                myLocationEnabled: true,
                markers: _markers,
                style: (_currentMapType == MapType.normal && _isDarkMode)
                    ? _darkMapStyle
                    : null,
              ),
              Positioned(
                  top: 50,
                  left: 15,
                  child: Column(children: [
                    FloatingActionButton.small(
                        onPressed: _showTypePicker,
                        backgroundColor: const Color(0xFF0F2E23),
                        child: const Icon(Icons.layers_rounded,
                            color: Colors.greenAccent)),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                        onPressed: () =>
                            setState(() => _isDarkMode = !_isDarkMode),
                        backgroundColor: const Color(0xFF0F2E23),
                        child: Icon(
                            _isDarkMode
                                ? Icons.wb_sunny
                                : Icons.nightlight_round,
                            color: Colors.greenAccent)),
                  ])),
            ]),
    );
  }
}
