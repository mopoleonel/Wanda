import 'analyse_ia.dart';
import 'categorie_service.dart';
import 'demande_menage.dart';

class SollicitationExpert {
  final String nom;
  final String? prenom;
  final String? telephone;
  final List<String> services;
  final String? photoProUrl;

  const SollicitationExpert({
    required this.nom,
    this.prenom,
    this.telephone,
    this.services = const [],
    this.photoProUrl,
  });

  factory SollicitationExpert.fromMap(Map<String, dynamic> map) =>
      SollicitationExpert(
        nom: (map['nom'] as String?) ?? 'Prestataire',
        prenom: map['prenom'] as String?,
        telephone: map['telephone'] as String?,
        services: CategorieService.codesValides(
            (map['services'] as List?) ?? const []),
        photoProUrl: map['photo_pro_url'] as String?,
      );
}

/// Demande d'un client à un prestataire. Les anciennes demandes (avant les
/// services ménagers) n'ont ni service ni prix : [estDemandeMenage] est faux.
class Sollicitation {
  final String id;
  final String prestataireId;
  final String citoyenId;
  final String nomCitoyen;
  final String? prenomCitoyen;
  final String numeroCitoyen;
  final DateTime? dateSollicitation;
  final DateTime? dateFin;

  /// en_attente | accepte | refuse | termine | annule | archive
  final String statut;
  final SollicitationExpert? expert;

  // --- Demande de service ménager (calculée par le serveur) ---
  final CategorieService? service;
  final Formule formule;
  final Frequence? frequence;
  final Map<String, Object> reponses;
  final bool produitsFournis;
  final int? minutesEstimees;
  final int? prixPassage;
  final int? prixTotal;
  final List<String> photos;
  final AnalyseIa? analyseIa;
  final DateTime? dateSouhaitee;
  final Creneau? creneau;
  final String? motifRefus;

  const Sollicitation({
    required this.id,
    required this.prestataireId,
    required this.citoyenId,
    required this.nomCitoyen,
    this.prenomCitoyen,
    required this.numeroCitoyen,
    this.dateSollicitation,
    this.dateFin,
    required this.statut,
    this.expert,
    this.service,
    this.formule = Formule.ponctuelle,
    this.frequence,
    this.reponses = const {},
    this.produitsFournis = false,
    this.minutesEstimees,
    this.prixPassage,
    this.prixTotal,
    this.photos = const [],
    this.analyseIa,
    this.dateSouhaitee,
    this.creneau,
    this.motifRefus,
  });

  bool get estDemandeMenage => service != null;

  /// La demande telle que saisie, pour réafficher le questionnaire.
  DemandeMenage? get demande => service == null
      ? null
      : DemandeMenage(
          service: service!,
          formule: formule,
          frequence: frequence,
          reponses: reponses,
          produitsFournis: produitsFournis,
        );

  factory Sollicitation.fromMap(Map<String, dynamic> map) => Sollicitation(
        id: map['id'].toString(),
        prestataireId: map['prestataire_id'] as String,
        citoyenId: map['citoyen_id'] as String,
        nomCitoyen: (map['nom_citoyen'] as String?) ?? '',
        prenomCitoyen: map['prenom_citoyen'] as String?,
        numeroCitoyen: (map['numero_citoyen'] as String?) ?? '',
        dateSollicitation: _date(map['date_sollicitation']),
        dateFin: _date(map['date_fin']),
        statut: (map['statut'] as String?) ?? 'en_attente',
        expert: map['expert'] != null
            ? SollicitationExpert.fromMap(map['expert'] as Map<String, dynamic>)
            : null,
        service: CategorieService.fromCode(map['service'] as String?),
        formule: Formule.fromCode(map['formule'] as String?),
        frequence: Frequence.fromCode(map['frequence'] as String?),
        reponses: {
          for (final e in ((map['reponses'] as Map?) ?? const {}).entries)
            if (e.value != null) e.key.toString(): e.value as Object,
        },
        produitsFournis: (map['produits_fournis'] as bool?) ?? false,
        minutesEstimees: (map['minutes_estimees'] as num?)?.toInt(),
        prixPassage: (map['prix_passage'] as num?)?.toInt(),
        prixTotal: (map['prix_total'] as num?)?.toInt(),
        photos: [
          for (final p in (map['photos'] as List?) ?? const [])
            if (p is String) p,
        ],
        analyseIa: map['ia_analyse'] is Map
            ? AnalyseIa.fromMap(
                (map['ia_analyse'] as Map).cast<String, dynamic>())
            : null,
        dateSouhaitee: _date(map['date_souhaitee']),
        creneau: Creneau.fromCode(map['creneau'] as String?),
        motifRefus: map['motif_refus'] as String?,
      );

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}
