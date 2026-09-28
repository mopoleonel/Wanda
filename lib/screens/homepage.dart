import 'package:flutter/material.dart';
import 'citoyenpage.dart';
import 'loginPrestaPage.dart';
import 'dashbordEntreprisePage.dart';

class HomePage extends StatelessWidget {
  final Function(String role) onSelectRole;
  final VoidCallback onPrestataireClick;

  const HomePage({
    super.key,
    required this.onSelectRole,
    required this.onPrestataireClick,
  });

  // Couleurs harmonisées avec ton logo
  static const Color wandaGreenMedium = Color(0xFF43A047);
  static const Color wandaGreenLight = Color(0xFF81C784);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF081F17), // très sombre en haut
              Color(0xFF0F2E23),
              Color(0xFF123D2E),
              Color(0xFF1B5E20), // plus clair en bas
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                /// ================= HEADER =================
                Column(
                  children: [
                    const SizedBox(height: 40),

                    // 🔥 HALO + LOGO
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
                        height: 150,
                      ),
                    ),

                    const SizedBox(height: 25),

                    const Text(
                      "Bienvenue sur WANDA",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "La plateforme intelligente pour améliorer votre ville.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),

                /// ================= CARTES =================
                Column(
                  children: [
                    _buildRoleCard(
                      title: "Citoyen",
                      description:
                          "Signalez des incidents et suivez les actions de la municipalité.",
                      icon: Icons.person,
                      accentColor: wandaGreenMedium,
                      onTap: () {
                        onSelectRole("citizen");
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CitoyenPage()),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildRoleCard(
                      title: "Prestataire",
                      description:
                          "Recevez des missions et intervenez sur le terrain.",
                      icon: Icons.business_center,
                      accentColor: wandaGreenLight,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginPrestaPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                /// ================= FOOTER =================
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    "© 2026 WANDA •  Cameroun",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
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

  static Widget _buildRoleCard({
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
            // Icône
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: accentColor,
                size: 28,
              ),
            ),

            const SizedBox(width: 18),

            // Texte
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0B3022),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}
