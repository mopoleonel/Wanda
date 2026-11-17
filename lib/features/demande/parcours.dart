// Parcours guidé de la réservation : une seule question à l'écran.
//
// Chaque réponse est une grande tuile ; toucher une réponse passe à la
// question suivante. Les questions qui ne concernent pas le client ne sont
// pas posées (nombre de pièces à repasser seulement si repassage, passages
// par semaine seulement en abonnement hebdomadaire…). Le prix suit en
// direct dans la barre du bas.

import 'package:flutter/material.dart';

import '../../data/models/categorie_service.dart';
import '../../data/models/demande_menage.dart';
import '../../data/pricing/tarification.dart';

/// Ce que le client a choisi jusqu'ici : la demande, le jour et le moment.
class Saisie {
  final DemandeMenage demande;
  final DateTime date;
  final Creneau creneau;
  const Saisie(this.demande, this.date, this.creneau);

  Saisie avec({DemandeMenage? demande, DateTime? date, Creneau? creneau}) =>
      Saisie(
          demande ?? this.demande, date ?? this.date, creneau ?? this.creneau);
}

/// Une réponse possible, affichée en tuile.
class Option {
  final String libelle;
  final String? detail;
  final IconData? icone;
  final bool Function(Saisie) choisie;
  final Saisie Function(Saisie) appliquer;
  const Option(this.libelle,
      {this.detail,
      this.icone,
      required this.choisie,
      required this.appliquer});
}

enum TypeQuestion {
  /// Une seule réponse : la toucher passe à la suite.
  unique,

  /// Plusieurs réponses cochées, puis « Continuer ».
  multiple,
}

class QuestionParcours {
  final String id;
  final String titre;
  final String? aide;
  final TypeQuestion type;
  final List<Option> options;

  /// Réponse actuelle en quelques mots (puce « vos réponses »).
  final String Function(Saisie) resume;

  /// Valeurs au-delà des tuiles : un compteur s'affiche (« Plus… »).
  final ({int min, int max, String cle})? auDela;

  /// Tuiles en grille de 3 (nombres, jours) plutôt qu'en liste.
  final bool grille;

  const QuestionParcours({
    required this.id,
    required this.titre,
    this.aide,
    this.type = TypeQuestion.unique,
    required this.options,
    required this.resume,
    this.auDela,
    this.grille = false,
  });
}

String _pluriel(int n, String un, String plusieurs) =>
    '$n ${n > 1 ? plusieurs : un}';

/// Question « combien ? » : des tuiles pour les valeurs courantes, et un
/// compteur au-delà.
QuestionParcours _nombre({
  required String id,
  required String titre,
  String? aide,
  required String cle,
  required List<int> valeurs,
  required int max,
  required String Function(int) libelle,
}) =>
    QuestionParcours(
      id: id,
      titre: titre,
      aide: aide,
      grille: true,
      options: [
        for (final v in valeurs)
          Option(
            libelle(v),
            choisie: (s) => s.demande.entier(cle) == v,
            appliquer: (s) => s.avec(demande: s.demande.avec(cle, v)),
          ),
      ],
      auDela: max > valeurs.last
          ? (min: valeurs.last + 1, max: max, cle: cle)
          : null,
      resume: (s) => libelle(s.demande.entier(cle)),
    );

QuestionParcours _ouiNon({
  required String id,
  required String titre,
  String? aide,
  required String cle,
  String oui = 'Oui',
  String non = 'Non',
  String? detailOui,
  required String Function(bool) resume,
}) =>
    QuestionParcours(
      id: id,
      titre: titre,
      aide: aide,
      options: [
        Option(non,
            icone: Icons.close_rounded,
            choisie: (s) => !s.demande.oui(cle),
            appliquer: (s) => s.avec(demande: s.demande.avec(cle, false))),
        Option(oui,
            detail: detailOui,
            icone: Icons.check_rounded,
            choisie: (s) => s.demande.oui(cle),
            appliquer: (s) => s.avec(demande: s.demande.avec(cle, true))),
      ],
      resume: (s) => resume(s.demande.oui(cle)),
    );

QuestionParcours _choix({
  required String id,
  required String titre,
  String? aide,
  required String cle,
  required List<Choix> choix,
  Map<String, IconData> icones = const {},
}) =>
    QuestionParcours(
      id: id,
      titre: titre,
      aide: aide,
      options: [
        for (final c in choix)
          Option(c.libelle,
              detail: c.aide,
              icone: icones[c.code],
              choisie: (s) => s.demande.code(cle) == c.code,
              appliquer: (s) => s.avec(demande: s.demande.avec(cle, c.code))),
      ],
      resume: (s) =>
          choix
              .where((c) => c.code == s.demande.code(cle))
              .firstOrNull
              ?.libelle ??
          '—',
    );

/// Une seule fois, chaque semaine ou chaque mois : formule et rythme en une
/// seule question.
QuestionParcours _rythme(CategorieService service) => QuestionParcours(
      id: 'rythme',
      titre: 'Une seule fois, ou régulièrement ?',
      options: [
        Option('Une seule fois',
            detail: 'Un passage, au jour que vous choisissez',
            icone: Icons.event_available_rounded,
            choisie: (s) => s.demande.formule == Formule.ponctuelle,
            appliquer: (s) => s.avec(
                demande: s.demande.copyWith(
                    formule: Formule.ponctuelle, effacerFrequence: true))),
        Option('Chaque semaine',
            detail:
                'Le même prestataire revient chaque semaine · prix par mois',
            icone: Icons.autorenew_rounded,
            choisie: (s) => s.demande.frequence == Frequence.hebdomadaire,
            appliquer: (s) => s.avec(
                demande: s.demande.copyWith(
                    formule: Formule.abonnement,
                    frequence: Frequence.hebdomadaire))),
        Option('Chaque mois',
            detail: 'Un passage par mois · prix par mois',
            icone: Icons.calendar_month_rounded,
            choisie: (s) => s.demande.frequence == Frequence.mensuel,
            appliquer: (s) => s.avec(
                demande: s.demande.copyWith(
                    formule: Formule.abonnement,
                    frequence: Frequence.mensuel))),
      ],
      resume: (s) => s.demande.formule == Formule.ponctuelle
          ? 'Une fois'
          : s.demande.frequence?.libelle ?? 'Abonnement',
    );

/// Options du ménage, cochées sur un seul écran.
QuestionParcours _optionsMenage() {
  Option bascule(String libelle, String cle, IconData icone,
          {bool compte = false}) =>
      Option(libelle,
          icone: icone,
          choisie: (s) =>
              compte ? s.demande.entier(cle) > 0 : s.demande.oui(cle),
          appliquer: (s) => s.avec(
              demande: compte
                  ? s.demande.avec(cle, s.demande.entier(cle) > 0 ? 0 : 1)
                  : s.demande.avec(cle, !s.demande.oui(cle))));
  return QuestionParcours(
    id: 'options',
    titre: 'Autre chose à nettoyer ?',
    aide: 'Cochez ce qui vous intéresse, puis continuez.',
    type: TypeQuestion.multiple,
    options: [
      bascule('Vitres', Q.vitres, Icons.window_rounded),
      bascule('Intérieur du frigo', Q.frigo, Icons.kitchen_rounded),
      bascule('Intérieur du four', Q.four, Icons.microwave_rounded),
      bascule('Canapés', Q.canapes, Icons.weekend_rounded, compte: true),
      bascule('Tapis', Q.tapis, Icons.texture_rounded, compte: true),
    ],
    resume: (s) {
      final d = s.demande;
      final choisis = [
        if (d.oui(Q.vitres)) 'vitres',
        if (d.oui(Q.frigo)) 'frigo',
        if (d.oui(Q.four)) 'four',
        if (d.entier(Q.canapes) > 0) 'canapés',
        if (d.entier(Q.tapis) > 0) 'tapis',
      ];
      return choisis.isEmpty ? 'Rien en plus' : choisis.join(', ');
    },
  );
}

/// Le prestataire apporte-t-il les produits ? (champ de la demande, pas du
/// questionnaire ; jamais demandé pour les nuisibles, toujours fournis).
QuestionParcours _produits(CategorieService service, Tarifs t) {
  final linge = service == CategorieService.linge;
  final prix = fcfa(t.v(service.code, 'produits'));
  return QuestionParcours(
    id: 'produits',
    titre: linge ? 'Qui apporte la lessive ?' : 'Qui apporte les produits ?',
    options: [
      Option('Moi',
          icone: Icons.person_rounded,
          choisie: (s) => !s.demande.produitsFournis,
          appliquer: (s) =>
              s.avec(demande: s.demande.copyWith(produitsFournis: false))),
      Option('Le prestataire',
          detail: linge ? '+ $prix par panier' : '+ $prix',
          icone: Icons.inventory_2_rounded,
          choisie: (s) => s.demande.produitsFournis,
          appliquer: (s) =>
              s.avec(demande: s.demande.copyWith(produitsFournis: true))),
    ],
    resume: (s) =>
        s.demande.produitsFournis ? 'Produits apportés' : 'Mes produits',
  );
}

const _jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

String libelleJour(DateTime d, DateTime aujourdhui) {
  final ecart = DateTime(d.year, d.month, d.day)
      .difference(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day))
      .inDays;
  final date = '${d.day}/${d.month.toString().padLeft(2, '0')}';
  return switch (ecart) {
    0 => "Aujourd'hui",
    1 => 'Demain',
    _ => '${_jours[d.weekday - 1]} $date',
  };
}

QuestionParcours _jour(DateTime aujourdhui) {
  final debut = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  return QuestionParcours(
    id: 'jour',
    titre: 'Quel jour ?',
    grille: true,
    options: [
      for (var i = 0; i < 9; i++)
        Option(
          libelleJour(
              DateTime(debut.year, debut.month, debut.day + i), aujourdhui),
          choisie: (s) =>
              s.date == DateTime(debut.year, debut.month, debut.day + i),
          appliquer: (s) =>
              s.avec(date: DateTime(debut.year, debut.month, debut.day + i)),
        ),
    ],
    resume: (s) => libelleJour(s.date, aujourdhui),
  );
}

QuestionParcours _moment() => QuestionParcours(
      id: 'moment',
      titre: 'À quel moment ?',
      options: [
        Option('Le matin',
            detail: 'Entre 8 h et 12 h',
            icone: Icons.wb_twilight_rounded,
            choisie: (s) => s.creneau == Creneau.matin,
            appliquer: (s) => s.avec(creneau: Creneau.matin)),
        Option("L'après-midi",
            detail: 'Entre 13 h et 18 h',
            icone: Icons.wb_sunny_rounded,
            choisie: (s) => s.creneau == Creneau.apresMidi,
            appliquer: (s) => s.avec(creneau: Creneau.apresMidi)),
      ],
      resume: (s) => s.creneau.libelle,
    );

/// Les questions à poser, dans l'ordre, selon ce qui est déjà répondu.
List<QuestionParcours> parcoursPour(Saisie s, Tarifs t,
    {DateTime? maintenant}) {
  final d = s.demande;
  final hebdo =
      d.formule == Formule.abonnement && d.frequence == Frequence.hebdomadaire;
  final service = switch (d.service) {
    CategorieService.menage => [
        _nombre(
            id: 'chambres',
            titre: 'Combien de chambres ?',
            cle: Q.chambres,
            valeurs: const [0, 1, 2, 3, 4, 5],
            max: 10,
            libelle: (n) =>
                n == 0 ? 'Aucune' : _pluriel(n, 'chambre', 'chambres')),
        _nombre(
            id: 'salons',
            titre: 'Combien de salons ?',
            cle: Q.salons,
            valeurs: const [0, 1, 2, 3],
            max: 6,
            libelle: (n) => n == 0 ? 'Aucun' : _pluriel(n, 'salon', 'salons')),
        _nombre(
            id: 'cuisines',
            titre: 'Combien de cuisines ?',
            cle: Q.cuisines,
            valeurs: const [0, 1, 2],
            max: 4,
            libelle: (n) =>
                n == 0 ? 'Aucune' : _pluriel(n, 'cuisine', 'cuisines')),
        _nombre(
            id: 'douches',
            titre: 'Combien de douches / WC ?',
            cle: Q.doucheWc,
            valeurs: const [0, 1, 2, 3],
            max: 8,
            libelle: (n) =>
                n == 0 ? 'Aucune' : _pluriel(n, 'douche / WC', 'douches / WC')),
        _optionsMenage(),
        if (d.entier(Q.canapes) > 0)
          _nombre(
              id: 'canapes',
              titre: 'Combien de canapés ?',
              cle: Q.canapes,
              valeurs: const [1, 2, 3],
              max: 6,
              libelle: (n) => _pluriel(n, 'canapé', 'canapés')),
        if (d.entier(Q.tapis) > 0)
          _nombre(
              id: 'tapis',
              titre: 'Combien de tapis ?',
              cle: Q.tapis,
              valeurs: const [1, 2, 3],
              max: 6,
              libelle: (n) => _pluriel(n, 'tapis', 'tapis')),
        _choix(
            id: 'etat',
            titre: 'Dans quel état est le logement ?',
            cle: Q.etat,
            choix: Q.etats,
            icones: const {
              'normal': Icons.sentiment_satisfied_rounded,
              'sale': Icons.sentiment_neutral_rounded,
              'tres_sale': Icons.sentiment_dissatisfied_rounded,
            }),
        _produits(d.service, t),
      ],
    CategorieService.linge => [
        _nombre(
            id: 'paniers',
            titre: 'Combien de paniers de linge ?',
            aide: 'Un panier ≈ une machine (5 kg)',
            cle: Q.paniers,
            valeurs: const [1, 2, 3, 4, 5],
            max: 10,
            libelle: (n) => _pluriel(n, 'panier', 'paniers')),
        _ouiNon(
            id: 'delicats',
            titre: 'Des draps ou vêtements délicats ?',
            aide: 'Lavage plus long, à la main si besoin',
            cle: Q.drapsDelicats,
            resume: (oui) => oui ? 'Délicats' : 'Pas de délicats'),
        _ouiNon(
            id: 'repassage',
            titre: 'Faut-il repasser ?',
            cle: Q.repassage,
            resume: (oui) => oui ? 'Repassage' : 'Sans repassage'),
        if (d.oui(Q.repassage))
          _nombre(
              id: 'pieces_repassage',
              titre: 'Combien de pièces à repasser ?',
              aide: 'Chemises, pantalons, pagnes…',
              cle: Q.piecesRepassage,
              valeurs: const [5, 10, 15, 20, 30, 40],
              max: 100,
              libelle: (n) => _pluriel(n, 'pièce', 'pièces')),
        _produits(d.service, t),
      ],
    CategorieService.dechets => [
        _nombre(
            id: 'sacs',
            titre: hebdo
                ? 'Combien de sacs par semaine ?'
                : 'Combien de sacs à emporter ?',
            aide: 'Sacs de 50 litres',
            cle: Q.sacs,
            valeurs: const [1, 2, 3, 4, 5, 6],
            max: 30,
            libelle: (n) => _pluriel(n, 'sac', 'sacs')),
        if (hebdo)
          _nombre(
              id: 'passages',
              titre: 'Combien de passages par semaine ?',
              cle: Q.passagesSemaine,
              valeurs: const [1, 2, 3],
              max: 7,
              libelle: (n) => _pluriel(n, 'passage', 'passages')),
        _nombre(
            id: 'etage',
            titre: 'À quel étage ?',
            cle: Q.etage,
            valeurs: const [0, 1, 2, 3, 4, 5],
            max: 20,
            libelle: (n) => n == 0
                ? 'Rez-de-chaussée'
                : '${n == 1 ? '1er' : '${n}e'} étage'),
        _choix(
            id: 'distance',
            titre: "Jusqu'au bac, quelle distance ?",
            cle: Q.distanceBac,
            choix: Q.distances),
      ],
    CategorieService.nuisibles => [
        _choix(
            id: 'nuisible',
            titre: 'Quel nuisible ?',
            cle: Q.nuisible,
            choix: Q.nuisibles,
            icones: const {
              'cafards': Icons.pest_control_rounded,
              'moustiques': Icons.bug_report_rounded,
              'punaises': Icons.bed_rounded,
              'rongeurs': Icons.pest_control_rodent_rounded,
              'fourmis': Icons.grain_rounded,
            }),
        _nombre(
            id: 'pieces',
            titre: 'Combien de pièces à traiter ?',
            cle: Q.pieces,
            valeurs: const [1, 2, 3, 4, 5],
            max: 15,
            libelle: (n) => _pluriel(n, 'pièce', 'pièces')),
        _choix(
            id: 'infestation',
            titre: "Quel niveau d'infestation ?",
            cle: Q.infestation,
            choix: Q.infestations),
      ],
  };
  return [
    _rythme(d.service),
    ...service,
    _jour(maintenant ?? DateTime.now()),
    _moment(),
  ];
}
