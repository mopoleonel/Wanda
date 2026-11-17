// Réponses de l'API WANDA (Django) -> cartes lues par les modèles de l'app.
//
// Les modèles gardent leurs noms de champs historiques (ceux des tables
// Supabase) ; seuls les noms qui diffèrent côté Django sont traduits ici.

Map<String, dynamic> _carte(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// Liste d'une réponse, paginée ({count, results}) ou non.
List<Map<String, dynamic>> liste(Object? reponse) {
  final brut = reponse is Map ? reponse['results'] : reponse;
  return [for (final e in (brut is List ? brut : const [])) _carte(e)];
}

/// Prestataire : profil personnel (GET moi/prestataire) ou fiche publique
/// (liste des prestataires, toujours en ligne).
Map<String, dynamic> versParticulier(Object? json) {
  final j = _carte(json);
  return {
    ...j,
    'photo_pro_url': j['photo_url'],
    'is_available': j['en_ligne'] ?? true,
    'abonnement_expire_at': j['abonnement_expire_le'],
  };
}

/// Demande : prestataire et client imbriqués côté Django.
Map<String, dynamic> versSollicitation(Object? json) {
  final j = _carte(json);
  final p = _carte(j['prestataire']);
  final c = _carte(j['client']);
  return {
    ...j,
    'prestataire_id': '${p['id'] ?? ''}',
    'citoyen_id': '${c['id'] ?? ''}',
    'nom_citoyen': c['nom'] ?? '',
    'prenom_citoyen': c['prenom'],
    'numero_citoyen': c['telephone'] ?? '',
    'expert': p.isEmpty
        ? null
        : {
            'nom': p['nom'],
            'prenom': p['prenom'],
            'telephone': p['telephone'],
            'services': p['services'],
            'photo_pro_url': p['photo_url'],
          },
    // Ancienne mission (avant les services ménagers) : pas de service.
    'service': (j['service'] as String?)?.isEmpty ?? true ? null : j['service'],
  };
}

Map<String, dynamic> versAjustement(Object? json) {
  final j = _carte(json);
  return {...j, 'sollicitation_id': j['demande'], 'created_at': j['cree_le']};
}

Map<String, dynamic> versSignalement(Object? json) {
  final j = _carte(json);
  return {...j, 'entreprise_id': j['entreprise'], 'created_at': j['cree_le']};
}

Map<String, dynamic> versVerification(Object? json) {
  final j = _carte(json);
  return {...j, 'created_at': j['cree_le']};
}

/// Tarifs {service: {cle: valeur}} -> lignes {service, cle, valeur}.
List<Map<String, dynamic>> lignesTarifs(Object? json) => [
      for (final s in _carte(json).entries)
        for (final c in _carte(s.value).entries)
          {'service': s.key, 'cle': c.key, 'valeur': c.value},
    ];
