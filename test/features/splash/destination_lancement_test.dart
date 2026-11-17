import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/api/session.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/features/splash/splash_screen.dart';

Session _compte(String type) => Session(
    acces: 'a',
    rafraichissement: 'r',
    userId: 'u',
    telephone: '+237690000002',
    typeCompte: type);

void main() {
  test("compte resté connecté : l'app s'ouvre directement sur son espace", () {
    expect(
        destinationAuLancement(_compte('citoyen')), AppRoutes.citoyenServices);
    expect(destinationAuLancement(_compte('particulier')),
        AppRoutes.dashboardParticulier);
    expect(destinationAuLancement(_compte('entreprise')),
        AppRoutes.dashboardEntreprise);
  });

  test("pas connecté, ou inscription prestataire pas finie : l'accueil", () {
    expect(destinationAuLancement(null), AppRoutes.home);
    expect(destinationAuLancement(_compte('')), AppRoutes.home);
  });

  test('la session est relue après fermeture de l\'app', () async {
    final stockage = StockageSessionMemoire();
    await GestionSession(stockage).ouvrir(_compte('particulier'));
    final relance = GestionSession(stockage);
    await relance.charger();
    expect(destinationAuLancement(relance.courante),
        AppRoutes.dashboardParticulier);
  });
}
