/// Demande d'ajustement du prix par le prestataire (aucun supplément sur
/// place) : le client l'accepte ou la refuse dans l'app.
class Ajustement {
  final String id;
  final String sollicitationId;
  final int minutesSupp;
  final int produitsSupp;
  final String motif;
  final List<String> photos;

  /// Calculé par le serveur au tarif horaire en vigueur.
  final int prixSupp;

  /// en_attente | accepte | refuse
  final String statut;
  final DateTime? createdAt;

  const Ajustement({
    required this.id,
    required this.sollicitationId,
    required this.minutesSupp,
    required this.produitsSupp,
    required this.motif,
    this.photos = const [],
    required this.prixSupp,
    required this.statut,
    this.createdAt,
  });

  bool get enAttente => statut == 'en_attente';

  factory Ajustement.fromMap(Map<String, dynamic> m) => Ajustement(
        id: m['id'].toString(),
        sollicitationId: m['sollicitation_id'].toString(),
        minutesSupp: (m['minutes_supp'] as num?)?.toInt() ?? 0,
        produitsSupp: (m['produits_supp'] as num?)?.toInt() ?? 0,
        motif: (m['motif'] as String?) ?? '',
        photos: [
          for (final p in (m['photos'] as List?) ?? const [])
            if (p is String) p,
        ],
        prixSupp: (m['prix_supp'] as num?)?.toInt() ?? 0,
        statut: (m['statut'] as String?) ?? 'en_attente',
        createdAt: m['created_at'] is String
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
      );
}
