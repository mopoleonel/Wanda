import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session ouverte par le code WhatsApp : jetons de l'API WANDA et identité
/// du compte.
class Session {
  final String acces;
  final String rafraichissement;
  final String userId;
  final String telephone;

  /// citoyen | particulier | entreprise ; vide tant que le type n'est pas
  /// choisi (premier code dans l'espace prestataire).
  final String typeCompte;

  const Session({
    required this.acces,
    required this.rafraichissement,
    required this.userId,
    required this.telephone,
    required this.typeCompte,
  });

  Session copyWith(
          {String? acces, String? rafraichissement, String? typeCompte}) =>
      Session(
        acces: acces ?? this.acces,
        rafraichissement: rafraichissement ?? this.rafraichissement,
        userId: userId,
        telephone: telephone,
        typeCompte: typeCompte ?? this.typeCompte,
      );

  Map<String, String> versCarte() => {
        'acces': acces,
        'rafraichissement': rafraichissement,
        'user_id': userId,
        'telephone': telephone,
        'type_compte': typeCompte,
      };

  static Session? depuisCarte(Map<String, String> m) {
    final acces = m['acces'], rafr = m['rafraichissement'], id = m['user_id'];
    if (acces == null || rafr == null || id == null) return null;
    return Session(
      acces: acces,
      rafraichissement: rafr,
      userId: id,
      telephone: m['telephone'] ?? '',
      typeCompte: m['type_compte'] ?? '',
    );
  }
}

/// Où la session est gardée entre deux lancements de l'app.
abstract class StockageSession {
  Future<Map<String, String>> lire();
  Future<void> ecrire(Map<String, String> valeurs);
  Future<void> effacer();
}

/// Stockage chiffré du téléphone (Keystore Android, trousseau iOS) : les
/// jetons ne sont jamais écrits en clair.
class StockageSessionSecurise implements StockageSession {
  static const _prefixe = 'wanda.session.';
  final FlutterSecureStorage _stockage;
  StockageSessionSecurise([FlutterSecureStorage? stockage])
      : _stockage = stockage ?? const FlutterSecureStorage();

  @override
  Future<Map<String, String>> lire() async {
    final tout = await _stockage.readAll();
    return {
      for (final e in tout.entries)
        if (e.key.startsWith(_prefixe))
          e.key.substring(_prefixe.length): e.value,
    };
  }

  @override
  Future<void> ecrire(Map<String, String> valeurs) async {
    for (final e in valeurs.entries) {
      await _stockage.write(key: _prefixe + e.key, value: e.value);
    }
  }

  @override
  Future<void> effacer() async {
    for (final cle in (await lire()).keys) {
      await _stockage.delete(key: _prefixe + cle);
    }
  }
}

/// Stockage en mémoire (tests).
class StockageSessionMemoire implements StockageSession {
  final Map<String, String> valeurs = {};

  @override
  Future<Map<String, String>> lire() async => Map.of(valeurs);

  @override
  Future<void> ecrire(Map<String, String> v) async => valeurs.addAll(v);

  @override
  Future<void> effacer() async => valeurs.clear();
}

/// Session courante, gardée en mémoire et dans le stockage chiffré.
class GestionSession {
  final StockageSession _stockage;
  GestionSession(this._stockage);

  Session? _courante;
  final _changements = StreamController<Session?>.broadcast();

  Session? get courante => _courante;
  Stream<Session?> get changements => _changements.stream;

  /// Au démarrage : reprend la session du dernier lancement. Un stockage
  /// illisible (restauration de sauvegarde, clé perdue) vaut déconnexion.
  Future<void> charger() async {
    try {
      _courante = Session.depuisCarte(await _stockage.lire());
    } catch (_) {
      _courante = null;
      await _stockage.effacer().catchError((_) {});
    }
  }

  Future<void> ouvrir(Session s) async {
    _courante = s;
    await _stockage.ecrire(s.versCarte());
    _changements.add(s);
  }

  Future<void> majJetons(String acces, String? rafraichissement) async {
    final s = _courante;
    if (s == null) return;
    await ouvrir(s.copyWith(acces: acces, rafraichissement: rafraichissement));
  }

  Future<void> majType(String typeCompte) async {
    final s = _courante;
    if (s == null) return;
    await ouvrir(s.copyWith(typeCompte: typeCompte));
  }

  Future<void> fermer() async {
    _courante = null;
    await _stockage.effacer();
    _changements.add(null);
  }
}
