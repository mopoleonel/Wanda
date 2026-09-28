import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    // 🎬 Animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // 🔥 Animation pulse
    _scale = Tween(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // 🌫 Fade animation
    _opacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // ⏱ Navigation automatique après 3 sec
    Timer(const Duration(seconds: 3), () {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
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
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// 🔥 HALO + LOGO IDENTIQUE A HOMEPAGE
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.9),
                          blurRadius: 60,
                          spreadRadius: 15,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      "assets/images/wanda_logo.png",
                      height: 160,
                    ),
                  ),

                  const SizedBox(height: 30),

                  /// 🏷 TITRE WANDA
                  const Text(
                    "WANDA",
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// 🏷 SLOGAN
                  const Text(
                    "L'Œil Intelligent de la Cité",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      letterSpacing: 1.2,
                    ),
                  ),

                  const SizedBox(height: 40),

                  /// ⏳ BARRE DE CHARGEMENT
                  Container(
                    width: 200,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(seconds: 3),
                      width: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF94D358),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
