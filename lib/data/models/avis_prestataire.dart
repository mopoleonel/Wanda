class AvisPrestataire {
  final String id;
  final String sollicitationId;
  final String prestataireId;
  final String citoyenId;
  final int note;
  final String? commentaire;

  const AvisPrestataire({
    required this.id,
    required this.sollicitationId,
    required this.prestataireId,
    required this.citoyenId,
    required this.note,
    this.commentaire,
  });

  factory AvisPrestataire.fromMap(Map<String, dynamic> map) => AvisPrestataire(
        id: map['id'].toString(),
        sollicitationId: map['sollicitation_id'].toString(),
        prestataireId: map['prestataire_id'] as String,
        citoyenId: map['citoyen_id'] as String,
        note: (map['note'] as num).toInt(),
        commentaire: map['commentaire'] as String?,
      );
}

/// Note moyenne agrégée d'un prestataire — remplace le "5.0" en dur qui
/// était affiché partout dans l'app avant cette refonte.
class RatingSummary {
  final double average;
  final int count;

  const RatingSummary({required this.average, required this.count});

  static const empty = RatingSummary(average: 0, count: 0);
}
