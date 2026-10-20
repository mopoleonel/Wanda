/// Chemins nommés centralisés — remplace les `Navigator.push(MaterialPageRoute(...))`
/// dispersés dans chaque écran et les callbacks morts qui les accompagnaient
/// (`onSelectRole: (role) {}`, `onPrestataireClick: () {}`).
class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const home = '/home';

  static const citoyenLogin = '/citoyen/login';
  static const citoyenServices = '/citoyen/services';
  static const citoyenSignal = '/citoyen/signal';

  /// Réserver un service ménager (`extra` : DemandeArgs).
  static const citoyenDemande = '/citoyen/demande';

  static const prestaLogin = '/presta/login';

  /// Certification facultative du compte artisan (badge de confiance).
  static const identityVerification = '/presta/certification';
  static const dashboardParticulier = '/presta/particulier';
  static const dashboardEntreprise = '/presta/entreprise';
}
