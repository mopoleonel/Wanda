import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wanda/screens/homepage.dart';
import 'package:wanda/screens/splash_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: 'https://nmffavjkfsoykzwtlqug.supabase.co',
    anonKey: 'sb_publishable_-Vb1dgw47RFaxOH7hSZY8g_ntulLvVw',
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData get _lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF389038),
        onPrimary: Colors.white,
        secondary: Color(0xFF94D358),
        error: Color(0xFFEF4444),
      ),
    );
  }

  ThemeData get _darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Color(0xFF2E2E2E),
        error: Color(0xFFEF4444),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WANDA',
      themeMode: ThemeMode.system,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: Builder(
        builder: (context) {
          return SplashScreen(
            onComplete: () {
              // REDIRECTION STRICTE VERS HOMEPAGE COMME À L'ORIGINE
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => HomePage(
                    onSelectRole: (role) {},
                    onPrestataireClick: () {},
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
