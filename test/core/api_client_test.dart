import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wanda/core/api/api_client.dart';
import 'package:wanda/core/api/session.dart';
import 'package:wanda/core/api/sondage.dart';
import 'package:wanda/data/api/adaptateurs.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/models/sollicitation.dart';

const _session = Session(
  acces: 'ancien',
  rafraichissement: 'r1',
  userId: 'u1',
  telephone: '+237690000002',
  typeCompte: 'citoyen',
);

http.Response _json(Object corps, [int statut = 200]) =>
    http.Response(jsonEncode(corps), statut,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('ApiClient', () {
    late GestionSession session;
    setUp(() async {
      session = GestionSession(StockageSessionMemoire());
      await session.ouvrir(_session);
    });

    test('jeton ajouté, réponse JSON décodée (accents compris)', () async {
      final api = ApiClient(
        baseUrl: 'https://api.test/api',
        session: session,
        client: MockClient((r) async {
          expect(r.url.toString(), 'https://api.test/api/tarifs');
          expect(r.headers['Authorization'], 'Bearer ancien');
          return _json({'libellé': 'Ménage'});
        }),
      );
      expect(await api.get('tarifs'), {'libellé': 'Ménage'});
    });

    test('jeton expiré : renouvelé une fois puis la requête est rejouée',
        () async {
      var appels = 0;
      final api = ApiClient(
        baseUrl: 'https://api.test/api/',
        session: session,
        client: MockClient((r) async {
          if (r.url.path.endsWith('auth/rafraichir')) {
            expect(jsonDecode(r.body), {'refresh': 'r1'});
            return _json({'access': 'nouveau', 'refresh': 'r2'});
          }
          appels++;
          return r.headers['Authorization'] == 'Bearer nouveau'
              ? _json({'ok': true})
              : _json({'code': 'NON_CONNECTE'}, 401);
        }),
      );
      expect(await api.get('moi'), {'ok': true});
      expect(appels, 2);
      expect(session.courante!.acces, 'nouveau');
      expect(session.courante!.rafraichissement, 'r2');
    });

    test('renouvellement refusé : session fermée, il faut se reconnecter',
        () async {
      final api = ApiClient(
        baseUrl: 'https://api.test/api/',
        session: session,
        client: MockClient((r) async => r.url.path.endsWith('auth/rafraichir')
            ? _json({'detail': 'expiré'}, 401)
            : _json({'code': 'NON_CONNECTE'}, 401)),
      );
      await expectLater(api.get('moi'), throwsA(isA<ApiException>()));
      expect(session.courante, isNull);
    });

    test('refus métier : code et message du serveur', () async {
      final api = ApiClient(
        baseUrl: 'https://api.test/api/',
        session: session,
        client: MockClient((r) async =>
            _json({'code': 'PRIX_PROTEGE', 'message': 'Prix protégé.'}, 400)),
      );
      try {
        await api.post('demandes', {'prix_total': 1});
        fail('aurait dû échouer');
      } on ApiException catch (e) {
        expect((e.code, e.statut, e.message),
            ('PRIX_PROTEGE', 400, 'Prix protégé.'));
      }
    });

    test('réponse non JSON (proxy en panne) : message lisible', () async {
      final api = ApiClient(
        baseUrl: 'https://api.test/api/',
        session: session,
        client: MockClient((r) async => http.Response('<html>502</html>', 502)),
      );
      await expectLater(
          api.get('moi'),
          throwsA(isA<ApiException>()
              .having((e) => e.message, 'message', contains('indisponible'))));
    });

    test('sans session : aucun en-tête de connexion', () async {
      await session.fermer();
      final api = ApiClient(
        baseUrl: 'https://api.test/api/',
        session: session,
        client: MockClient((r) async {
          expect(r.headers.containsKey('Authorization'), isFalse);
          return _json({'telephone': '+237690000002'});
        }),
      );
      await api.postPublic('auth/code', {'telephone': '690000002'});
    });
  });

  group('Session', () {
    test('gardée dans le stockage et relue au lancement suivant', () async {
      final stockage = StockageSessionMemoire();
      await GestionSession(stockage).ouvrir(_session);
      final relue = GestionSession(stockage);
      await relue.charger();
      expect(relue.courante!.userId, 'u1');
      await relue.fermer();
      expect(stockage.valeurs, isEmpty);
    });
  });

  group('Adaptateurs', () {
    test('demande Django -> Sollicitation', () {
      final s = Sollicitation.fromMap(versSollicitation({
        'id': 'd1',
        'statut': 'accepte',
        'service': 'menage',
        'formule': 'ponctuelle',
        'prix_total': 4500,
        'date_sollicitation': '2026-11-17T09:00:00Z',
        'photos': ['demandes/c1/x/1.jpg'],
        'prestataire': {
          'id': 'p1',
          'nom': 'Essai',
          'prenom': 'Testeur',
          'telephone': '+237690000001',
          'services': ['menage'],
          'photo_url': 'https://api/p.jpg',
        },
        'client': {
          'id': 'c1',
          'nom': 'Client',
          'prenom': '',
          'telephone': '+237690000002'
        },
      }));
      expect((s.prestataireId, s.citoyenId, s.numeroCitoyen),
          ('p1', 'c1', '+237690000002'));
      expect(s.expert!.prenom, 'Testeur');
      expect(s.prixTotal, 4500);
      expect(s.estDemandeMenage, isTrue);
    });

    test('ancienne mission sans service', () {
      final s = Sollicitation.fromMap(versSollicitation({
        'id': 'd2',
        'service': '',
        'prestataire': {'id': 'p1'},
        'client': {'id': 'c1'},
      }));
      expect(s.estDemandeMenage, isFalse);
    });

    test('prestataire Django -> Particulier', () {
      final p = Particulier.fromMap(versParticulier({
        'id': 'p1',
        'services': ['linge'],
        'photo_url': 'https://api/p.jpg',
        'en_ligne': false,
        'abonnement_expire_le': '2026-12-01T00:00:00Z',
      }));
      expect(p.photoProUrl, 'https://api/p.jpg');
      expect(p.isAvailable, isFalse);
      expect(p.abonnementExpireAt, isNotNull);
    });

    test('tarifs imbriqués -> lignes', () {
      expect(
          lignesTarifs({
            'global': {'deplacement': 1000}
          }),
          [
            {'service': 'global', 'cle': 'deplacement', 'valeur': 1000}
          ]);
    });
  });

  group('sonder', () {
    test("émet au départ puis seulement quand le contenu change", () async {
      var n = 0;
      final valeurs = [1, 1, 2];
      final recu = <int>[];
      final abonnement = sonder(() async => valeurs[n < 2 ? n++ : 2],
              intervalle: const Duration(milliseconds: 10))
          .listen(recu.add);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await abonnement.cancel();
      expect(recu, [1, 2]);
    });

    test('une panne réseau est signalée une fois, puis le suivi reprend',
        () async {
      var n = 0;
      final erreurs = <Object>[];
      final recu = <String>[];
      final abonnement = sonder<String>(() async {
        n++;
        if (n <= 3) throw TimeoutException('réseau');
        return 'ok';
      }, intervalle: const Duration(milliseconds: 10))
          .listen(recu.add, onError: erreurs.add);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await abonnement.cancel();
      expect(erreurs, hasLength(1));
      expect(recu, ['ok']);
    });
  });
}
