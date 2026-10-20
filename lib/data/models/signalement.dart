class Signalement {
  final String id;
  final String typeProbleme;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final String? entrepriseId;
  final String? citoyenId;
  final String statut;
  final String? iaValidationDetails;
  final DateTime? createdAt;

  const Signalement({
    required this.id,
    required this.typeProbleme,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    this.entrepriseId,
    this.citoyenId,
    required this.statut,
    this.iaValidationDetails,
    this.createdAt,
  });

  factory Signalement.fromMap(Map<String, dynamic> map) => Signalement(
        id: map['id'].toString(),
        typeProbleme: (map['type_probleme'] as String?) ?? '',
        imageUrl: (map['image_url'] as String?) ?? '',
        latitude: double.tryParse(map['latitude'].toString()) ?? 0,
        longitude: double.tryParse(map['longitude'].toString()) ?? 0,
        entrepriseId: map['entreprise_id'] as String?,
        citoyenId: map['citoyen_id'] as String?,
        statut: (map['statut'] as String?) ?? 'en_attente',
        iaValidationDetails: map['ia_validation_details'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}
