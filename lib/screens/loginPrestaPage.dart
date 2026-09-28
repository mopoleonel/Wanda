// LoginPrestaPage.dart
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Importe tes pages ici
import 'package:wanda/screens/dashbordEntreprisePage.dart';
import 'package:wanda/screens/dashbordParticulier.dart';

class LoginPrestaPage extends StatefulWidget {
  const LoginPrestaPage({super.key});

  @override
  State<LoginPrestaPage> createState() => _LoginPrestaPageState();
}

class _LoginPrestaPageState extends State<LoginPrestaPage> {
  bool isLogin = true;
  bool isEntreprise = true;
  bool obscurePassword = true;
  bool isLoading = false;

  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final nameController = TextEditingController();
  final prenomController = TextEditingController();
  final entrepriseController = TextEditingController();

  String? selectedSector;
  String? selectedService;

  final ImagePicker _picker = ImagePicker();
  File? entrepriseLogo;
  File? photoProfessionnelle;

  static const Color wandaGreen = Color(0xFF43A047);
  static const Color wandaLight = Color(0xFF81C784);

  final List<String> secteursActivite = [
    "Hydraulique (Fuites d'eau, etc.)",
    "Électricité (Pannes, Poteaux, etc.)",
    "BTP / Voirie (Nids de poule, etc.)",
    "Environnement (Déchets, etc.)",
    "Sécurité Publique",
  ];

  // ================= LOGIQUE D'ALERTE PROFESSIONNELLE =================

  void _showAlert(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
                child:
                    Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor:
            isError ? Colors.redAccent.withOpacity(0.9) : wandaGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(15),
      ),
    );
  }

  // ================= VALIDATIONS =================

  String? validateEmail(String? value) =>
      (value == null || !value.contains('@')) ? "Email invalide" : null;
  String? validatePhone(String? value) =>
      (value == null || value.length < 8) ? "Numéro invalide" : null;
  String? validateName(String? value) =>
      (value == null || value.isEmpty) ? "Champ obligatoire" : null;
  String? validatePassword(String? value) =>
      (value == null || value.length < 6) ? "Minimum 6 caractères" : null;

  void showError(String message) {
    _showAlert(message, isError: true);
  }

  Future<void> _pickImage(bool isLogo) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final file = File(image.path);
        if (file.lengthSync() > 5 * 1024 * 1024) {
          showError("L'image est trop lourde (maximum 5MB)");
          return;
        }
        setState(() {
          if (isLogo)
            entrepriseLogo = file;
          else
            photoProfessionnelle = file;
        });
      }
    } catch (e) {
      showError("Erreur lors de la sélection de l'image.");
    }
  }

  // ================= LOGIQUE SUPABASE =================

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (!isLogin &&
        (isEntreprise
            ? entrepriseLogo == null
            : photoProfessionnelle == null)) {
      showError("Veuillez sélectionner une photo ou un logo.");
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        // --- CONNEXION ---
        final AuthResponse res = await supabase.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(), // Ajout du .trim() ici
        );

        if (res.user != null) {
          final profile = await supabase
              .from('profiles')
              .select('user_type')
              .eq('id', res.user!.id)
              .maybeSingle(); // Utilisation de maybeSingle pour éviter le crash si vide

          if (profile != null) {
            _redirectUser(profile['user_type']);
          } else {
            showError("Profil introuvable en base de données.");
          }
        }
      } else {
        // --- INSCRIPTION ---
        final AuthResponse res = await supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        final String? userId = res.user?.id;
        if (userId == null)
          throw "Erreur lors de la création de l'identifiant.";

        String imageUrl = "";
        File? imageFile = isEntreprise ? entrepriseLogo : photoProfessionnelle;

        // 1. Upload Image d'abord
        if (imageFile != null) {
          final String path = 'profiles/$userId';
          await supabase.storage.from('profils').upload(path, imageFile);
          imageUrl = supabase.storage.from('profils').getPublicUrl(path);
        }

        // 2. Création du profil (Table profiles)
        final String type = isEntreprise ? 'entreprise' : 'particulier';
        await supabase.from('profiles').insert({
          'id': userId,
          'user_type': type,
        });

        // 3. Création des données métier (INCLUSION DU TÉLÉPHONE)
        if (isEntreprise) {
          await supabase.from('entreprises').insert({
            'id': userId,
            'nom_entreprise': entrepriseController.text.trim(),
            'secteur_activite': selectedSector,
            'telephone': phoneController.text.trim(),
            'logo_url': imageUrl,
          });
        } else {
          await supabase.from('particuliers').insert({
            'id': userId,
            'nom': nameController.text.trim(),
            'prenom': prenomController.text.trim(),
            'service_propose': selectedService,
            'telephone': phoneController.text.trim(),
            'photo_pro_url': imageUrl,
          });
        }

        if (mounted) {
          _showAlert("Compte créé avec succès ! Connectez-vous.",
              isError: false);
          setState(() {
            isLogin = true;
            isLoading = false;
          });
          passwordController.clear();
          confirmPasswordController.clear();
          phoneController.clear();
        }
      }
    } on AuthException catch (e) {
      if (e.message.contains("already registered")) {
        showError("Cet email est déjà utilisé.");
      } else if (e.message.contains("Invalid login credentials")) {
        showError("Email ou mot de passe incorrect.");
      } else {
        showError(e.message);
      }
    } on PostgrestException catch (e) {
      showError("Erreur base de données : ${e.message}");
    } on SocketException {
      showError("Problème de connexion internet.");
    } catch (e) {
      showError("Une erreur est survenue : $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _redirectUser(String type) {
    if (mounted) {
      Widget page = (type == 'entreprise')
          ? const DashbordEntreprisePage()
          : const DashbordParticulier();

      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF081F17),
              Color(0xFF0F2E23),
              Color(0xFF123D2E),
              Color(0xFF1B5E20)
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 30),
                          _buildLogo(),
                          const SizedBox(height: 30),
                          _buildFormContainer(),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 40)
        ],
      ),
      child: Image.asset("assets/images/wanda_logo.png", height: 110),
    );
  }

  Widget _buildFormContainer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLogin) _buildToggle(),
              const SizedBox(height: 20),
              TextFormField(
                  controller: emailController,
                  validator: validateEmail,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("Email", Icons.email)),
              const SizedBox(height: 16),
              if (!isLogin) ...[
                TextFormField(
                    controller: phoneController,
                    validator: validatePhone,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration("Téléphone", Icons.phone)),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: passwordController,
                obscureText: obscurePassword,
                validator: validatePassword,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _inputDecoration("Mot de passe", Icons.lock).copyWith(
                  suffixIcon: IconButton(
                      icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white70),
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword)),
                ),
              ),
              if (!isLogin) ..._buildRegisterFields(),
              const SizedBox(height: 30),
              _buildSubmitButton(),
              const SizedBox(height: 10),
              TextButton(
                  onPressed: () {
                    setState(() {
                      isLogin = !isLogin;
                    });
                  },
                  child: Text(isLogin ? "Créer un compte" : "Se connecter",
                      style: const TextStyle(color: Colors.white70))),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRegisterFields() {
    if (isEntreprise) {
      return [
        const SizedBox(height: 16),
        TextFormField(
            controller: entrepriseController,
            validator: (v) => (v == null || v.isEmpty) ? "Nom requis" : null,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration("Nom Entreprise", Icons.business)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          dropdownColor: const Color(0xFF0F2E23),
          value: selectedSector,
          validator: (v) => v == null ? "Sélectionnez un secteur" : null,
          items: secteursActivite
              .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12))))
              .toList(),
          onChanged: (v) => setState(() => selectedSector = v),
          decoration: _inputDecoration("Secteur", Icons.category),
        ),
        const SizedBox(height: 16),
        _buildImagePicker(true),
      ];
    } else {
      return [
        const SizedBox(height: 16),
        TextFormField(
            controller: nameController,
            validator: validateName,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration("Nom", Icons.person)),
        const SizedBox(height: 16),
        TextFormField(
            controller: prenomController,
            validator: validateName,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration("Prénom", Icons.person_outline)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          dropdownColor: const Color(0xFF0F2E23),
          value: selectedService,
          validator: (v) => v == null ? "Sélectionnez un service" : null,
          items: ["Plombier", "Électricien", "Maçon", "Froid & Clim"]
              .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, style: const TextStyle(color: Colors.white))))
              .toList(),
          onChanged: (v) => setState(() => selectedService = v),
          decoration: _inputDecoration("Service", Icons.build),
        ),
        const SizedBox(height: 16),
        _buildImagePicker(false),
      ];
    }
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: isLoading ? null : _submitForm,
      style: ElevatedButton.styleFrom(
          backgroundColor: wandaGreen,
          minimumSize: const Size(double.infinity, 55),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Text(isLogin ? "Se connecter" : "S'inscrire",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildToggle() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ChoiceChip(
          label: const Text("Entreprise"),
          selected: isEntreprise,
          onSelected: (_) => setState(() => isEntreprise = true),
          selectedColor: wandaGreen),
      const SizedBox(width: 10),
      ChoiceChip(
          label: const Text("Particulier"),
          selected: !isEntreprise,
          onSelected: (_) => setState(() => isEntreprise = false),
          selectedColor: wandaGreen),
    ]);
  }

  Widget _buildImagePicker(bool isLogo) {
    File? file = isLogo ? entrepriseLogo : photoProfessionnelle;
    return Column(children: [
      OutlinedButton.icon(
          onPressed: () => _pickImage(isLogo),
          icon: const Icon(Icons.image),
          label: Text(isLogo ? "Sélectionner Logo" : "Sélectionner Photo Pro"),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70)),
      if (file != null)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(file, height: 60))),
    ]);
  }

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.white70, size: 20),
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)));
}
