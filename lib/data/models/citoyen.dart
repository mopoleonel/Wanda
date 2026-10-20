class Citoyen {
  final String citoyenId;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String? photoUrl;

  const Citoyen({
    required this.citoyenId,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    this.photoUrl,
  });

  factory Citoyen.fromMap(Map<String, dynamic> map) => Citoyen(
        citoyenId: map['citoyen_id'] as String,
        nom: (map['nom'] as String?) ?? '',
        prenom: (map['prenom'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        telephone: (map['telephone'] as String?) ?? '',
        photoUrl: map['photo_url'] as String?,
      );

  Map<String, dynamic> toUpdateMap() => {
        'nom': nom,
        'prenom': prenom,
        'telephone': telephone,
        // Vide → null : la colonne peut porter une contrainte d'unicité.
        'email': email.trim().isEmpty ? null : email.trim(),
      };
}
