import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_exception.dart';
import '../../core/error/app_logger.dart';
import '../../core/error/error_mapper.dart';
import '../models/ajustement.dart';
import '../models/analyse_ia.dart';
import '../models/demande_menage.dart';
import '../pricing/tarification.dart';

/// Demandes de services ménagers : photos privées, analyse IA, prix et
/// création côté serveur, refus, ajustements, passages d'abonnement.
///
/// Le prix n'est jamais envoyé par l'app : `creer_demande` le recalcule
/// (supabase/sql/011). Les photos vont dans le bucket privé « demandes »,
/// dans le dossier de leur auteur.
class DemandeRepository {
  final SupabaseClient _client;
  DemandeRepository(this._client);

  static const bucket = 'demandes';

  String? get _uid => _client.auth.currentUser?.id;

  /// Dépose une photo (déjà compressée) et renvoie son chemin.
  Future<String> envoyerPhoto(File photo, {required String dossier}) async {
    final uid = _uid;
    if (uid == null) {
      throw const AppException('Connectez-vous pour joindre une photo.');
    }
    final chemin = '$uid/$dossier/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await _client.storage.from(bucket).upload(chemin, photo,
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
      return chemin;
    } catch (e, st) {
      throw mapError('DemandeRepository.envoyerPhoto', e, st);
    }
  }

  /// URL temporaire pour afficher une photo privée (10 minutes).
  Future<String> urlPhoto(String chemin) async {
    try {
      return await _client.storage.from(bucket).createSignedUrl(chemin, 600);
    } catch (e, st) {
      throw mapError('DemandeRepository.urlPhoto', e, st);
    }
  }

  /// Analyse IA des photos. Ne lève jamais d'erreur : en cas d'échec
  /// (réseau, quota, IA indisponible), renvoie null et la demande continue
  /// sur le questionnaire seul.
  Future<AnalyseIa?> analyser(DemandeMenage d, List<String> photos) async {
    try {
      final res = await _client.functions.invoke(
        'analyze-demande-menage',
        body: {
          'service': d.service.code,
          'reponses': d.reponses,
          'photos': photos,
        },
      ).timeout(const Duration(seconds: 35));
      final data = res.data;
      if (data is! Map || data['resultat'] is! Map) return null;
      return AnalyseIa.fromMap(
          (data['resultat'] as Map).cast<String, dynamic>(),
          id: data['analyse_id'] as String?);
    } catch (e, st) {
      AppLogger.error('DemandeRepository.analyser', e, st);
      return null;
    }
  }

  /// Prix calculé par le serveur (fonction SQL calculer_prix_demande).
  Future<EstimationPrix> prixServeur(DemandeMenage d) async {
    try {
      final res = await _client.rpc('calculer_prix_demande', params: {
        'p_service': d.service.code,
        'p_formule': d.formule.code,
        'p_frequence': d.frequence?.code,
        'p_reponses': d.reponses,
        'p_produits': d.produitsFournis,
      }).timeout(const Duration(seconds: 15));
      return EstimationPrix.fromServeur((res as Map).cast<String, dynamic>());
    } catch (e, st) {
      throw mapError('DemandeRepository.prixServeur', e, st);
    }
  }

  /// Crée la demande au prix du serveur ; renvoie son identifiant.
  Future<String> creer({
    required String prestataireId,
    required DemandeMenage demande,
    required List<String> photos,
    String? analyseId,
    required DateTime date,
    required Creneau creneau,
  }) async {
    try {
      final id = await _client.rpc('creer_demande', params: {
        'p_prestataire': prestataireId,
        'p_service': demande.service.code,
        'p_formule': demande.formule.code,
        'p_frequence': demande.frequence?.code,
        'p_reponses': demande.reponses,
        'p_produits': demande.produitsFournis,
        'p_photos': photos,
        'p_analyse': analyseId,
        'p_date': _jour(date),
        'p_creneau': creneau.code,
      }).timeout(const Duration(seconds: 20));
      return id as String;
    } catch (e, st) {
      throw mapError('DemandeRepository.creer', e, st);
    }
  }

  /// Le prestataire décline la demande (motif facultatif, montré au client).
  Future<void> refuser(String sollicitationId, {String? motif}) async {
    try {
      await _client.from('sollicitations').update({
        'statut': 'refuse',
        if (motif != null && motif.trim().isNotEmpty)
          'motif_refus': motif.trim(),
      }).eq('id', sollicitationId);
    } catch (e, st) {
      throw mapError('DemandeRepository.refuser', e, st);
    }
  }

  /// Signal temps réel (migration 015) : un ajustement ou un passage a été
  /// ajouté ou modifié. Les règles RLS limitent aux lignes de l'utilisateur ;
  /// l'écran relit ensuite le détail avec [ajustements] et [passages].
  Stream<void> changementsSuivi(String table) {
    assert(table == 'ajustements' || table == 'passages');
    return _client.from(table).stream(primaryKey: ['id']).map((_) {});
  }

  Future<List<Ajustement>> ajustements(List<String> sollicitationIds) async {
    if (sollicitationIds.isEmpty) return const [];
    try {
      final rows = await _client
          .from('ajustements')
          .select()
          .inFilter('sollicitation_id', sollicitationIds)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          Ajustement.fromMap(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e, st) {
      throw mapError('DemandeRepository.ajustements', e, st);
    }
  }

  Future<void> demanderAjustement({
    required String sollicitationId,
    required int minutes,
    required int produits,
    required String motif,
    List<String> photos = const [],
  }) async {
    try {
      await _client.rpc('demander_ajustement', params: {
        'p_sollicitation': sollicitationId,
        'p_minutes': minutes,
        'p_produits': produits,
        'p_motif': motif,
        'p_photos': photos,
      });
    } catch (e, st) {
      throw mapError('DemandeRepository.demanderAjustement', e, st);
    }
  }

  Future<void> repondreAjustement(String ajustementId,
      {required bool accepte}) async {
    try {
      await _client.rpc('repondre_ajustement',
          params: {'p_ajustement': ajustementId, 'p_accepte': accepte});
    } catch (e, st) {
      throw mapError('DemandeRepository.repondreAjustement', e, st);
    }
  }

  /// Passages effectués d'un abonnement, du plus récent au plus ancien.
  Future<List<DateTime>> passages(String sollicitationId) async {
    try {
      final rows = await _client
          .from('passages')
          .select('effectue_le')
          .eq('sollicitation_id', sollicitationId)
          .order('effectue_le', ascending: false);
      return [
        for (final r in rows as List)
          if (DateTime.tryParse('${(r as Map)['effectue_le']}') case final d?)
            d,
      ];
    } catch (e, st) {
      throw mapError('DemandeRepository.passages', e, st);
    }
  }

  Future<void> pointerPassage(String sollicitationId) async {
    try {
      await _client
          .rpc('pointer_passage', params: {'p_sollicitation': sollicitationId});
    } catch (e, st) {
      throw mapError('DemandeRepository.pointerPassage', e, st);
    }
  }

  static String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Paramètres de tarification (table `tarifs`, lecture seule).
class TarifRepository {
  final SupabaseClient _client;
  TarifRepository(this._client);

  /// Tarifs en base ; en cas d'échec, les valeurs de départ (l'estimation en
  /// direct reste possible, le prix final vient de toute façon du serveur).
  Future<Tarifs> charger() async {
    try {
      final rows = await _client
          .from('tarifs')
          .select('service, cle, valeur')
          .timeout(const Duration(seconds: 10));
      return Tarifs.depuisLignes(
          [for (final r in rows as List) Map<String, dynamic>.from(r as Map)]);
    } catch (e, st) {
      AppLogger.error('TarifRepository.charger', e, st);
      return Tarifs.defaut;
    }
  }
}
