/// Statut de la vérification d'identité d'un artisan
/// (table `prestataire_verifications`).
enum VerificationStatut { enAttente, valide, rejete }

VerificationStatut _statut(String? s) => switch (s) {
      'valide' => VerificationStatut.valide,
      'rejete' => VerificationStatut.rejete,
      _ => VerificationStatut.enAttente,
    };

/// Dernière vérification connue d'un artisan, telle que l'app a besoin de
/// la voir (les pièces elles-mêmes restent dans le stockage privé).
class VerificationIdentite {
  final String id;
  final VerificationStatut statut;
  final String? motifRejet;
  final DateTime? createdAt;

  const VerificationIdentite({
    required this.id,
    required this.statut,
    this.motifRejet,
    this.createdAt,
  });

  factory VerificationIdentite.fromMap(Map<String, dynamic> map) =>
      VerificationIdentite(
        id: map['id'].toString(),
        statut: _statut(map['statut'] as String?),
        motifRejet: map['motif_rejet'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );
}
