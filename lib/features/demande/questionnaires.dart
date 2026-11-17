// Règles du questionnaire communes au parcours guidé (parcours.dart).

import '../../data/models/categorie_service.dart';
import '../../data/models/demande_menage.dart';

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
