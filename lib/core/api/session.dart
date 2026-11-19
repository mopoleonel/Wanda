import 'dart:async';
import 'dart:convert';

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
///
/// La session tient dans UNE clé (écriture d'un bloc, jamais à moitié). Les
/// sessions enregistrées par les versions 1.1.x (une clé par champ) sont
/// relues puis réécrites au nouveau format.
class StockageSessionSecurise implements StockageSession {
  static const _cle = 'wanda.session';
  static const _prefixeAncien = 'wanda.session.';

  /// `resetOnError: false` : par défaut, la bibliothèque EFFACE tout le
  /// stockage à la moindre erreur de déchiffrement ou d'accès au coffre de
  /// clés (même passagère, ex. téléphone verrouillé) ; l'utilisateur était
  /// alors déconnecté sans raison.
  static const _options = AndroidOptions(resetOnError: false);

  final FlutterSecureStorage _stockage;
  StockageSessionSecurise([FlutterSecureStorage? stockage])
      : _stockage = stockage ?? const FlutterSecureStorage(aOptions: _options);

  @override
  Future<Map<String, String>> lire() async {
    final tout = await _stockage.readAll();
    final bloc = tout[_cle];
    if (bloc != null) {
      final m = jsonDecode(bloc) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: '${e.value}'};
    }
    return {
      for (final e in tout.entries)
        if (e.key.startsWith(_prefixeAncien))
          e.key.substring(_prefixeAncien.length): e.value,
    };
  }

  @override
  Future<void> ecrire(Map<String, String> valeurs) async {
    await _stockage.write(key: _cle, value: jsonEncode(valeurs));
    await _effacerAncienFormat();
  }

  @override
  Future<void> effacer() async {
    await _stockage.delete(key: _cle);
    await _effacerAncienFormat();
  }

  Future<void> _effacerAncienFormat() async {
    final cles = (await _stockage.readAll())
        .keys
        .where((k) => k.startsWith(_prefixeAncien));
    for (final cle in cles) {
      await _stockage.delete(key: cle);
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

  /// Les écritures passent l'une après l'autre (renouvellement du jeton et
  /// mise à jour du type peuvent arriver en même temps).
  Future<void> _file = Future.value();
  Future<void> _enFile(Future<void> Function() action) {
    final suite = _file.then((_) => action());
    _file = suite.catchError((_) {});
    return suite;
  }

  Session? get courante => _courante;
  Stream<Session?> get changements => _changements.stream;

  /// Au démarrage : reprend la session du dernier lancement. Une lecture
  /// qui échoue (coffre de clés momentanément indisponible) est retentée ;
  /// si elle échoue encore, on démarre sans session mais SANS rien effacer :
  /// la session sera retrouvée au lancement suivant.
  Future<void> charger({
    int essais = 3,
    Duration pause = const Duration(milliseconds: 300),
  }) async {
    for (var i = 1; i <= essais; i++) {
      try {
        _courante = Session.depuisCarte(await _stockage.lire());
        return;
      } catch (_) {
        if (i < essais) await Future<void>.delayed(pause);
      }
    }
    _courante = null;
  }

  Future<void> ouvrir(Session s) async {
    _courante = s;
    _changements.add(s);
    await _enFile(() => _stockage.ecrire(s.versCarte()));
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

  /// Déconnexion volontaire (ou jeton refusé par le serveur) : seul cas où
  /// la session est effacée du téléphone.
  Future<void> fermer() async {
    _courante = null;
    _changements.add(null);
    await _enFile(_stockage.effacer);
  }
}
