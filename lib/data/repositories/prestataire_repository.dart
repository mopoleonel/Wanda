import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';
import '../models/particulier.dart';

/// Liste temps réel des prestataires indépendants ("particuliers") et
/// gestion de leur disponibilité/position.
class PrestataireRepository {
  final SupabaseClient _client;
  PrestataireRepository(this._client);

  /// Flux temps réel des prestataires actuellement disponibles. Le filtrage
  /// par catégorie se fait côté client (peu de lignes, pas besoin d'un
  /// aller-retour serveur supplémentaire par changement de filtre).
  Stream<List<Particulier>> streamAvailable() {
    return _client
        .from('particuliers')
        .stream(primaryKey: ['id'])
        .eq('is_available', true)
        .limit(200)
        .map((rows) => rows.map(Particulier.fromMap).toList());
  }

  /// Prestataires en ligne qui proposent [serviceCode] (choix du
  /// prestataire au moment de réserver).
  Future<List<Particulier>> disponiblesPour(String serviceCode) async {
    try {
      final rows = await _client
          .from('particuliers')
          .select()
          .eq('is_available', true)
          .contains('services', [serviceCode])
          .limit(100)
          .timeout(const Duration(seconds: 10));
      return [
        for (final r in rows as List)
          Particulier.fromMap(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e, st) {
      throw mapError('PrestataireRepository.disponiblesPour', e, st);
    }
  }

  Future<Particulier?> getById(String id) async {
    try {
      final data = await _client
          .from('particuliers')
          .select()
          .eq('id', id)
          .maybeSingle();
      return data == null ? null : Particulier.fromMap(data);
    } catch (e, st) {
      throw mapError('PrestataireRepository.getById', e, st);
    }
  }

  /// Passe le prestataire disponible/indisponible. Quand il se déclare
  /// disponible, on capture sa position pour permettre le tri par proximité
  /// côté citoyen.
  Future<void> setAvailability(
    String id,
    bool isAvailable, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final update = <String, dynamic>{'is_available': isAvailable};
      if (isAvailable && latitude != null && longitude != null) {
        update['latitude'] = latitude;
        update['longitude'] = longitude;
      }
      await _client.from('particuliers').update(update).eq('id', id);
    } catch (e, st) {
      throw mapError('PrestataireRepository.setAvailability', e, st);
    }
  }
}
