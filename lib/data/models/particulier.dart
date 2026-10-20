class Particulier {
  final String id;
  final String nom;
  final String prenom;
  final String telephone;
  final String servicePropose;
  final String? photoProUrl;
  final bool isAvailable;
  final double? latitude;
  final double? longitude;
  final DateTime? abonnementExpireAt;
  final String? typeAbonnement;
  final bool essaiUtilise;

  /// Badge de confiance : identité certifiée par WANDA (CNI + selfie).
  final bool identiteVerifiee;

  const Particulier({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.servicePropose,
    this.photoProUrl,
    this.isAvailable = false,
    this.latitude,
    this.longitude,
    this.abonnementExpireAt,
    this.typeAbonnement,
    this.essaiUtilise = false,
    this.identiteVerifiee = false,
  });

  factory Particulier.fromMap(Map<String, dynamic> map) => Particulier(
        id: map['id'] as String,
        nom: (map['nom'] as String?) ?? '',
        prenom: (map['prenom'] as String?) ?? '',
        telephone: (map['telephone'] as String?) ?? '',
        servicePropose: (map['service_propose'] as String?) ?? '',
        photoProUrl: map['photo_pro_url'] as String?,
        isAvailable: (map['is_available'] as bool?) ?? false,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        abonnementExpireAt: map['abonnement_expire_at'] != null
            ? DateTime.tryParse(map['abonnement_expire_at'] as String)
            : null,
        typeAbonnement: map['type_abonnement'] as String?,
        essaiUtilise: (map['essai_utilise'] as bool?) ?? false,
        identiteVerifiee: (map['identite_verifiee'] as bool?) ?? false,
      );

  /// Éléments du profil encore manquants (vide = profil complet). La
  /// certification d'identité n'est ouverte qu'à un profil complet ; même
  /// règle côté base (trigger `exiger_profil_complet`).
  List<String> get profilManquant => [
        if ((photoProUrl ?? '').trim().isEmpty) 'photo professionnelle',
        if (nom.trim().isEmpty) 'nom',
        if (prenom.trim().isEmpty) 'prénom',
        if (servicePropose.trim().isEmpty) 'métier',
      ];

  static const int profilElements = 4;

  /// Le minimum pour être visible des citoyens (passer « en ligne ») :
  /// une fiche sans nom ni métier ne peut pas être proposée.
  List<String> get infosVisibiliteManquantes => [
        if (nom.trim().isEmpty) 'nom',
        if (prenom.trim().isEmpty) 'prénom',
        if (servicePropose.trim().isEmpty) 'métier',
      ];

  bool get profilComplet => profilManquant.isEmpty;

  /// Informations figées dès qu'une certification est en cours ou obtenue :
  /// elles doivent rester celles de la pièce vérifiée. Même règle côté base
  /// (trigger `figer_identite_certifiee`). La photo reste modifiable.
  static const champsFiges = ['nom', 'prénom', 'métier', 'téléphone'];

  /// Vrai si [champsFiges] ne peuvent plus être modifiés par l'artisan.
  bool identiteFigee({bool verificationEnCours = false}) =>
      identiteVerifiee || verificationEnCours;

  /// Jours d'abonnement restants, arrondis au jour supérieur : un essai de
  /// 14 jours activé à l'instant affiche bien « 14 jours ».
  int joursRestants([DateTime? now]) {
    final end = abonnementExpireAt;
    if (end == null) return 0;
    final minutes = end.difference(now ?? DateTime.now()).inMinutes;
    return minutes <= 0 ? 0 : (minutes / (24 * 60)).ceil();
  }

  bool get hasValidSubscription =>
      abonnementExpireAt != null &&
      DateTime.now().isBefore(abonnementExpireAt!);
}
