import 'categorie_service.dart';

/// Formule d'une demande : une seule fois, ou en abonnement. À ne pas
/// confondre avec l'abonnement des prestataires à WANDA
/// (`Particulier.abonnementExpireAt`), qui est sans rapport.
enum Formule {
  ponctuelle('ponctuelle', 'Une fois'),
  abonnement('abonnement', 'Abonnement');

  const Formule(this.code, this.libelle);
  final String code;
  final String libelle;

  static Formule fromCode(String? c) =>
      c == abonnement.code ? abonnement : ponctuelle;
}

/// Rythme d'un abonnement.
enum Frequence {
  hebdomadaire('hebdomadaire', 'Chaque semaine'),
  mensuel('mensuel', 'Chaque mois');

  const Frequence(this.code, this.libelle);
  final String code;
  final String libelle;

  static Frequence? fromCode(String? c) => switch (c) {
        'hebdomadaire' => hebdomadaire,
        'mensuel' => mensuel,
        _ => null,
      };
}

/// Moment de la journée souhaité pour le passage.
enum Creneau {
  matin('matin', 'Matin'),
  apresMidi('apres_midi', 'Après-midi');

  const Creneau(this.code, this.libelle);
  final String code;
  final String libelle;

  static Creneau? fromCode(String? c) => switch (c) {
        'matin' => matin,
        'apres_midi' => apresMidi,
        _ => null,
      };
}

/// Un choix parmi une liste fixe (état du logement, type de nuisible…) :
/// [code] stocké dans les réponses, [libelle] affiché.
class Choix {
  final String code;
  final String libelle;
  final String? aide;
  const Choix(this.code, this.libelle, [this.aide]);
}

/// Clés des réponses au questionnaire, par service. Ce sont aussi les clés
/// lues par la fonction SQL `calculer_prix_demande` : ne pas les renommer.
abstract final class Q {
  // Ménage
  static const chambres = 'chambres';
  static const salons = 'salons';
  static const cuisines = 'cuisines';
  static const doucheWc = 'douche_wc';
  static const canapes = 'canapes';
  static const tapis = 'tapis';
  static const vitres = 'vitres';
  static const frigo = 'frigo';
  static const four = 'four';
  static const etat = 'etat';

  static const etats = [
    Choix('normal', 'Normal', 'Entretien courant'),
    Choix('sale', 'Sale', 'Pas nettoyé depuis un moment (+25 % de temps)'),
    Choix('tres_sale', 'Très sale',
        'Après travaux, déménagement, longue absence (+50 % de temps)'),
  ];

  // Linge
  static const paniers = 'paniers';
  static const drapsDelicats = 'draps_delicats';
  static const repassage = 'repassage';
  static const piecesRepassage = 'pieces_repassage';

  // Déchets
  static const sacs = 'sacs';
  static const passagesSemaine = 'passages_semaine';
  static const etage = 'etage';
  static const distanceBac = 'distance_bac';

  /// Distance jusqu'au bac, en mètres (valeur stockée = borne haute).
  static const distances = [
    Choix('10', 'Moins de 10 m'),
    Choix('50', '10 à 50 m'),
    Choix('100', '50 à 100 m'),
    Choix('200', 'Plus de 100 m'),
  ];

  // Nuisibles
  static const nuisible = 'nuisible';
  static const pieces = 'pieces';
  static const infestation = 'infestation';

  static const nuisibles = [
    Choix('cafards', 'Cafards'),
    Choix('moustiques', 'Moustiques'),
    Choix('punaises', 'Punaises de lit'),
    Choix('rongeurs', 'Rats et souris'),
    Choix('fourmis', 'Fourmis'),
  ];

  static const infestations = [
    Choix('faible', 'Faible', 'Quelques-uns, de temps en temps'),
    Choix('moyenne', 'Moyenne', 'Tous les jours, dans plusieurs pièces'),
    Choix('forte', 'Forte', 'Partout, même en journée'),
  ];
}

/// Une demande de service ménager en cours de saisie ou enregistrée.
class DemandeMenage {
  final CategorieService service;
  final Formule formule;
  final Frequence? frequence;

  /// Réponses au questionnaire (clés de [Q]) : entiers, booléens ou codes.
  final Map<String, Object> reponses;

  /// Le prestataire apporte ses produits (ménage, linge). Toujours vrai pour
  /// les nuisibles (produits professionnels).
  final bool produitsFournis;

  const DemandeMenage({
    required this.service,
    this.formule = Formule.ponctuelle,
    this.frequence,
    this.reponses = const {},
    this.produitsFournis = false,
  });

  /// Réponses de départ d'un service : ce qu'on voit au premier écran.
  factory DemandeMenage.initiale(CategorieService service) => DemandeMenage(
        service: service,
        produitsFournis: service == CategorieService.nuisibles,
        reponses: switch (service) {
          CategorieService.menage => {
              Q.chambres: 1,
              Q.salons: 1,
              Q.cuisines: 1,
              Q.doucheWc: 1,
              Q.canapes: 0,
              Q.tapis: 0,
              Q.vitres: false,
              Q.frigo: false,
              Q.four: false,
              Q.etat: 'normal',
            },
          CategorieService.linge => {
              Q.paniers: 1,
              Q.drapsDelicats: false,
              Q.repassage: false,
              Q.piecesRepassage: 0,
            },
          CategorieService.dechets => {
              Q.sacs: 2,
              Q.passagesSemaine: 1,
              Q.etage: 0,
              Q.distanceBac: '10',
            },
          CategorieService.nuisibles => {
              Q.nuisible: 'cafards',
              Q.pieces: 2,
              Q.infestation: 'moyenne',
            },
        },
      );

  // Lecture tolérante, comme `_rep_int` / `_rep_oui` en SQL : une valeur du
  // mauvais type compte pour 0 / non.
  int entier(String cle) {
    final v = reponses[cle];
    return v is num ? v.toInt() : 0;
  }

  bool oui(String cle) => reponses[cle] == true;

  String? code(String cle) => reponses[cle]?.toString();

  DemandeMenage avec(String cle, Object valeur) =>
      copyWith(reponses: {...reponses, cle: valeur});

  DemandeMenage copyWith({
    Formule? formule,
    Frequence? frequence,
    bool effacerFrequence = false,
    Map<String, Object>? reponses,
    bool? produitsFournis,
  }) =>
      DemandeMenage(
        service: service,
        formule: formule ?? this.formule,
        frequence: effacerFrequence ? null : (frequence ?? this.frequence),
        reponses: reponses ?? this.reponses,
        produitsFournis: service == CategorieService.nuisibles
            ? true
            : (produitsFournis ?? this.produitsFournis),
      );

  /// Les nuisibles se traitent toujours avec les produits du prestataire.
  bool get produitsModifiables => service != CategorieService.nuisibles;

  /// Une demande d'abonnement doit avoir un rythme.
  bool get formuleComplete =>
      formule == Formule.ponctuelle || frequence != null;

  /// « Une fois » / « Abonnement · chaque semaine ».
  String get libelleFormule => formule == Formule.ponctuelle
      ? formule.libelle
      : '${formule.libelle} · ${(frequence?.libelle ?? '').toLowerCase()}';

  /// Les réponses en phrases courtes, pour le récapitulatif du client et la
  /// fiche du prestataire (indépendant des tarifs).
  List<String> resumeReponses() {
    String n(int q, String un, String plusieurs) =>
        '$q ${q > 1 ? plusieurs : un}';
    String libelle(List<Choix> choix, String cle) =>
        choix.where((c) => c.code == code(cle)).firstOrNull?.libelle ?? '—';
    final lignes = <String>[];
    switch (service) {
      case CategorieService.menage:
        lignes.add([
          if (entier(Q.chambres) > 0)
            n(entier(Q.chambres), 'chambre', 'chambres'),
          if (entier(Q.salons) > 0) n(entier(Q.salons), 'salon', 'salons'),
          if (entier(Q.cuisines) > 0)
            n(entier(Q.cuisines), 'cuisine', 'cuisines'),
          if (entier(Q.doucheWc) > 0)
            n(entier(Q.doucheWc), 'douche / WC', 'douches / WC'),
        ].join(', '));
        if (entier(Q.canapes) > 0 || entier(Q.tapis) > 0) {
          lignes.add([
            if (entier(Q.canapes) > 0)
              n(entier(Q.canapes), 'canapé', 'canapés'),
            if (entier(Q.tapis) > 0) n(entier(Q.tapis), 'tapis', 'tapis'),
          ].join(', '));
        }
        final options = [
          if (oui(Q.vitres)) 'vitres',
          if (oui(Q.frigo)) 'intérieur du frigo',
          if (oui(Q.four)) 'intérieur du four',
        ];
        if (options.isNotEmpty) lignes.add('En plus : ${options.join(', ')}');
        lignes.add(
            'État du logement : ${libelle(Q.etats, Q.etat).toLowerCase()}');
      case CategorieService.linge:
        lignes.add(n(entier(Q.paniers) < 1 ? 1 : entier(Q.paniers), 'panier',
            'paniers'));
        if (oui(Q.drapsDelicats)) lignes.add('Draps ou vêtements délicats');
        if (oui(Q.repassage)) {
          lignes.add(
              'Repassage : ${n(entier(Q.piecesRepassage), 'pièce', 'pièces')}');
        }
      case CategorieService.dechets:
        final hebdo = formule == Formule.abonnement &&
            frequence == Frequence.hebdomadaire;
        lignes.add(hebdo
            ? '${n(entier(Q.sacs), 'sac', 'sacs')} par semaine, '
                '${n(entier(Q.passagesSemaine) < 1 ? 1 : entier(Q.passagesSemaine), 'passage', 'passages')} par semaine'
            : n(entier(Q.sacs), 'sac', 'sacs'));
        lignes.add(entier(Q.etage) == 0
            ? 'Rez-de-chaussée'
            : '${entier(Q.etage)}${entier(Q.etage) == 1 ? 'er' : 'e'} étage');
        lignes
            .add('Bac : ${libelle(Q.distances, Q.distanceBac).toLowerCase()}');
      case CategorieService.nuisibles:
        lignes.add(libelle(Q.nuisibles, Q.nuisible));
        lignes.add(
            n(entier(Q.pieces) < 1 ? 1 : entier(Q.pieces), 'pièce', 'pièces'));
        lignes.add(
            'Infestation : ${libelle(Q.infestations, Q.infestation).toLowerCase()}');
    }
    if (service != CategorieService.dechets) {
      lignes.add(produitsFournis
          ? 'Produits apportés par le prestataire'
          : 'Produits fournis par le client');
    }
    return lignes;
  }
}
