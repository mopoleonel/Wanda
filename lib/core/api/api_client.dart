import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../error/app_exception.dart';
import 'session.dart';

/// Adresse de l'API WANDA (back-end Django), fixée à la compilation :
///   flutter build apk --dart-define=API_URL=https://api.wanda.cm/api/
/// Par défaut, le serveur de développement du PC, joint depuis un téléphone
/// branché en USB avec « adb reverse tcp:8000 tcp:8000 ».
const apiUrlParDefaut = String.fromEnvironment('API_URL',
    defaultValue: 'http://127.0.0.1:8000/api/');

/// Refus de l'API : code stable (« PRIX_PROTEGE »…) et message en français,
/// prêt à afficher.
class ApiException extends AppException {
  final String code;
  final int statut;
  const ApiException(super.message,
      {required this.code, required this.statut, super.cause});
}

/// Appels à l'API WANDA : jeton de connexion ajouté, renouvelé une fois en
/// cas d'expiration, erreurs traduites en [ApiException].
class ApiClient {
  final Uri _base;
  final GestionSession session;
  final http.Client _http;

  /// Délai d'une requête ordinaire ; les envois de fichiers ont le double.
  final Duration delai;

  ApiClient({
    String baseUrl = apiUrlParDefaut,
    required this.session,
    http.Client? client,
    this.delai = const Duration(seconds: 20),
  })  : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = client ?? http.Client();

  Future<dynamic> get(String chemin, {Map<String, String>? query}) =>
      _envoyer('GET', chemin, query: query);

  Future<dynamic> post(String chemin, [Object? corps]) =>
      _envoyer('POST', chemin, corps: corps);

  Future<dynamic> patch(String chemin, Object corps) =>
      _envoyer('PATCH', chemin, corps: corps);

  Future<dynamic> put(String chemin, Object corps) =>
      _envoyer('PUT', chemin, corps: corps);

  Future<dynamic> delete(String chemin) => _envoyer('DELETE', chemin);

  /// Envoi multipart : champs texte et fichiers (photos).
  Future<dynamic> envoyerFichiers(
    String chemin, {
    Map<String, String> champs = const {},
    required Map<String, File> fichiers,
  }) =>
      _envoyer('POST', chemin, champs: champs, fichiers: fichiers);

  /// Requête sans jeton (envoi et vérification du code de connexion).
  Future<dynamic> postPublic(String chemin, Object corps) =>
      _envoyer('POST', chemin, corps: corps, authentifie: false);

  Uri _uri(String chemin, [Map<String, String>? query]) {
    final uri = _base.resolve(chemin.startsWith('/') ? chemin.substring(1) : chemin);
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  Future<http.BaseRequest> _requete(
    String methode,
    String chemin, {
    Map<String, String>? query,
    Object? corps,
    Map<String, String>? champs,
    Map<String, File>? fichiers,
    required bool authentifie,
  }) async {
    final uri = _uri(chemin, query);
    final http.BaseRequest r;
    if (fichiers != null) {
      final m = http.MultipartRequest(methode, uri)..fields.addAll(champs ?? const {});
      for (final e in fichiers.entries) {
        m.files.add(await http.MultipartFile.fromPath(e.key, e.value.path));
      }
      r = m;
    } else {
      final simple = http.Request(methode, uri);
      if (corps != null) {
        simple.headers['Content-Type'] = 'application/json; charset=utf-8';
        simple.body = jsonEncode(corps);
      }
      r = simple;
    }
    r.headers['Accept'] = 'application/json';
    final s = session.courante;
    if (authentifie && s != null) r.headers['Authorization'] = 'Bearer ${s.acces}';
    return r;
  }

  Future<dynamic> _envoyer(
    String methode,
    String chemin, {
    Map<String, String>? query,
    Object? corps,
    Map<String, String>? champs,
    Map<String, File>? fichiers,
    bool authentifie = true,
  }) async {
    Future<http.Response> une() async {
      final r = await _requete(methode, chemin,
          query: query,
          corps: corps,
          champs: champs,
          fichiers: fichiers,
          authentifie: authentifie);
      final envoi = _http.send(r).then(http.Response.fromStream);
      return envoi.timeout(fichiers == null ? delai : delai * 2);
    }

    var reponse = await une();
    // Jeton d'accès expiré : on le renouvelle une fois, puis on rejoue.
    if (reponse.statusCode == 401 && authentifie && session.courante != null) {
      if (await _renouveler()) reponse = await une();
    }
    return _lire(reponse);
  }

  Future<bool>? _renouvellement;

  /// Un seul renouvellement à la fois, même si plusieurs requêtes échouent
  /// ensemble.
  Future<bool> _renouveler() => _renouvellement ??= () async {
        try {
          final s = session.courante;
          if (s == null) return false;
          final r = await _http
              .post(_uri('auth/rafraichir'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'refresh': s.rafraichissement}))
              .timeout(delai);
          if (r.statusCode != 200) {
            // Session expirée ou révoquée : il faut se reconnecter.
            await session.fermer();
            return false;
          }
          final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          await session.majJetons(d['access'] as String, d['refresh'] as String?);
          return true;
        } finally {
          _renouvellement = null;
        }
      }();

  dynamic _lire(http.Response r) {
    final texte = utf8.decode(r.bodyBytes);
    dynamic corps;
    if (texte.isNotEmpty) {
      try {
        corps = jsonDecode(texte);
      } on FormatException {
        corps = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return corps;
    final code = corps is Map ? '${corps['code'] ?? ''}' : '';
    final message = corps is Map && corps['message'] is String
        ? corps['message'] as String
        : _messageParDefaut(r.statusCode);
    throw ApiException(message,
        code: code.isEmpty ? 'HTTP_${r.statusCode}' : code, statut: r.statusCode);
  }

  static String _messageParDefaut(int statut) => switch (statut) {
        401 => 'Votre session a expiré : reconnectez-vous.',
        403 => 'Action non autorisée.',
        404 => 'Élément introuvable.',
        429 => 'Trop de demandes : réessayez dans quelques minutes.',
        >= 500 => 'Le service est momentanément indisponible. Réessayez.',
        _ => 'La demande a été refusée.',
      };
}
