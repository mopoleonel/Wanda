import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';
import '../../core/identity/cni_parser.dart';
import '../models/verification_identite.dart';

/// Dépôt et suivi de la vérification d'identité d'un artisan.
///
/// Les pièces (recto, verso, selfie) partent dans le bucket PRIVÉ
/// « identites », dans le dossier de l'artisan, avec des noms horodatés :
/// aucune URL publique n'est créée et un fichier déposé ne peut pas être
/// remplacé (voir supabase/sql/005).
class VerificationRepository {
  static const bucket = 'identites';
  final SupabaseClient _client;
  VerificationRepository(this._client);

  Future<VerificationIdentite?> latestFor(String userId) async {
    try {
      final row = await _client
          .from('prestataire_verifications')
          .select('id, statut, motif_rejet, created_at')
          .eq('prestataire_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : VerificationIdentite.fromMap(row);
    } catch (e, st) {
      throw mapError('VerificationRepository.latestFor', e, st);
    }
  }

  Future<String> _uploadPrivate(String userId, String name, File file) async {
    final path =
        '$userId/${DateTime.now().toUtc().millisecondsSinceEpoch}_$name.jpg';
    await _client.storage.from(bucket).upload(
          path,
          file,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  /// Envoie les pièces puis enregistre la demande de vérification.
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
    try {
      final rectoPath = await _uploadPrivate(userId, 'cni_recto', recto);
      final versoPath = await _uploadPrivate(userId, 'cni_verso', verso);
      final selfiePath = await _uploadPrivate(userId, 'selfie', selfie);

      String? iso(DateTime? d) => d?.toIso8601String().substring(0, 10);
      await _client.from('prestataire_verifications').insert({
        'prestataire_id': userId,
        'type_document': 'CNI_CM',
        'numero_document': mrz?.numeroDocument,
        'nom': nom,
        'prenoms': prenoms,
        'date_naissance': iso(mrz?.dateNaissance ?? front.dateNaissance),
        'lieu_naissance': front.lieuNaissance,
        'sexe': (mrz?.sexe.isNotEmpty ?? false) ? mrz!.sexe : front.sexe,
        'date_expiration': iso(mrz?.dateExpiration),
        'mrz_presente': mrz != null,
        'mrz_valide': mrz?.isValid ?? false,
        'saisie_corrigee': saisieCorrigee,
        'recto_path': rectoPath,
        'verso_path': versoPath,
        'selfie_path': selfiePath,
        'consentement_at': consentementAt.toUtc().toIso8601String(),
        'consentement_version': consentementVersion,
        'consentement_texte': consentementTexte,
      });
    } catch (e, st) {
      throw mapError('VerificationRepository.submit', e, st);
    }
  }
}
