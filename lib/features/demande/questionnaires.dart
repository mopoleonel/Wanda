// Questionnaire propre à chaque service : compteurs, choix, interrupteurs.
// Chaque réponse modifie la demande, dont le prix est recalculé en direct.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/bordereau.dart';
import '../../data/models/categorie_service.dart';
import '../../data/models/demande_menage.dart';
import '../../data/pricing/tarification.dart';
import 'composants.dart';

/// Ce qui empêche de continuer, ou null si le questionnaire est complet.
String? manqueQuestionnaire(DemandeMenage d) => switch (d.service) {
      CategorieService.menage => d.entier(Q.chambres) +
                  d.entier(Q.salons) +
                  d.entier(Q.cuisines) +
                  d.entier(Q.doucheWc) +
                  d.entier(Q.canapes) +
                  d.entier(Q.tapis) ==
              0
          ? 'Indiquez au moins une pièce à nettoyer.'
          : null,
      CategorieService.dechets =>
        d.entier(Q.sacs) < 1 ? 'Indiquez au moins un sac.' : null,
      CategorieService.linge || CategorieService.nuisibles => null,
    };

/// Étape « formule » : une fois ou abonnement, et le rythme.
class QuestionsFormule extends StatelessWidget {
  final DemandeMenage demande;
  final ValueChanged<DemandeMenage> onChanged;
  const QuestionsFormule(
      {super.key, required this.demande, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final d = demande;
    final abonnement = d.formule == Formule.abonnement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ServiceStyle.ofCategorie(d.service).libelle,
            style: AppText.sectionTitle),
        const SizedBox(height: 2),
        Text(d.service.detail, style: AppText.caption),
        const SizedBox(height: AppSpace.xl),
        SegmentedButton<Formule>(
          showSelectedIcon: false,
          style:
              SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          segments: const [
            ButtonSegment(
                value: Formule.ponctuelle,
                icon: Icon(Icons.event_available_rounded),
                label: Text('Une fois')),
            ButtonSegment(
                value: Formule.abonnement,
                icon: Icon(Icons.autorenew_rounded),
                label: Text('Abonnement')),
          ],
          selected: {d.formule},
          onSelectionChanged: (s) => onChanged(s.first == Formule.ponctuelle
              ? d.copyWith(formule: Formule.ponctuelle, effacerFrequence: true)
              : d.copyWith(
                  formule: Formule.abonnement,
                  frequence: d.frequence ?? Frequence.hebdomadaire)),
        ),
        const SizedBox(height: AppSpace.lg),
        if (abonnement) ...[
          ListeChoix(
            titre: 'À quel rythme ?',
            choix: const [
              Choix('hebdomadaire', 'Chaque semaine',
                  'Le même prestataire revient chaque semaine'),
              Choix('mensuel', 'Chaque mois', 'Un passage par mois'),
            ],
            valeur: d.frequence?.code,
            onChanged: (c) =>
                onChanged(d.copyWith(frequence: Frequence.fromCode(c))),
          ),
          Text('Le prix affiché est alors le prix par mois.',
              style: AppText.caption),
        ] else
          Text(
              'Un seul passage, au jour et au moment que vous choisissez à la fin.',
              style: AppText.caption),
      ],
    );
  }
}

/// Étape « détails » : les questions du service.
class QuestionsService extends StatelessWidget {
  final DemandeMenage demande;
  final Tarifs tarifs;
  final ValueChanged<DemandeMenage> onChanged;
  const QuestionsService(
      {super.key,
      required this.demande,
      required this.tarifs,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final d = demande;
    Widget compteur(String cle, String libelle,
            {String? aide, int min = 0, int max = 20, int pas = 1}) =>
        Compteur(
          libelle: libelle,
          aide: aide,
          valeur: d.entier(cle),
          min: min,
          max: max,
          pas: pas,
          onChanged: (v) => onChanged(d.avec(cle, v)),
        );
    Widget option(String cle, String libelle, {String? aide}) => Interrupteur(
          libelle: libelle,
          aide: aide,
          valeur: d.oui(cle),
          onChanged: (v) => onChanged(d.avec(cle, v)),
        );
    final encre = ServiceStyle.ofCategorie(d.service).ink;
    Widget choix(String titre, List<Choix> liste, String cle) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: ListeChoix(
            titre: titre,
            choix: liste,
            valeur: d.code(cle),
            encre: encre,
            onChanged: (c) => onChanged(d.avec(cle, c)),
          ),
        );

    final produits = d.produitsModifiables
        ? [
            const TitreGroupe('Produits'),
            Interrupteur(
              libelle: 'Le prestataire apporte les produits',
              aide: d.service == CategorieService.linge
                  ? '+ ${fcfa(tarifs.v('linge', 'produits'))} par panier'
                  : '+ ${fcfa(tarifs.v(d.service.code, 'produits'))}',
              valeur: d.produitsFournis,
              onChanged: (v) => onChanged(d.copyWith(produitsFournis: v)),
            ),
          ]
        : const <Widget>[];

    final hebdo = d.formule == Formule.abonnement &&
        d.frequence == Frequence.hebdomadaire;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (d.service) {
        CategorieService.menage => [
            const TitreGroupe('Pièces à nettoyer'),
            compteur(Q.chambres, 'Chambres', max: 10),
            compteur(Q.salons, 'Salons', max: 6),
            compteur(Q.cuisines, 'Cuisines', max: 4),
            compteur(Q.doucheWc, 'Douches / WC', max: 8),
            const TitreGroupe('En plus'),
            compteur(Q.canapes, 'Canapés', aide: 'Lavage des assises', max: 6),
            compteur(Q.tapis, 'Tapis', max: 6),
            option(Q.vitres, 'Vitres'),
            option(Q.frigo, 'Intérieur du frigo'),
            option(Q.four, 'Intérieur du four'),
            choix('État du logement', Q.etats, Q.etat),
            ...produits,
          ],
        CategorieService.linge => [
            const TitreGroupe('Votre linge'),
            compteur(Q.paniers, 'Paniers',
                aide: 'Un panier ≈ une machine (5 kg)', min: 1, max: 10),
            option(Q.drapsDelicats, 'Draps ou vêtements délicats',
                aide: 'Lavage plus long, à la main si besoin'),
            option(Q.repassage, 'Repassage'),
            if (d.oui(Q.repassage))
              compteur(Q.piecesRepassage, 'Pièces à repasser',
                  aide: 'Chemises, pantalons, pagnes…', max: 100, pas: 5),
            ...produits,
          ],
        CategorieService.dechets => [
            const TitreGroupe('Vos poubelles'),
            compteur(Q.sacs, hebdo ? 'Sacs par semaine' : 'Sacs à emporter',
                aide: 'Sacs de 50 litres', min: 1, max: 30),
            if (hebdo)
              compteur(Q.passagesSemaine, 'Passages par semaine',
                  min: 1, max: 7),
            compteur(Q.etage, 'Étage', aide: '0 = rez-de-chaussée', max: 20),
            choix('Distance jusqu\'au bac', Q.distances, Q.distanceBac),
          ],
        CategorieService.nuisibles => [
            choix('Quel nuisible ?', Q.nuisibles, Q.nuisible),
            const TitreGroupe('Où ?'),
            compteur(Q.pieces, 'Pièces à traiter', min: 1, max: 15),
            choix('Niveau d\'infestation', Q.infestations, Q.infestation),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text(
                  'Les produits de traitement sont toujours apportés par le prestataire.',
                  style: AppText.caption),
            ),
          ],
      },
    );
  }
}

/// Consigne de prise de vue, par service.
String consignePhotos(CategorieService s) => switch (s) {
      CategorieService.menage =>
        'Photographiez la pièce la plus sale, en entier, puis une autre pièce si vous voulez.',
      CategorieService.linge =>
        'Photographiez tout le linge à laver : panier ou tas entier.',
      CategorieService.dechets =>
        'Photographiez les sacs à emporter, tous ensemble.',
      CategorieService.nuisibles =>
        'Photographiez les nuisibles ou leurs traces : coins, sous l\'évier, derrière les meubles.',
    };
