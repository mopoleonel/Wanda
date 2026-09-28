// dashbordParticulier.dart
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// IMPORT DE TA PAGE D'ACCUEIL
import 'package:wanda/screens/homepage.dart';

class DashbordParticulier extends StatefulWidget {
  const DashbordParticulier({super.key});

  @override
  State<DashbordParticulier> createState() => _DashbordParticulierState();
}

class _DashbordParticulierState extends State<DashbordParticulier> {
  int _selectedIndex = 0;
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? userData;
  bool isAvailable = false;
  bool isLoading = true;

  bool hasValidSubscription = false;
  bool trialAlreadyUsed = false;
  String statusMessage = "Vérification...";
  String selectedLanguage = "Français";

  List<Map<String, dynamic>> sollicitations = [];
  List<FlSpot> graphSpots = [];

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadData();
    _fetchSollicitations();
    Timer.periodic(const Duration(minutes: 1), (t) {
      if (mounted && _selectedIndex == 1) setState(() {});
    });
  }

  // ================= SÉCURITÉ & CONNECTIVITÉ =================

  Future<void> _checkConnectivity() async {
    var result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) {
      _showSnackBar("Pas de connexion internet. Vérifiez vos données mobiles.",
          isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(message, style: const TextStyle(color: Colors.white))),
        ]),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(15),
      ),
    );
  }

  // --- CHARGEMENT DES DONNÉES UTILISATEUR ---
  Future<void> _loadData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('particuliers')
          .select()
          .eq('id', user.id)
          .single()
          .timeout(const Duration(seconds: 10));

      String? rawExpiry = data['abonnement_expire_at'];
      String? typeAbo = data['type_abonnement'];
      DateTime? expiryDate =
          rawExpiry != null ? DateTime.parse(rawExpiry) : null;
      DateTime now = DateTime.now();

      if (expiryDate != null && now.isBefore(expiryDate)) {
        hasValidSubscription = true;
        int remaining = expiryDate.difference(now).inDays;
        statusMessage = "Pro ($typeAbo) : $remaining jours restants";
      } else {
        hasValidSubscription = false;
        statusMessage = "Abonnement requis pour être en ligne";
      }

      if (mounted) {
        setState(() {
          userData = data;
          isAvailable = data['is_available'] ?? false;
          trialAlreadyUsed = data['essai_utilise'] ?? false;
          _nomController.text = (data['nom'] ?? "").toString();
          _phoneController.text = (data['telephone'] ?? "").toString();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnackBar("Erreur de synchronisation profil.");
    }
  }

  // --- RÉCUPÉRATION DES SOLLICITATIONS ---
  Future<void> _fetchSollicitations() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('sollicitations')
          .select('*')
          .eq('prestataire_id', userId)
          .order('date_sollicitation', ascending: false)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          sollicitations = List<Map<String, dynamic>>.from(response);
          _generateGraphSpots();
        });
      }
    } catch (e) {
      debugPrint("Erreur Fetch: $e");
    }
  }

  // --- LOGIQUE DES MISSIONS (AVEC REMISE EN LIGNE AUTO) ---
  Future<void> _updateMissionStatus(String id, String newStatus,
      {String? phone}) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase
          .from('sollicitations')
          .update({'statut': newStatus}).eq('id', id);

      if (newStatus == 'accepte') {
        await supabase
            .from('particuliers')
            .update({'is_available': false}).eq('id', userId);
        setState(() => isAvailable = false);
        if (phone != null) _callClient(phone);
      }

      if (newStatus == 'termine') {
        await supabase
            .from('particuliers')
            .update({'is_available': true}).eq('id', userId);
        await supabase.from('sollicitations').update(
            {'date_fin': DateTime.now().toIso8601String()}).eq('id', id);
        setState(() => isAvailable = true);
        _showSnackBar("Mission terminée ! Vous êtes de nouveau en ligne.",
            isError: false);
      }
      _fetchSollicitations();
    } catch (e) {
      _showSnackBar("Erreur lors de la mise à jour.");
    }
  }

  void _generateGraphSpots() {
    Map<int, int> dailyCounts = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};
    DateTime now = DateTime.now();
    for (var s in sollicitations) {
      if (s['date_sollicitation'] == null) continue;
      DateTime d = DateTime.parse(s['date_sollicitation']);
      int diff = now.difference(d).inDays;
      if (diff >= 0 && diff < 7)
        dailyCounts[6 - diff] = (dailyCounts[6 - diff] ?? 0) + 1;
    }
    setState(() {
      graphSpots = dailyCounts.entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
          .toList();
    });
  }

  String _getTimeDisplay(Map item) {
    if (item['statut'] == 'termine' && item['date_fin'] != null) {
      final dateFin = DateTime.parse(item['date_fin']).toLocal();
      return "Terminé à ${DateFormat('HH:mm').format(dateFin)}";
    }
    if (item['date_sollicitation'] == null) return "Inconnue";
    final diff =
        DateTime.now().difference(DateTime.parse(item['date_sollicitation']));
    return "Reçu il y a ${diff.inHours}h ${diff.inMinutes % 60}m";
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

  Future<void> _toggleVisibility(bool value) async {
    if (!hasValidSubscription) {
      _showSubscriptionMenu();
      return;
    }
    setState(() => isAvailable = value);
    try {
      await supabase.from('particuliers').update({'is_available': value}).eq(
          'id', supabase.auth.currentUser!.id);
    } catch (e) {
      setState(() => isAvailable = !value);
      _showSnackBar("Erreur réseau : visibilité non mise à jour.");
    }
  }

  Future<void> _updateProfileInfo() async {
    if (_nomController.text.isEmpty) {
      _showSnackBar("Le nom est obligatoire.");
      return;
    }
    setState(() => isLoading = true);
    try {
      await supabase.from('particuliers').update({
        'nom': _nomController.text.trim(),
        'telephone': _phoneController.text.trim(),
      }).eq('id', supabase.auth.currentUser!.id);
      _showSnackBar("Profil mis à jour !", isError: false);
      _loadData();
    } catch (e) {
      _showSnackBar("Erreur de mise à jour.");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeView(),
      _buildAnalyticsView(),
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

  // --- VUE 1 : ACCUEIL ---
  Widget _buildHomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _buildHeroHeader(),
        const SizedBox(height: 25),
        _buildVisibilitySwitch(),
        const SizedBox(height: 30),
        _buildSectionHeader(
            "Audience hebdomadaire", "Statistiques de demandes"),
        _buildActivityGraph(),
        const SizedBox(height: 100),
      ]),
    );
  }

  Widget _buildHeroHeader() {
    return Column(children: [
      _circleAvatar(60),
      const SizedBox(height: 15),
      Text("${userData?['nom'] ?? ''}",
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(
          userData?['service_propose']?.toString().toUpperCase() ??
              "PRESTATAIRE",
          style: const TextStyle(
              color: Colors.greenAccent, fontSize: 12, letterSpacing: 1.2)),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _miniStat("Note", "5.0", Icons.star, Colors.amber),
        _miniStat("Missions", "${sollicitations.length}", Icons.task_alt,
            Colors.blueAccent),
        _miniStat("Fiabilité", "100%", Icons.verified_user, Colors.greenAccent),
      ])
    ]);
  }

  Widget _buildVisibilitySwitch() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: isAvailable
              ? Colors.greenAccent.withOpacity(0.1)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
              color: isAvailable ? Colors.greenAccent : Colors.white10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isAvailable ? "VOUS ÊTES EN LIGNE" : "VOUS ÊTES HORS LIGNE",
              style: TextStyle(
                  color: isAvailable ? Colors.greenAccent : Colors.white38,
                  fontWeight: FontWeight.bold)),
          Text(statusMessage,
              style: const TextStyle(color: Colors.white24, fontSize: 11)),
        ]),
        Switch(
            value: isAvailable,
            activeColor: Colors.greenAccent,
            onChanged: _toggleVisibility),
      ]),
    );
  }

  // --- VUE 2 : MISSIONS ---
  Widget _buildAnalyticsView() {
    return Column(children: [
      const SizedBox(height: 20),
      _buildSectionHeader("Gestion des Missions", "Interventions en cours"),
      Expanded(
        child: sollicitations.isEmpty
            ? const Center(
                child: Text("Aucune mission",
                    style: TextStyle(color: Colors.white24)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: sollicitations.length,
                itemBuilder: (context, index) {
                  final item = sollicitations[index];
                  final status = item['statut'];
                  final nomComplet =
                      "${item['nom_citoyen'] ?? 'Client'} ${item['prenom_citoyen'] ?? ''}"
                          .trim();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: status == 'accepte'
                            ? Colors.greenAccent.withOpacity(0.05)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                            color: status == 'accepte'
                                ? Colors.greenAccent
                                : Colors.white10)),
                    child: Column(children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                            backgroundColor: status == 'accepte'
                                ? Colors.greenAccent
                                : Colors.white10,
                            child:
                                const Icon(Icons.person, color: Colors.white)),
                        title: Text(
                            nomComplet.isEmpty ? "Client WANDA" : nomComplet,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(_getTimeDisplay(item),
                            style: TextStyle(
                                color: status == 'termine'
                                    ? Colors.greenAccent
                                    : Colors.amberAccent,
                                fontSize: 11)),
                        trailing: status == 'accepte'
                            ? IconButton(
                                icon: const Icon(Icons.call,
                                    color: Colors.greenAccent),
                                onPressed: () =>
                                    _callClient(item['numero_citoyen']))
                            : null,
                      ),
                      const SizedBox(height: 10),
                      if (status == 'en_attente')
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                                onPressed: () => _updateMissionStatus(
                                    item['id'], 'accepte',
                                    phone: item['numero_citoyen']),
                                icon:
                                    const Icon(Icons.phone_forwarded, size: 18),
                                label: const Text("ACCEPTER & APPELER"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.greenAccent,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)))))
                      else if (status == 'accepte')
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                                onPressed: () =>
                                    _updateMissionStatus(item['id'], 'termine'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white10),
                                child: const Text("TERMINER LA MISSION",
                                    style: TextStyle(color: Colors.white))))
                      else
                        Align(alignment: Alignment.centerRight, child: Text(status.toString().toUpperCase(), style: TextStyle(color: status == 'termine' ? Colors.greenAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold))),
                    ]),
                  );
                }),
      ),
      const SizedBox(height: 80),
    ]);
  }

  // --- VUE 3 : PAGE PROFIL ---
  Widget _buildProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      child: Column(children: [
        const Text("Réglages du Profil",
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        _circleAvatar(60, editable: true),
        const SizedBox(height: 40),
        _buildInputField("Nom complet", _nomController, Icons.person),
        _buildInputField("Téléphone", _phoneController, Icons.phone),
        const SizedBox(height: 20),
        ElevatedButton(
            onPressed: _updateProfileInfo,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15))),
            child: const Text("SAUVEGARDER LES CHANGEMENTS",
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold))),
        const SizedBox(height: 30),
        _buildSectionHeader("Mon Abonnement",
            "Statut : ${hasValidSubscription ? 'ACTIF' : 'INACTIF'}"),
        Card(
          color: Colors.white.withOpacity(0.05),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ListTile(
            leading: Icon(Icons.verified_user,
                color:
                    hasValidSubscription ? Colors.greenAccent : Colors.white24),
            title: Text(
                hasValidSubscription
                    ? "Compte Pro ${userData?['type_abonnement'] ?? ''}"
                    : "Devenir Membre Pro",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(statusMessage,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: _showSubscriptionMenu,
          ),
        ),
        const SizedBox(height: 40),
        ElevatedButton.icon(
            onPressed: () async {
              await supabase.auth.signOut();
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) => HomePage(
                          onSelectRole: (r) {}, onPrestataireClick: () {})),
                  (route) => false);
            },
            icon: const Icon(Icons.logout),
            label: const Text("SE DÉCONNECTER"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)))),
      ]),
    );
  }

  // --- WIDGETS UI ---
  Widget _circleAvatar(double rad, {bool editable = false}) {
    String? url = userData?['photo_pro_url'];
    return Stack(alignment: Alignment.center, children: [
      Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
              color: Colors.greenAccent, shape: BoxShape.circle),
          child: CircleAvatar(
              radius: rad,
              backgroundColor: Colors.white10,
              backgroundImage:
                  (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
              child: (url == null || url.isEmpty)
                  ? const Icon(Icons.person,
                      size: 30, color: Colors.greenAccent)
                  : null)),
      if (editable)
        Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
                onTap: _pickImg,
                child: const CircleAvatar(
                    backgroundColor: Colors.greenAccent,
                    radius: 18,
                    child: Icon(Icons.camera_alt,
                        size: 16, color: Colors.black)))),
    ]);
  }

  Future<void> _pickImg() async {
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (img != null) {
        final userId = supabase.auth.currentUser!.id;
        await supabase.storage.from('profils').upload(
            'pro_$userId.jpg', File(img.path),
            fileOptions: const FileOptions(upsert: true));
        final url =
            supabase.storage.from('profils').getPublicUrl('pro_$userId.jpg');
        await supabase
            .from('particuliers')
            .update({'photo_pro_url': url}).eq('id', userId);
        _loadData();
      }
    } catch (e) {
      _showSnackBar("Erreur lors de l'upload.");
    }
  }

  Widget _buildActivityGraph() {
    return Container(
        height: 180,
        width: double.infinity,
        padding: const EdgeInsets.only(top: 20, right: 20, left: 10),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(25)),
        child: graphSpots.isEmpty
            ? const Center(
                child: Text("Initialisation...",
                    style: TextStyle(color: Colors.white10)))
            : LineChart(LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                    LineChartBarData(
                        spots: graphSpots,
                        isCurved: true,
                        color: Colors.greenAccent,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                            show: true,
                            color: Colors.greenAccent.withOpacity(0.1)))
                  ])));
  }

  Widget _miniStat(String l, String v, IconData i, Color c) {
    return Column(children: [
      Icon(i, color: c, size: 20),
      const SizedBox(height: 5),
      Text(v,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      Text(l, style: const TextStyle(color: Colors.white38, fontSize: 10))
    ]);
  }

  Widget _buildInputField(String l, TextEditingController c, IconData i) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 8),
          TextField(
              controller: c,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  prefixIcon: Icon(i, color: Colors.greenAccent, size: 20),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none)))
        ]));
  }

  // ==========================================
  // LA BARRE DE NAVIGATION (FIXÉE POUR ÉVITER L'OVERFLOW)
  // ==========================================
  Widget _buildBottomNav() {
    return Container(
        margin: const EdgeInsets.fromLTRB(25, 0, 25, 25),
        height: 65, // Hauteur optimale
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                  color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
            ]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navItem(Icons.dashboard_rounded, 0, "Dash"),
            _navItem(Icons.assignment_ind_rounded, 1, "Missions"),
            _navItem(Icons.person_pin_rounded, 2, "Profil"),
          ],
        ));
  }

  Widget _navItem(IconData icon, int index, String label) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        if (index == 1) _fetchSollicitations();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.greenAccent.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? Colors.greenAccent : Colors.white24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.greenAccent : Colors.white24,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String t, String s) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
            alignment: Alignment.centerLeft,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Text(s,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 15)
            ])));
  }

  // --- MENU DES OFFRES PRO AVEC TES TARIFS EXACTS ---
  void _showSubscriptionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F2E23),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text("Choisissez votre forfait Pro",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            if (!trialAlreadyUsed)
              _subOption("ESSAI GRATUIT (14 Jours)", "Offre de bienvenue",
                  Colors.greenAccent, () {
                Navigator.pop(context);
                _activateTrial();
              }),
            _subOption("FORFAIT 1 SEMAINE", "3 000 FCFA", Colors.white, () {}),
            _subOption("FORFAIT 2 SEMAINES", "5 000 FCFA", Colors.white, () {}),
            _subOption(
                "FORFAIT 1 MOIS", "8 000 FCFA", Colors.amberAccent, () {}),
            _subOption(
                "FORFAIT 3 MOIS", "15 000 FCFA", Colors.blueAccent, () {}),
            const SizedBox(height: 20),
            const Text("Activation instantanée via Mobile Money",
                style: TextStyle(color: Colors.white24, fontSize: 11)),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _subOption(String t, String s, Color c, VoidCallback on) {
    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
          title: Text(t,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(s,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios,
              size: 14, color: Colors.white10),
          onTap: on),
    );
  }

  Future<void> _activateTrial() async {
    setState(() => isLoading = true);
    try {
      final expiry = DateTime.now().add(const Duration(days: 14));
      await supabase.from('particuliers').update({
        'essai_utilise': true,
        'type_abonnement': 'ESSAI',
        'abonnement_expire_at': expiry.toIso8601String()
      }).eq('id', supabase.auth.currentUser!.id);
      _loadData();
      _showSnackBar("Période d'essai activée !", isError: false);
    } catch (e) {
      _showSnackBar("Erreur d'activation.");
    }
  }
}
