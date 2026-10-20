class Entreprise {
  final String id;
  final String nomEntreprise;
  final String secteurActivite;
  final String telephone;
  final String? logoUrl;

  const Entreprise({
    required this.id,
    required this.nomEntreprise,
    required this.secteurActivite,
    required this.telephone,
    this.logoUrl,
  });

  factory Entreprise.fromMap(Map<String, dynamic> map) => Entreprise(
        id: map['id'] as String,
        nomEntreprise: (map['nom_entreprise'] as String?) ?? '',
        secteurActivite: (map['secteur_activite'] as String?) ?? '',
        telephone: (map['telephone'] as String?) ?? '',
        logoUrl: map['logo_url'] as String?,
      );
}
