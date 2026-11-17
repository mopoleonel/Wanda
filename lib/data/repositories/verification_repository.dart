import 'dart:io';

import '../../core/api/api_client.dart';
import '../../core/error/error_mapper.dart';
import '../../core/identity/cni_parser.dart';
import '../api/adaptateurs.dart';
import '../models/verification_identite.dart';

/// Dépôt et suivi de la vérification d'identité d'un prestataire.
///
/// Les pièces (recto, verso, selfie) sont envoyées en une seule requête au
/// serveur, qui les range dans un espace privé : aucune adresse publique, et
/// une pièce déposée ne peut pas être remplacée.
class VerificationRepository {
  final ApiClient _api;
  VerificationRepository(this._api);

  Future<VerificationIdentite?> latestFor(String userId) async {
    try {
      final d = await _api.get('moi/certification');
      return d == null ? null : VerificationIdentite.fromMap(versVerification(d));
    } catch (e, st) {
      throw mapError('VerificationRepository.latestFor', e, st);
    }
  }

  Future<void> submit({
    required String userId,
    required File recto,
    required File verso,
    required File selfie,
    required String nom,
    required String prenoms,
    required bool saisieCorrigee,
    required CniFront front,
    required CniMrz? mrz,
    required DateTime consentementAt,
    required String consentementVersion,
    required String consentementTexte,
  }) async {
    String? iso(DateTime? d) => d?.toIso8601String().substring(0, 10);
    final sexe = (mrz?.sexe.isNotEmpty ?? false) ? mrz!.sexe : front.sexe;
    final champs = <String, String?>{
      'nom': nom,
      'prenoms': prenoms,
      'numero_document': mrz?.numeroDocument,
      'date_naissance': iso(mrz?.dateNaissance ?? front.dateNaissance),
      'lieu_naissance': front.lieuNaissance,
      'sexe': sexe == 'M' || sexe == 'F' ? sexe : null,
      'date_expiration': iso(mrz?.dateExpiration),
      'mrz_presente': '${mrz != null}',
      'mrz_valide': '${mrz?.isValid ?? false}',
      'saisie_corrigee': '$saisieCorrigee',
      'consentement': 'true',
      'consentement_version': consentementVersion,
      'consentement_texte': consentementTexte,
    };
    try {
      await _api.envoyerFichiers(
        'moi/certification',
        champs: {
          for (final e in champs.entries)
            if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
        },
        fichiers: {'recto': recto, 'verso': verso, 'selfie': selfie},
      );
    } catch (e, st) {
      throw mapError('VerificationRepository.submit', e, st);
    }
  }
}
