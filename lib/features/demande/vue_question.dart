// Affichage d'une question du parcours guidé : progression, réponses déjà
// données (puces cliquables pour revenir), la question et ses tuiles.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'composants.dart';
import 'parcours.dart';

class VueQuestion extends StatefulWidget {
  final List<QuestionParcours> questions;
  final int index;
  final Saisie saisie;
  final Color encre;

  /// Nouvelle saisie ; [avancer] : la réponse est complète, question suivante.
  final void Function(Saisie saisie, {required bool avancer}) onReponse;

  /// Retour à une question déjà répondue (toucher une puce).
  final ValueChanged<int> onRevenir;

  const VueQuestion({
    super.key,
    required this.questions,
    required this.index,
    required this.saisie,
    required this.encre,
    required this.onReponse,
    required this.onRevenir,
  });

  @override
  State<VueQuestion> createState() => _VueQuestionState();
}

class _VueQuestionState extends State<VueQuestion> {
  /// Compteur « au-delà des tuiles » ouvert.
  bool _plus = false;

  @override
  void didUpdateWidget(VueQuestion ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.index != widget.index) _plus = false;
  }

  QuestionParcours get _q => widget.questions[widget.index];

  void _choisir(Option o) {
    HapticFeedback.selectionClick();
    final q = _q;
    widget.onReponse(o.appliquer(widget.saisie),
        avancer: q.type == TypeQuestion.unique);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final s = widget.saisie;
    final auDela = q.auDela;
    final valeurAuDela = auDela == null ? null : s.demande.entier(auDela.cle);
    final horsTuiles = auDela != null && valeurAuDela! >= auDela.min;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Réponses déjà données : le client voit sa commande se construire.
        if (widget.index > 0) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widget.index; i++)
                _PuceReponse(
                  texte: widget.questions[i].resume(s),
                  onTap: () => widget.onRevenir(i),
                ),
            ],
          ),
        ],

        // Le titre de la question est dans l'en-tête de la page (plus de
        // place pour les réponses sur les petits écrans).
        if (widget.index > 0) const SizedBox(height: AppSpace.lg),
        if (q.aide != null) ...[
          Text(q.aide!, style: AppText.body.copyWith(color: AppColors.inkSoft)),
          const SizedBox(height: AppSpace.md),
        ],

        if (q.grille)
          _Grille(
            options: q.options,
            saisie: s,
            encre: widget.encre,
            plus: auDela == null
                ? null
                : _TuilePlus(
                    actif: _plus || horsTuiles,
                    libelle: horsTuiles ? '$valeurAuDela' : 'Plus…',
                    encre: widget.encre,
                    onTap: () => setState(() => _plus = true),
                  ),
            onChoisir: _choisir,
          )
        else
          for (final o in q.options) ...[
            _TuileReponse(
              option: o,
              choisie: o.choisie(s),
              multiple: q.type == TypeQuestion.multiple,
              encre: widget.encre,
              onTap: () => _choisir(o),
            ),
            const SizedBox(height: AppSpace.sm),
          ],

        // Au-delà des tuiles : un compteur, validé par « Suivant ».
        if (auDela != null && (_plus || horsTuiles)) ...[
          const SizedBox(height: AppSpace.md),
          Compteur(
            libelle: 'Nombre exact',
            valeur: valeurAuDela!.clamp(auDela.min, auDela.max),
            min: auDela.min,
            max: auDela.max,
            onChanged: (v) => widget.onReponse(
                s.avec(demande: s.demande.avec(auDela.cle, v)),
                avancer: false),
          ),
        ],
      ],
    );
  }
}

class _PuceReponse extends StatelessWidget {
  final String texte;
  final VoidCallback onTap;
  const _PuceReponse({required this.texte, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Modifier : $texte',
      excludeSemantics: true,
      child: Material(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_rounded,
                  size: 14, color: AppColors.letterhead),
              const SizedBox(width: 4),
              Flexible(
                child: Text(texte,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                        color: AppColors.letterheadDeep,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Réponse en pleine largeur : icône, libellé, détail, coche.
class _TuileReponse extends StatelessWidget {
  final Option option;
  final bool choisie;
  final bool multiple;
  final Color encre;
  final VoidCallback onTap;

  const _TuileReponse({
    required this.option,
    required this.choisie,
    required this.multiple,
    required this.encre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisie,
      child: Material(
        color: choisie ? encre.withValues(alpha: 0.08) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
              color: choisie ? encre : AppColors.rule, width: choisie ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg, vertical: 12),
              child: Row(children: [
                if (option.icone != null) ...[
                  Icon(option.icone,
                      color: choisie ? encre : AppColors.inkSoft, size: 26),
                  const SizedBox(width: AppSpace.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.libelle,
                          style: AppText.bodyStrong.copyWith(fontSize: 17)),
                      if (option.detail != null)
                        Text(option.detail!, style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Icon(
                  multiple
                      ? (choisie
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded)
                      : (choisie
                          ? Icons.radio_button_checked_rounded
                          : Icons.chevron_right_rounded),
                  color: choisie ? encre : AppColors.inkMuted,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nombres ou jours : tuiles carrées, trois par ligne.
class _Grille extends StatelessWidget {
  final List<Option> options;
  final Saisie saisie;
  final Color encre;
  final Widget? plus;
  final ValueChanged<Option> onChoisir;

  const _Grille({
    required this.options,
    required this.saisie,
    required this.encre,
    required this.plus,
    required this.onChoisir,
  });

  @override
  Widget build(BuildContext context) {
    final tuiles = <Widget>[
      for (final o in options)
        _TuileCourte(
          libelle: o.libelle,
          choisie: o.choisie(saisie),
          encre: encre,
          onTap: () => onChoisir(o),
        ),
      if (plus != null) plus!,
    ];
    return LayoutBuilder(builder: (context, box) {
      const ecart = AppSpace.sm;
      final largeur = (box.maxWidth - 2 * ecart) / 3;
      return Wrap(
        spacing: ecart,
        runSpacing: ecart,
        children: [for (final t in tuiles) SizedBox(width: largeur, child: t)],
      );
    });
  }
}

class _TuileCourte extends StatelessWidget {
  final String libelle;
  final bool choisie;
  final Color encre;
  final VoidCallback onTap;

  const _TuileCourte({
    required this.libelle,
    required this.choisie,
    required this.encre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisie,
      child: Material(
        color: choisie ? encre : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: choisie ? encre : AppColors.rule),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(libelle,
                    textAlign: TextAlign.center,
                    style: AppText.bodyStrong.copyWith(
                        color: choisie ? Colors.white : AppColors.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TuilePlus extends StatelessWidget {
  final bool actif;
  final String libelle;
  final Color encre;
  final VoidCallback onTap;
  const _TuilePlus(
      {required this.actif,
      required this.libelle,
      required this.encre,
      required this.onTap});

  @override
  Widget build(BuildContext context) => _TuileCourte(
      libelle: libelle, choisie: actif, encre: encre, onTap: onTap);
}
