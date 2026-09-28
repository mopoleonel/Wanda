// loginCitoyen.dart
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// IMPORT DE LA PAGE DE DESTINATION
import 'package:wanda/screens/service_page.dart';

class LoginCitoyenPage extends StatefulWidget {
  const LoginCitoyenPage({super.key});

  @override
  State<LoginCitoyenPage> createState() => _LoginCitoyenPageState();
}

class _LoginCitoyenPageState extends State<LoginCitoyenPage> {
  bool isLogin = true;
  bool obscurePassword = true;
  bool isLoading = false;

  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final prenomController = TextEditingController();

  static const Color wandaGreen = Color(0xFF43A047);

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

  // ================= LOGIQUE AUTHENTIFICATION =================

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      if (isLogin) {
        // --- CONNEXION ---
        await supabase.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
        _redirectUser();
      } else {
        // --- INSCRIPTION ---
        final AuthResponse res = await supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        final String? userId = res.user?.id;
        if (userId == null)
          throw "Erreur lors de la création de l'identifiant.";

        // 1. On insère dans 'profiles' d'abord (Table de référence)
        await supabase.from('profiles').insert({
          'id': userId,
          'user_type': 'citoyen',
        });

        // 2. On insère dans 'citoyens' (Grâce à la politique RLS que tu viens de fixer)
        await supabase.from('citoyens').insert({
          'citoyen_id': userId,
          'nom': nameController.text.trim(),
          'prenom': prenomController.text.trim(),
          'email': emailController.text.trim(),
          'telephone': phoneController.text.trim(),
        });

        // MODIFICATION ICI : Au lieu de _redirectUser(), on bascule sur la connexion
        _showAlert("Compte créé avec succès ! Connectez-vous.", isError: false);

        setState(() {
          isLogin =
              true; // Renvoie l'utilisateur vers le formulaire de connexion
          passwordController.clear(); // Vide le mot de passe pour la sécurité
          isLoading = false;
        });
      }
    } on AuthException catch (e) {
      if (e.message.contains("already registered")) {
        _showAlert("Cet email est déjà utilisé. Connectez-vous.");
        setState(() => isLogin = true);
      } else {
        _showAlert(e.message);
      }
    } on PostgrestException catch (e) {
      _showAlert("Erreur Base de données : ${e.message}");
    } catch (e) {
      _showAlert("Une erreur inattendue est survenue.");
    } finally {
      // On n'arrête le chargement ici que si on n'a pas déjà fait le setState du dessus
      if (mounted && isLogin) setState(() => isLoading = false);
    }
  }

  void _redirectUser() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ServicePage()),
      );
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
            colors: [Color(0xFF081F17), Color(0xFF0F2E23), Color(0xFF1B5E20)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // 🔥 HALO + LOGO (Design WANDA)
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.8),
                            blurRadius: 50,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        "assets/images/wanda_logo.png",
                        height: 120,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildFormContainer(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
            children: [
              Text(
                isLogin ? "Espace Citoyen" : "Rejoindre WANDA",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 25),
              if (!isLogin) ...[
                _buildField(nameController, "Nom", Icons.person),
                const SizedBox(height: 16),
                _buildField(prenomController, "Prénom", Icons.person_outline),
                const SizedBox(height: 16),
                _buildField(phoneController, "Téléphone", Icons.phone,
                    type: TextInputType.phone),
                const SizedBox(height: 16),
              ],
              _buildField(emailController, "Email", Icons.email,
                  type: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _buildField(passwordController, "Mot de passe", Icons.lock,
                  isPass: true),
              const SizedBox(height: 30),
              _buildSubmitButton(),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: () => setState(() => isLogin = !isLogin),
                child: RichText(
                  text: TextSpan(
                    text:
                        isLogin ? "Pas encore de compte ? " : "Déjà membre ? ",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    children: [
                      TextSpan(
                        text: isLogin ? "S'inscrire" : "Se connecter",
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller, String label, IconData icon,
      {bool isPass = false, TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      obscureText: isPass ? obscurePassword : false,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      validator: (v) => (v == null || v.isEmpty) ? "Champ obligatoire" : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.greenAccent, size: 20),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70),
                onPressed: () =>
                    setState(() => obscurePassword = !obscurePassword),
              )
            : null,
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: isLoading ? null : _submitForm,
      style: ElevatedButton.styleFrom(
        backgroundColor: wandaGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Text(isLogin ? "SE CONNECTER" : "REJOINDRE LA COMMUNAUTÉ",
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    );
  }
}
