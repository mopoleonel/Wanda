import 'categorie_service.dart';

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

class Sollicitation {
  final String id;
  final String prestataireId;
  final String citoyenId;
  final String nomCitoyen;
  final String? prenomCitoyen;
  final String numeroCitoyen;
  final DateTime? dateSollicitation;
  final DateTime? dateFin;
  final String statut;
  final SollicitationExpert? expert;

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
  });

  factory Sollicitation.fromMap(Map<String, dynamic> map) => Sollicitation(
        id: map['id'].toString(),
        prestataireId: map['prestataire_id'] as String,
        citoyenId: map['citoyen_id'] as String,
        nomCitoyen: (map['nom_citoyen'] as String?) ?? '',
        prenomCitoyen: map['prenom_citoyen'] as String?,
        numeroCitoyen: (map['numero_citoyen'] as String?) ?? '',
        dateSollicitation: map['date_sollicitation'] != null
            ? DateTime.tryParse(map['date_sollicitation'] as String)
            : null,
        dateFin: map['date_fin'] != null
            ? DateTime.tryParse(map['date_fin'] as String)
            : null,
        statut: (map['statut'] as String?) ?? 'en_attente',
        expert: map['expert'] != null
            ? SollicitationExpert.fromMap(map['expert'] as Map<String, dynamic>)
            : null,
      );
}
