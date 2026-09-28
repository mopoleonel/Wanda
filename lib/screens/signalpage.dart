// SignalPage.dart
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart'; // IMPORT POUR LA LOCALISATION
import 'citoyenpage.dart';

class SignalPage extends StatefulWidget {
  const SignalPage({super.key});

  @override
  State<SignalPage> createState() => _SignalPageState();
}

class _SignalPageState extends State<SignalPage> {
  int? selectedIndex;
  int step = 1;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  final supabase = Supabase.instance.client;
  bool analysing = false;

  final List<Map<String, dynamic>> problems = [
    {
      "title": "Dépôt d'ordures",
      "icon": Icons.delete_outline,
      "color": Colors.greenAccent
    },
    {
      "title": "Fuite d'eau",
      "icon": Icons.water_drop_outlined,
      "color": Colors.blueAccent
    },
    {"title": "Électricité", "icon": Icons.bolt, "color": Colors.amberAccent},
    {
      "title": "Autre (IA)",
      "icon": Icons.auto_awesome,
      "color": Colors.purpleAccent
    },
  ];

  // --- LOGIQUE CAMERA ---
  Future<void> _openCamera() async {
    final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50 // Réduit le poids pour l'IA et Supabase
        );
    if (photo != null) {
      setState(() => _image = File(photo.path));
    }
  }

  void _nextStep() {
    if (step == 2) {
      setState(() => step = 3);
      _analyse();
    } else {
      setState(() => step++);
    }
  }

  // --- LOGIQUE IA (GROQ) ---
  Future<Map<String, dynamic>> _callGroqVision(
      File imageFile, String category) async {
    final String apiKey = dotenv.env['GROQ_API_KEY'] ?? "";

    print("--- DEBUG GROQ ---");
    const String modelId = "meta-llama/llama-4-scout-17b-16e-instruct";
    print("Modèle utilisé : $modelId");

    final bytes = await imageFile.readAsBytes();
    final String base64Image = base64Encode(bytes);

    try {
      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              "model": modelId,
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "text",
                      "text": """Analyse cette image de signalement citoyen. 
                  Catégorie choisie : $category.
                  Instructions :
                  1. Vérifie si l'image est une photo réelle de terrain.
                  2. Si 'Autre (IA)', identifie précisément le problème.
                  3. Réponds uniquement en JSON : {"valid": bool, "detected_type": "string", "reason": "string"}"""
                    },
                    {
                      "type": "image_url",
                      "image_url": {
                        "url": "data:image/jpeg;base64,$base64Image"
                      }
                    }
                  ]
                }
              ],
              "response_format": {"type": "json_object"}
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final String content = decoded['choices'][0]['message']['content'];
        return jsonDecode(content);
      } else {
        throw "Erreur API Groq (${response.statusCode}): ${response.body}";
      }
    } catch (e) {
      print("ERREUR IA : $e");
      rethrow;
    }
  }

  // --- LOGIQUE GLOBALE (IA + GPS + SUPABASE) ---
  Future<void> _analyse() async {
    if (analysing) return;
    setState(() => analysing = true);

    try {
      // 1. RÉCUPÉRATION DE LA LOCALISATION
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final String selectedProblem = problems[selectedIndex!]["title"];

      // 2. VALIDATION IA
      final aiData = await _callGroqVision(_image!, selectedProblem);

      if (aiData['valid'] == false) {
        _showAIRejectDialog(aiData['reason'] ??
            "L'image ne semble pas correspondre à un incident réel.");
        return;
      }

      final String finalType = selectedProblem == "Autre (IA)"
          ? (aiData['detected_type'] ?? "Incident divers")
          : selectedProblem;

      // 3. UPLOAD IMAGE VERS SUPABASE
      final String fileName =
          'signal_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String path = 'uploads/$fileName';

      await supabase.storage.from('signalements').upload(path, _image!);
      final String imageUrl =
          supabase.storage.from('signalements').getPublicUrl(path);

      // 4. ATTRIBUTION ENTREPRISE
      final entrepriseData = await supabase
          .from('entreprises')
          .select('id')
          .eq('secteur_activite', finalType)
          .limit(1)
          .maybeSingle();

      // 5. INSERTION FINALE (AVEC GPS ET IA DETAILS)
      await supabase.from('signalements').insert({
        'type_probleme': finalType,
        'image_url': imageUrl,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'entreprise_id': entrepriseData != null ? entrepriseData['id'] : null,
        'citoyen_id': supabase.auth.currentUser?.id,
        'statut': 'en_attente',
        'ia_validation_details': aiData['reason'],
      });

      if (mounted) _showSuccess();
    } catch (e) {
      print("ERREUR ANALYSE : $e");
      setState(() {
        analysing = false;
        step = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur technique : $e"),
          backgroundColor: Colors.redAccent));
    }
  }

  // --- INTERFACE UTILISATEUR (UI) ---

  void _showAIRejectDialog(String reason) {
    setState(() {
      analysing = false;
      step = 2;
    });
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF0F2E23),
        title: const Text("Vérification IA",
            style: TextStyle(color: Colors.redAccent)),
        content: Text(reason, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("CORRIGER",
                  style: TextStyle(color: Colors.greenAccent)))
        ],
      ),
    );
  }

  void _showSuccess() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SuccessDialog());
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted)
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const CitoyenPage()),
            (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [
          Color(0xFF081F17),
          Color(0xFF0F2E23),
          Color(0xFF1B5E20)
        ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildStepIndicator(),
                const SizedBox(height: 40),
                Expanded(
                    child: step == 1
                        ? _buildStep1()
                        : step == 2
                            ? _buildStep2()
                            : _buildStep3()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(children: [
      const Text("Quel est l'incident ?",
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 30),
      Expanded(
        child: GridView.builder(
          itemCount: problems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15),
          itemBuilder: (context, index) {
            final item = problems[index];
            final isSelected = selectedIndex == index;
            return GestureDetector(
              onTap: () => setState(() => selectedIndex = index),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSelected ? Colors.greenAccent : Colors.white10,
                      width: isSelected ? 2 : 1),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item["icon"],
                          size: 40,
                          color:
                              isSelected ? Colors.greenAccent : Colors.white60),
                      const SizedBox(height: 10),
                      Text(item["title"],
                          style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white60,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ]),
              ),
            );
          },
        ),
      ),
      _buildButton(
          "CONTINUER", Colors.greenAccent, Icons.arrow_forward, _nextStep,
          isFull: true, enabled: selectedIndex != null),
    ]);
  }

  Widget _buildStep2() {
    return Column(children: [
      const Text("Preuve visuelle",
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 30),
      Container(
        width: double.infinity,
        height: 250,
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white10)),
        child: _image != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Image.file(_image!, fit: BoxFit.cover))
            : const Icon(Icons.camera_enhance_outlined,
                size: 50, color: Colors.white24),
      ),
      const SizedBox(height: 30),
      _buildButton(_image == null ? "OUVRIR LA CAMÉRA" : "REPRENDRE LA PHOTO",
          Colors.white10, Icons.camera_alt, _openCamera,
          isFull: true),
      const SizedBox(height: 15),
      if (_image != null)
        _buildButton("VALIDER LE SIGNALEMENT", Colors.greenAccent,
            Icons.check_circle, _nextStep,
            isFull: true),
    ]);
  }

  Widget _buildStep3() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CircularProgressIndicator(color: Colors.greenAccent),
      const SizedBox(height: 25),
      const Text("Analyse intelligente...",
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text("WANDA vérifie l'image avec l'IA",
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
    ]);
  }

  Widget _buildButton(String text, Color bg, IconData icon, VoidCallback onTap,
      {bool isFull = false, bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor:
              bg == Colors.greenAccent ? Colors.black : Colors.white,
          minimumSize: Size(isFull ? double.infinity : 150, 55),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          bool active = step >= index + 1;
          return Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: active ? 25 : 10,
              height: 10,
              decoration: BoxDecoration(
                  color: active ? Colors.greenAccent : Colors.white10,
                  borderRadius: BorderRadius.circular(10)));
        }));
  }
}

// --- DIALOG DE SUCCÈS ---
class SuccessDialog extends StatelessWidget {
  const SuccessDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(30),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
            color: const Color(0xFF0F2E23),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.2))),
        child: Material(
            color: Colors.transparent,
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.verified_rounded, size: 70, color: Colors.greenAccent),
              SizedBox(height: 20),
              Text("SIGNALÉ !",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text("Votre alerte a été transmise aux services compétents.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
      ),
    );
  }
}
