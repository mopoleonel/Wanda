import 'dart:io';

import '../../core/api/api_client.dart';
import '../../core/error/app_logger.dart';
import '../../core/error/error_mapper.dart';
import '../api/adaptateurs.dart';
import '../models/ajustement.dart';
import '../models/analyse_ia.dart';
import '../models/demande_menage.dart';
import '../pricing/tarification.dart';

/// Demandes de services ménagers : photos privées, analyse IA, prix et
/// création par le serveur, refus, ajustements, passages d'abonnement.
///
/// Le prix n'est jamais envoyé par l'app : le serveur le recalcule à la
/// création. Les photos sont privées ; l'app n'en reçoit que des liens de
/// courte durée.
class DemandeRepository {
  final ApiClient _api;
  DemandeRepository(this._api);

  /// Envoie une photo (déjà compressée) et renvoie son chemin, à joindre
  /// ensuite à la demande ou à l'ajustement.
  Future<String> envoyerPhoto(File photo, {required String dossier}) async {
    try {
      final d = await _api.envoyerFichiers('photos',
          champs: {'dossier': dossier}, fichiers: {'fichier': photo}) as Map;
      return d['chemin'] as String;
    } catch (e, st) {
      throw mapError('DemandeRepository.envoyerPhoto', e, st);
    }
  }

  /// Lien temporaire pour afficher une photo privée (si on y a droit).
  Future<String> urlPhoto(String chemin) async {
    try {
      final d = await _api.get('photos/lien', query: {'chemin': chemin}) as Map;
      return d['url'] as String;
    } catch (e, st) {
      throw mapError('DemandeRepository.urlPhoto', e, st);
    }
  }

  /// Analyse IA des photos. Ne lève jamais d'erreur : sans IA (réseau,
  /// quota, clé absente), renvoie null et le prix vient du questionnaire.
  Future<AnalyseIa?> analyser(DemandeMenage d, List<String> photos) async {
    try {
      final r = await _api.post('demandes/analyse', {
        'service': d.service.code,
        'reponses': d.reponses,
        'photos': photos,
      });
      if (r is! Map || r['resultat'] is! Map) return null;
      return AnalyseIa.fromMap((r['resultat'] as Map).cast<String, dynamic>(),
          id: r['analyse_id'] as String?);
    } catch (e, st) {
      AppLogger.error('DemandeRepository.analyser', e, st);
      return null;
    }
  }

  /// Prix calculé par le serveur : c'est lui qui sera enregistré.
  Future<EstimationPrix> prixServeur(DemandeMenage d) async {
    try {
      final r = await _api.post('prix', {
        'service': d.service.code,
        'formule': d.formule.code,
        'frequence': d.frequence?.code,
        'reponses': d.reponses,
        'produits': d.produitsFournis,
      });
      return EstimationPrix.fromServeur((r as Map).cast<String, dynamic>());
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
      final r = await _api.post('demandes', {
        'prestataire': prestataireId,
        'service': demande.service.code,
        'formule': demande.formule.code,
        'frequence': demande.frequence?.code,
        'reponses': demande.reponses,
        'produits': demande.produitsFournis,
        'photos': photos,
        if (analyseId != null) 'analyse': analyseId,
        'date_souhaitee': _jour(date),
        'creneau': creneau.code,
      }) as Map;
      return r['id'] as String;
    } catch (e, st) {
      throw mapError('DemandeRepository.creer', e, st);
    }
  }

  /// Le prestataire décline la demande (motif facultatif, montré au client).
  Future<void> refuser(String sollicitationId, {String? motif}) async {
    try {
      await _api.post('demandes/$sollicitationId/refuser', {
        'motif': (motif ?? '').trim(),
      });
    } catch (e, st) {
      throw mapError('DemandeRepository.refuser', e, st);
    }
  }

  /// Les ajustements et passages modifient la demande elle-même (date de
  /// modification, ajustement en attente, nombre de passages) : le suivi
  /// des demandes suffit à les voir arriver, aucun flux séparé.
  Stream<void> changementsSuivi(String table) => const Stream.empty();

  Future<List<Ajustement>> ajustements(List<String> sollicitationIds) async {
    if (sollicitationIds.isEmpty) return const [];
    try {
      final tous = <Ajustement>[];
      for (final id in sollicitationIds) {
        final d = await _api.get('demandes/$id/ajustements');
        tous.addAll([for (final a in liste(d)) Ajustement.fromMap(versAjustement(a))]);
      }
      return tous;
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
      await _api.post('demandes/$sollicitationId/ajustements', {
        'minutes': minutes,
        'produits': produits,
        'motif': motif,
        'photos': photos,
      });
    } catch (e, st) {
      throw mapError('DemandeRepository.demanderAjustement', e, st);
    }
  }

  Future<void> repondreAjustement(String ajustementId, {required bool accepte}) async {
    try {
      await _api.post('ajustements/$ajustementId/repondre', {'accepte': accepte});
    } catch (e, st) {
      throw mapError('DemandeRepository.repondreAjustement', e, st);
    }
  }

  /// Passages effectués d'un abonnement, du plus récent au plus ancien.
  Future<List<DateTime>> passages(String sollicitationId) async {
    try {
      final d = await _api.get('demandes/$sollicitationId/passages');
      return [
        for (final p in (d is List ? d : const []))
          if (DateTime.tryParse('$p') case final date?) date.toLocal(),
      ];
    } catch (e, st) {
      throw mapError('DemandeRepository.passages', e, st);
    }
  }

  Future<void> pointerPassage(String sollicitationId) async {
    try {
      await _api.post('demandes/$sollicitationId/passages');
    } catch (e, st) {
      throw mapError('DemandeRepository.pointerPassage', e, st);
    }
  }

  static String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Paramètres de prix fixés par WANDA (lecture seule).
class TarifRepository {
  final ApiClient _api;
  TarifRepository(this._api);

  /// Tarifs du serveur ; en cas d'échec, les valeurs de départ (l'estimation
  /// en direct reste possible, le prix final vient du serveur).
  Future<Tarifs> charger() async {
    try {
      return Tarifs.depuisLignes(lignesTarifs(await _api.get('tarifs')));
    } catch (e, st) {
      AppLogger.error('TarifRepository.charger', e, st);
      return Tarifs.defaut;
    }
  }
}
