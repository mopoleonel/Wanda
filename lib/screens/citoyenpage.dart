import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wanda/screens/homepage.dart';
import 'package:wanda/screens/signalpage.dart';
import 'package:wanda/screens/service_page.dart';
import 'loginCitoyen.dart';

class CitoyenPage extends StatelessWidget {
  const CitoyenPage({super.key});

  static const Color wandaGreenMedium = Color(0xFF43A047);
  static const Color wandaGreenLight = Color(0xFF81C784);

  final List<String> images = const [
    "assets/images/city1.png",
    "assets/images/city2.png",
    "assets/images/city3.jpg",
    "assets/images/city4.jpg",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF081F17),
              Color(0xFF0F2E23),
              Color(0xFF123D2E),
              Color(0xFF1B5E20),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              /// ================= BOUTON RETOUR (HAUT GAUCHE) =================
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, left: 15),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),

              /// ================= LOGO + TITRE =================
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.99),
                      blurRadius: 50,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Image.asset(
                  "assets/images/wanda_logo.png",
                  height: 110,
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                "Espace Citoyen",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                "Signalez les problèmes et suivez votre ville",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 25),

              /// ================= MENU PRINCIPAL =================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildMenuCard(
                      title: "Signaler un problème",
                      description:
                          "Déclarez un incident urbain en quelques secondes.",
                      icon: Icons.report_problem,
                      accentColor: wandaGreenMedium,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignalPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    _buildMenuCard(
                      title: "Rechercher des services",
                      description:
                          "Consultez les services disponibles dans votre ville.",
                      icon: Icons.work,
                      accentColor: wandaGreenLight,
                      onTap: () {
                        final session =
                            Supabase.instance.client.auth.currentSession;
                        if (session != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ServicePage()),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginCitoyenPage()),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              /// ================= SLIDER =================
              Expanded(
                child: CarouselSlider(
                  options: CarouselOptions(
                    autoPlay: true,
                    enlargeCenterPage: true,
                    viewportFraction: 0.9,
                  ),
                  items: images.map((img) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        img,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildMenuCard({
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 26),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0B3022),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
