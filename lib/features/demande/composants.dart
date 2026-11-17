// Briques du questionnaire de demande : compteurs, choix en tuiles,
// interrupteurs, barre de prix en direct. Utilisables d'une main : cibles
// ≥ 48 dp, aucune saisie de texte.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/bordereau.dart';
import '../../data/models/demande_menage.dart';
import '../../data/pricing/tarification.dart';

/// Ligne « libellé ……… [−] 2 [+] ».
class Compteur extends StatelessWidget {
  final String libelle;
  final String? aide;
  final int valeur;
  final int min;
  final int max;
  final int pas;
  final ValueChanged<int> onChanged;

  const Compteur({
    super.key,
    required this.libelle,
    this.aide,
    required this.valeur,
    required this.onChanged,
    this.min = 0,
    this.max = 20,
    this.pas = 1,
  });

  @override
  Widget build(BuildContext context) {
    void changer(int v) {
      HapticFeedback.selectionClick();
      onChanged(v.clamp(min, max));
    }

    return Semantics(
      label: libelle,
      value: '$valeur',
      increasedValue: '${(valeur + pas).clamp(min, max)}',
      decreasedValue: '${(valeur - pas).clamp(min, max)}',
      onIncrease: valeur < max ? () => changer(valeur + pas) : null,
      onDecrease: valeur > min ? () => changer(valeur - pas) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(children: [
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(libelle, style: AppText.bodyStrong),
                  if (aide != null) Text(aide!, style: AppText.caption),
                ],
              ),
            ),
          ),
          ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _Bouton(
                icon: Icons.remove_rounded,
                tooltip: 'Moins',
                onPressed: valeur > min ? () => changer(valeur - pas) : null,
              ),
              SizedBox(
                width: 44,
                child: Text('$valeur',
                    textAlign: TextAlign.center,
                    style: AppText.number.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
              _Bouton(
                icon: Icons.add_rounded,
                tooltip: 'Plus',
                onPressed: valeur < max ? () => changer(valeur + pas) : null,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const _Bouton({required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: IconButton.styleFrom(
        side: BorderSide(
            color: onPressed == null ? AppColors.rule : AppColors.ruleStrong),
        foregroundColor: AppColors.letterhead,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      icon: Icon(icon),
    );
  }
}

/// Barre basse fixe : le prix en direct à gauche, l'action à droite.
class BarrePrix extends StatelessWidget {
  final EstimationPrix? estimation;

  /// « ≈ » tant que le serveur n'a pas confirmé.
  final bool confirme;
  final String action;
  final IconData? icone;
  final bool chargement;
  final VoidCallback? onPressed;

  const BarrePrix({
    super.key,
    required this.estimation,
    this.confirme = false,
    required this.action,
    this.icone,
    this.chargement = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final e = estimation;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.md),
          child: Row(children: [
            if (e != null)
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '${confirme ? 'Prix' : 'Prix estimé'} : '
                      '${fcfa(e.prixTotal)}'
                      '${e.passages > 1 ? ' par mois' : ''}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          confirme
                              ? (e.passages > 1 ? 'Prix par mois' : 'Prix fixe')
                              : (e.passages > 1
                                  ? 'Estimation par mois'
                                  : 'Estimation'),
                          style: AppText.caption),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: FittedBox(
                          key: ValueKey(e.prixTotal),
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${confirme ? '' : '≈ '}${fcfa(e.prixTotal)}',
                            style: AppText.number.copyWith(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (e != null) const SizedBox(width: AppSpace.md),
            Flexible(
              flex: e == null ? 1 : 0,
              child: FilledButton.icon(
                onPressed: chargement ? null : onPressed,
                style: FilledButton.styleFrom(
                    minimumSize: Size(e == null ? double.infinity : 0, 54)),
                icon: chargement
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(icone ?? Icons.arrow_forward_rounded, size: 20),
                label: Text(action),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Le détail d'une estimation, ligne par ligne, montants en chiffres
/// condensés.
class DetailPrix extends StatelessWidget {
  final EstimationPrix estimation;
  const DetailPrix(this.estimation, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in estimation.lignes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(l.libelle, style: AppText.body)),
                const SizedBox(width: AppSpace.md),
                Text(l.valeur,
                    style: AppText.number
                        .copyWith(fontSize: 15, color: AppColors.inkSoft)),
              ],
            ),
          ),
      ],
    );
  }
}

/// En-tête d'une demande : copie carbone du service, libellé, formule.
class EnteteService extends StatelessWidget {
  final DemandeMenage demande;
  const EnteteService(this.demande, {super.key});

  @override
  Widget build(BuildContext context) {
    final style = ServiceStyle.ofCategorie(demande.service);
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: style.tint, borderRadius: BorderRadius.circular(10)),
        child: Icon(style.icon, color: style.ink),
      ),
      const SizedBox(width: AppSpace.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(style.libelle, style: AppText.cardTitle),
            Text(demande.libelleFormule, style: AppText.caption),
          ],
        ),
      ),
    ]);
  }
}
