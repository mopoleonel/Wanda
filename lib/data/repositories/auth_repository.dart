import '../../core/api/api_client.dart';
import '../../core/api/session.dart';
import '../../core/error/app_exception.dart';
import '../../core/error/error_mapper.dart';

/// Types de compte gérés par l'app (champ `type_compte` de l'API).
enum UserType { citoyen, particulier, entreprise }

UserType? userTypeFromString(String? value) {
  switch (value) {
    case 'citoyen':
      return UserType.citoyen;
    case 'particulier':
      return UserType.particulier;
    case 'entreprise':
      return UserType.entreprise;
    default:
      return null;
  }
}

/// Connexion par code WhatsApp (API WANDA) et type du compte connecté.
class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  GestionSession get _session => _api.session;

  String? get currentUserId => _session.courante?.userId;

  /// `true` si la session a été ouverte par un numéro vérifié (WhatsApp).
  bool get hasVerifiedPhone => (_session.courante?.telephone ?? '').isNotEmpty;

  /// Le dernier code vérifié a créé le compte (premier passage).
  bool dernierCompteNouveau = false;

  /// Envoie un code à usage unique sur WhatsApp ; inscription et connexion
  /// sont le même flux. [phone] au format E.164 (voir `normalizePhone`).
  Future<void> sendWhatsAppOtp(String phone) async {
    try {
      await _api.postPublic('auth/code', {'telephone': phone});
    } catch (e, st) {
      throw mapError('AuthRepository.sendWhatsAppOtp', e, st);
    }
  }

  /// Vérifie le code et ouvre la session ; renvoie l'id de l'utilisateur.
  /// [typeCompte] : type à donner au compte s'il vient d'être créé (le
  /// serveur refuse un numéro déjà lié à un autre type de compte).
  Future<String> verifyWhatsAppOtp({
    required String phone,
    required String code,
    String? typeCompte,
  }) async {
    try {
      final d = await _api.postPublic('auth/connexion', {
        'telephone': phone,
        'code': code.trim(),
        if (typeCompte != null) 'type_compte': typeCompte,
      }) as Map;
      final u = (d['utilisateur'] as Map).cast<String, dynamic>();
      final id = u['id'] as String?;
      if (id == null) throw const AppException('Code invalide ou expiré.');
      dernierCompteNouveau = d['nouveau'] == true;
      await _session.ouvrir(Session(
        acces: d['acces'] as String,
        rafraichissement: d['rafraichissement'] as String,
        userId: id,
        telephone: (u['telephone'] as String?) ?? phone,
        typeCompte: (u['type_compte'] as String?) ?? '',
      ));
      return id;
    } catch (e, st) {
      throw mapError('AuthRepository.verifyWhatsAppOtp', e, st);
    }
  }

  Future<void> signOut() async {
    try {
      await _session.fermer();
    } catch (e, st) {
      throw mapError('AuthRepository.signOut', e, st);
    }
  }

  /// Type du compte connecté, tel que le serveur le connaît.
  Future<UserType?> fetchUserType(String userId) async {
    try {
      final d = await _api.get('moi') as Map;
      final type = ((d['utilisateur'] as Map?)?['type_compte'] as String?) ?? '';
      await _session.majType(type);
      return userTypeFromString(type);
    } catch (e, st) {
      throw mapError('AuthRepository.fetchUserType', e, st);
    }
  }
}
