import 'dart:io';

import '../../core/api/api_client.dart';
import '../../core/error/error_mapper.dart';
import '../api/adaptateurs.dart';
import '../models/signalement.dart';

/// Signalements citoyens (attribués par le serveur à l'entreprise du
/// secteur) et leur avancement côté entreprise.
class SignalementRepository {
  final ApiClient _api;
  SignalementRepository(this._api);

  /// Vérification de la photo par l'IA : {valid, detected_type, reason}.
  /// Sans IA disponible, `valid` est null et le signalement peut partir.
  Future<Map<String, dynamic>> analyser(String categorie, File image) async {
    try {
      final d = await _api.envoyerFichiers('signalements/analyse',
          champs: {'categorie': categorie}, fichiers: {'image': image});
      return (d as Map).cast<String, dynamic>();
    } catch (e, st) {
      throw mapError('SignalementRepository.analyser', e, st);
    }
  }

  /// Envoie la photo et le signalement ; le serveur choisit l'entreprise du
  /// secteur.
  Future<void> create({
    required String typeProbleme,
    required File image,
    required double latitude,
    required double longitude,
    String? iaValidationDetails,
  }) async {
    try {
      await _api.envoyerFichiers('signalements', champs: {
        'type_probleme': typeProbleme,
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
        if (iaValidationDetails != null && iaValidationDetails.isNotEmpty)
          'ia_validation_details': iaValidationDetails.length > 500
              ? iaValidationDetails.substring(0, 500)
              : iaValidationDetails,
      }, fichiers: {
        'image': image
      });
    } catch (e, st) {
      throw mapError('SignalementRepository.create', e, st);
    }
  }

  /// Missions de l'entreprise connectée : attribuées, ou de son secteur sans
  /// entreprise (le serveur fait le tri).
  Future<List<Signalement>> fetchForEntreprise(
    String entrepriseId,
    List<String> types, {
    int pageSize = 100,
  }) async {
    try {
      final d = await _api.get('signalements');
      return [for (final s in liste(d)) Signalement.fromMap(versSignalement(s))];
    } catch (e, st) {
      throw mapError('SignalementRepository.fetchForEntreprise', e, st);
    }
  }

  /// Avancement d'une mission : en_cours, resolu ou rejete.
  Future<void> updateStatut(String id, String statut) async {
    try {
      await _api.post('signalements/$id/statut', {'statut': statut});
    } catch (e, st) {
      throw mapError('SignalementRepository.updateStatut', e, st);
    }
  }
}
