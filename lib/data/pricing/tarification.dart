// Calcul du prix d'une demande de service ménager.
//
// Le prix est FIXÉ PAR WANDA : temps estimé × tarif horaire + déplacement +
// produits. Ce fichier est le MIROIR EXACT du
// calcul du serveur (backend/tarification/calcul.py) : l'app s'en sert pour
// afficher le prix en direct pendant le questionnaire, mais le prix
// enregistré est toujours recalculé par le serveur. Toute modification ici
// doit être reportée là-bas (les deux partagent les mêmes cas de test).
//
// Arithmétique entière uniquement, pour que Dart et SQL tombent juste.

import '../models/categorie_service.dart';
import '../models/demande_menage.dart';

/// Paramètres de tarification (table `tarifs`) : valeur par (service, clé).
class Tarifs {
  final Map<String, Map<String, int>> _valeurs;
  const Tarifs._(this._valeurs);

  /// Valeurs de départ, identiques au contenu initial de la table `tarifs`
  /// (009). Servent aussi de repli si la table n'a pas pu être lue.
  static const Map<String, Map<String, int>> depart = {
    'global': {
      'tarif_horaire': 1200,
      'deplacement': 1000,
      'remise_abonnement': 0,
      'seuil_ecart_ia': 50,
    },
    'menage': {
      'chambre': 30,
      'salon': 40,
      'cuisine': 45,
      'douche_wc': 30,
      'canape': 40,
      'tapis': 25,
      'vitres': 30,
      'frigo': 20,
      'four': 20,
      'etat_sale': 25,
      'etat_tres_sale': 50,
      'produits': 1500,
    },
    'linge': {
      'panier': 40,
      'draps_delicats': 15,
      'piece_repassage': 4,
      'produits': 500,
    },
    'dechets': {
      'sac': 5,
      'etage': 2,
      'distance_10m': 1,
      'minimum': 15,
    },
    'nuisibles': {
      'piece': 20,
      'produit_cafards': 1500,
      'produit_moustiques': 1000,
      'produit_punaises': 3000,
      'produit_rongeurs': 2500,
      'produit_fourmis': 1000,
      'infestation_moyenne': 50,
      'infestation_forte': 100,
    },
  };

  static const Tarifs defaut = Tarifs._(depart);

  /// Tarifs lus en base, complétés par [depart] pour toute clé absente.
  factory Tarifs.depuisLignes(Iterable<Map<String, dynamic>> lignes) {
    final m = {
      for (final e in depart.entries) e.key: Map<String, int>.of(e.value),
    };
    for (final l in lignes) {
      final service = l['service'] as String?;
      final cle = l['cle'] as String?;
      final valeur = (l['valeur'] as num?)?.round();
      if (service == null || cle == null || valeur == null) continue;
      (m[service] ??= {})[cle] = valeur;
    }
    return Tarifs._(m);
  }

  int v(String service, String cle) => _valeurs[service]?[cle] ?? 0;
}

/// Une ligne du détail du prix, pour l'affichage.
class LignePrix {
  final String libelle;
  final String valeur;
  const LignePrix(this.libelle, this.valeur);
}

/// Résultat du calcul.
class EstimationPrix {
  final int minutes;
  final int mainOeuvre;
  final int deplacement;
  final int produits;
  final int prixPassage;

  /// Passages par mois (1 pour une demande ponctuelle).
  final int passages;
  final int prixTotal;
  final List<LignePrix> lignes;

  const EstimationPrix({
    required this.minutes,
    required this.mainOeuvre,
    required this.deplacement,
    required this.produits,
    required this.prixPassage,
    required this.passages,
    required this.prixTotal,
    this.lignes = const [],
  });

  /// Résultat de la fonction SQL (`calculer_prix_demande`).
  factory EstimationPrix.fromServeur(Map<String, dynamic> m) => EstimationPrix(
        minutes: (m['minutes'] as num).toInt(),
        mainOeuvre: (m['main_oeuvre'] as num).toInt(),
        deplacement: (m['deplacement'] as num).toInt(),
        produits: (m['produits'] as num).toInt(),
        prixPassage: (m['prix_passage'] as num).toInt(),
        passages: (m['passages'] as num).toInt(),
        prixTotal: (m['prix_total'] as num).toInt(),
      );

  EstimationPrix avecLignes(List<LignePrix> l) => EstimationPrix(
        minutes: minutes,
        mainOeuvre: mainOeuvre,
        deplacement: deplacement,
        produits: produits,
        prixPassage: prixPassage,
        passages: passages,
        prixTotal: prixTotal,
        lignes: l,
      );

  bool memePrix(EstimationPrix o) =>
      prixTotal == o.prixTotal && prixPassage == o.prixPassage;
}

/// Arrondi à la centaine supérieure : 4 420 → 4 500.
int arrondiCentaine(int x) => x <= 0 ? 0 : ((x + 99) ~/ 100) * 100;

/// « 5 400 FCFA » (espaces insécables : jamais coupé en fin de ligne).
String fcfa(int montant) {
  final s = montant.abs().toString();
  final b = StringBuffer(montant < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

/// « 2 h 55 », « 45 min », avec des espaces insécables : la durée ne se
/// coupe jamais en fin de ligne.
String duree(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _nombre(int n, String un, String plusieurs) =>
    n > 1 ? '$n $plusieurs' : '$n $un';

/// Calcule le prix d'une demande avec les [tarifs] donnés.
EstimationPrix calculerPrix(DemandeMenage d, [Tarifs tarifs = Tarifs.defaut]) {
  int t(String cle) => tarifs.v(d.service.code, cle);
  int g(String cle) => tarifs.v('global', cle);
  final lignes = <LignePrix>[];
  var minutes = 0;
  var produits = 0;
  var passagesSemaine = 1;

  void poste(String cle, int quantite, String un, [String? plusieurs]) {
    if (quantite <= 0) return;
    minutes += quantite * t(cle);
    lignes.add(LignePrix(
        '${_nombre(quantite, un, plusieurs ?? '${un}s')} × ${t(cle)} min',
        duree(quantite * t(cle))));
  }

  void option(String cle, String libelle) {
    if (!d.oui(cle)) return;
    minutes += t(cle);
    lignes.add(LignePrix(libelle, '+${duree(t(cle))}'));
  }

  switch (d.service) {
    case CategorieService.menage:
      poste('chambre', d.entier(Q.chambres), 'chambre');
      poste('salon', d.entier(Q.salons), 'salon');
      poste('cuisine', d.entier(Q.cuisines), 'cuisine');
      poste('douche_wc', d.entier(Q.doucheWc), 'douche / WC', 'douches / WC');
      poste('canape', d.entier(Q.canapes), 'canapé');
      poste('tapis', d.entier(Q.tapis), 'tapis', 'tapis');
      option('vitres', 'Vitres');
      option('frigo', 'Intérieur du frigo');
      option('four', 'Intérieur du four');
      final maj = switch (d.code(Q.etat)) {
        'sale' => t('etat_sale'),
        'tres_sale' => t('etat_tres_sale'),
        _ => 0,
      };
      if (maj > 0) {
        final avant = minutes;
        minutes = (minutes * (100 + maj) + 99) ~/ 100;
        lignes.add(LignePrix(
            'Logement ${d.code(Q.etat) == 'sale' ? 'sale' : 'très sale'} : +$maj %',
            '+${duree(minutes - avant)}'));
      }
      if (d.produitsFournis) produits = t('produits');

    case CategorieService.linge:
      final paniers = d.entier(Q.paniers) < 1 ? 1 : d.entier(Q.paniers);
      poste('panier', paniers, 'panier');
      if (d.oui(Q.drapsDelicats)) {
        minutes += paniers * t('draps_delicats');
        lignes.add(LignePrix('Draps ou vêtements délicats',
            '+${duree(paniers * t('draps_delicats'))}'));
      }
      if (d.oui(Q.repassage)) {
        poste('piece_repassage', d.entier(Q.piecesRepassage),
            'pièce à repasser', 'pièces à repasser');
      }
      if (d.produitsFournis) produits = paniers * t('produits');

    case CategorieService.dechets:
      final hebdo = d.formule == Formule.abonnement &&
          d.frequence == Frequence.hebdomadaire;
      passagesSemaine = hebdo ? d.entier(Q.passagesSemaine).clamp(1, 7) : 1;
      final sacs = d.entier(Q.sacs);
      final sacsPassage =
          hebdo ? (sacs + passagesSemaine - 1) ~/ passagesSemaine : sacs;
      poste('sac', sacsPassage, 'sac');
      poste('etage', d.entier(Q.etage), 'étage');
      final dizaines =
          ((int.tryParse(d.code(Q.distanceBac) ?? '') ?? 0) + 9) ~/ 10;
      if (dizaines > 0) {
        minutes += dizaines * t('distance_10m');
        lignes.add(LignePrix(
            'Trajet jusqu\'au bac', '+${duree(dizaines * t('distance_10m'))}'));
      }
      if (minutes < t('minimum')) {
        lignes.add(LignePrix('Passage minimum', duree(t('minimum'))));
        minutes = t('minimum');
      }

    case CategorieService.nuisibles:
      final pieces = d.entier(Q.pieces) < 1 ? 1 : d.entier(Q.pieces);
      poste('piece', pieces, 'pièce');
      final base = pieces * t('produit_${d.code(Q.nuisible) ?? 'cafards'}');
      final maj = switch (d.code(Q.infestation)) {
        'moyenne' => t('infestation_moyenne'),
        'forte' => t('infestation_forte'),
        _ => 0,
      };
      produits = (base * (100 + maj) + 99) ~/ 100;
  }

  final mainOeuvre = (minutes * g('tarif_horaire') + 30) ~/ 60;
  final deplacement = g('deplacement');
  final prixPassage = arrondiCentaine(mainOeuvre + deplacement + produits);

  final passages = switch ((d.formule, d.frequence)) {
    (Formule.abonnement, Frequence.hebdomadaire) => 4 * passagesSemaine,
    _ => 1,
  };
  final remise = d.formule == Formule.abonnement ? g('remise_abonnement') : 0;
  final brut = prixPassage * passages;
  final prixTotal = arrondiCentaine((brut * (100 - remise) + 99) ~/ 100);

  lignes.addAll([
    LignePrix(
        'Main d\'œuvre (${duree(minutes)} × ${fcfa(g('tarif_horaire'))}/h)',
        fcfa(mainOeuvre)),
    LignePrix('Déplacement', fcfa(deplacement)),
    if (produits > 0)
      LignePrix(
          d.service == CategorieService.nuisibles
              ? 'Produits de traitement'
              : 'Produits apportés',
          fcfa(produits)),
    if (passages > 1)
      LignePrix('$passages passages par mois', '${fcfa(prixPassage)} chacun'),
    if (remise > 0) LignePrix('Remise abonnement', '−$remise %'),
  ]);

  return EstimationPrix(
    minutes: minutes,
    mainOeuvre: mainOeuvre,
    deplacement: deplacement,
    produits: produits,
    prixPassage: prixPassage,
    passages: passages,
    prixTotal: prixTotal,
    lignes: lignes,
  );
}
