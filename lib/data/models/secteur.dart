/// Secteurs d'activité des entreprises et attribution des signalements.
///
/// Source unique de la correspondance « type de problème → secteur » :
/// utilisée à l'envoi d'un signalement (choix de l'entreprise) et par le
/// tableau de bord entreprise (missions de son secteur).
library;

/// Secteurs proposés à l'inscription d'une entreprise (valeur enregistrée
/// telle quelle dans `entreprises.secteur_activite`).
const secteursActivite = [
  secteurHydraulique,
  secteurElectricite,
  secteurVoirie,
  secteurEnvironnement,
  secteurSecurite,
];

const secteurHydraulique = "Hydraulique (Fuites d'eau, etc.)";
const secteurElectricite = 'Électricité (Pannes, Poteaux, etc.)';
const secteurVoirie = 'BTP / Voirie (Nids de poule, etc.)';
const secteurEnvironnement = 'Environnement (Déchets, etc.)';

/// Secteur par défaut : tout incident non reconnu y est envoyé plutôt que
/// de n'arriver chez personne.
const secteurSecurite = 'Sécurité Publique';

/// Types proposés dans l'écran de signalement, par secteur. Sert aussi à
/// retrouver les anciens signalements enregistrés sans entreprise.
const _typesConnus = <String, String>{
  "Fuite d'eau": secteurHydraulique,
  'Électricité': secteurElectricite,
  "Dépôt d'ordures": secteurEnvironnement,
  'BTP / Voirie': secteurVoirie,
  'Sécurité Publique': secteurSecurite,
  'Autre (IA)': secteurSecurite,
};

/// Mots-clés des types libres renvoyés par l'IA (« Nid de poule »,
/// « Câble arraché »…), cherchés sans accents ni majuscules, en début de
/// mot (« eau » ne doit pas reconnaître « réseau »).
const _motsCles = <String, List<String>>{
  secteurHydraulique: [
    'eau',
    'fuite',
    'canalisation',
    'inondation',
    'egout',
    'caniveau',
    'tuyau',
    'robinet',
    'borne fontaine',
    'assainissement',
  ],
  secteurElectricite: [
    'electri',
    'poteau',
    'cable',
    'fil',
    'panne',
    'lampadaire',
    'eclairage',
    'transformateur',
    'courant',
  ],
  secteurEnvironnement: [
    'ordure',
    'dechet',
    'poubelle',
    'detritus',
    'decharge',
    'plastique',
    'salete',
    'insalubr',
  ],
  secteurVoirie: [
    'route',
    'nid de poule',
    'nids de poule',
    'voirie',
    'chaussee',
    'trottoir',
    'pont',
    'goudron',
    'bitume',
    'effondr',
    'fissure',
    'chantier',
    'batiment',
  ],
};

String _sansAccents(String s) {
  const avec = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
  const sans = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = avec.indexOf(c);
    b.write(i < 0 ? c : sans[i]);
  }
  return b.toString();
}

/// Secteur chargé d'un type de problème. Types de l'écran reconnus tels
/// quels ; types libres classés par mots-clés ; sinon [secteurSecurite].
String secteurPourType(String typeProbleme) {
  final connu = _typesConnus[typeProbleme.trim()];
  if (connu != null) return connu;
  final t = _sansAccents(typeProbleme);
  for (final entry in _motsCles.entries) {
    if (entry.value.any((m) => RegExp(r'\b' + m).hasMatch(t))) {
      return entry.key;
    }
  }
  return secteurSecurite;
}

/// Types de l'écran de signalement rattachés à [secteur] (un secteur
/// inconnu n'a que lui-même comme type, comme avant).
List<String> typesDuSecteur(String secteur) {
  final types = [
    for (final e in _typesConnus.entries)
      if (e.value == secteur) e.key,
  ];
  return types.isEmpty ? [secteur] : types;
}
