// Détail d'une demande côté prestataire (avant d'accepter : réponses,
// photos, analyse IA, prix) et formulaire de demande d'ajustement.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../data/models/analyse_ia.dart';
import '../../data/models/demande_menage.dart';
import '../../data/models/sollicitation.dart';
import '../../data/pricing/tarification.dart';
import '../demande/composants.dart';

/// Feuille de détail : tout ce que le prestataire doit voir avant de
/// répondre. [actions] : boutons propres au statut (accepter / refuser…).
class DetailMission extends ConsumerWidget {
  final Sollicitation mission;
  final List<Widget> actions;
  const DetailMission(
      {super.key, required this.mission, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = mission;
    final d = m.demande;
    final client = '${m.prenomCitoyen ?? ''} ${m.nomCitoyen}'.trim();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
        children: [
          Row(children: [
            FicheNumber(m.id, color: AppColors.ink),
            const Spacer(),
            StatusStamp(FicheStatus.sollicitation(m.statut)),
          ]),
          const SizedBox(height: AppSpace.md),
          if (d != null) ...[
            EnteteService(d),
            const SizedBox(height: AppSpace.md),
            for (final l in d.resumeReponses())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(l, style: AppText.body),
              ),
            const Divider(height: AppSpace.xl),
            _Ligne('Prévu', m.quand),
            if (m.minutesEstimees != null)
              _Ligne('Durée estimée', duree(m.minutesEstimees!)),
            if (m.prixTotal != null)
              _Ligne(
                  m.formule == Formule.abonnement
                      ? 'Prix par mois'
                      : 'Prix fixé par WANDA',
                  fcfa(m.prixTotal!),
                  fort: true),
            _Ligne('Client', client.isEmpty ? 'Client WANDA' : client),
            if (m.photos.isNotEmpty) ...[
              const SectionTitle('Photos du client',
                  padding:
                      EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm)),
              _Photos(chemins: m.photos),
            ],
            const SectionTitle('Vérification des photos',
                padding:
                    EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm)),
            _ResumeIa(m.analyseIa),
          ] else
            Text('Demande sans détail (créée avant les services ménagers).',
                style: AppText.body),
          const SizedBox(height: AppSpace.xl),
          ...actions,
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  final String libelle;
  final String valeur;
  final bool fort;
  const _Ligne(this.libelle, this.valeur, {this.fort = false});

  @override
  Widget build(BuildContext context) {
    if (valeur.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(libelle, style: AppText.caption)),
        Text(valeur,
            style: fort
                ? AppText.number.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)
                : AppText.bodyStrong),
      ]),
    );
  }
}

/// Photos privées : URL signées de courte durée, agrandissables.
class _Photos extends ConsumerStatefulWidget {
  final List<String> chemins;
  const _Photos({required this.chemins});

  @override
  ConsumerState<_Photos> createState() => _PhotosState();
}

class _PhotosState extends ConsumerState<_Photos> {
  late final Future<List<String?>> _urls = _charger();

  Future<List<String?>> _charger() async {
    final repo = ref.read(demandeRepositoryProvider);
    return [
      for (final c in widget.chemins)
        await repo.urlPhoto(c).then<String?>((u) => u).catchError((_) => null),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String?>>(
      future: _urls,
      builder: (context, snap) {
        final urls = snap.data;
        return Row(children: [
          for (var i = 0; i < widget.chemins.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  child: urls == null
                      ? const ColoredBox(color: AppColors.surfaceSunk)
                      : urls[i] == null
                          ? const ColoredBox(
                              color: AppColors.surfaceSunk,
                              child: Icon(Icons.broken_image_outlined,
                                  color: AppColors.inkMuted))
                          : Semantics(
                              button: true,
                              label: 'Agrandir la photo ${i + 1}',
                              child: InkWell(
                                onTap: () => _agrandir(urls[i]!),
                                child: Image.network(urls[i]!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 400,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(
                                            color: AppColors.surfaceSunk)),
                              ),
                            ),
                ),
              ),
            ),
          ],
        ]);
      },
    );
  }

  void _agrandir(String url) => showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpace.md),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ]),
        ),
      );
}

class _ResumeIa extends StatelessWidget {
  final AnalyseIa? analyse;
  const _ResumeIa(this.analyse);

  @override
  Widget build(BuildContext context) {
    final a = analyse;
    if (a == null) {
      return Text(
          'Analyse indisponible : fiez-vous aux réponses et aux photos.',
          style: AppText.body);
    }
    final estimation = [
      if (a.quantiteMin != null)
        a.quantiteMax != null && a.quantiteMax != a.quantiteMin
            ? '${a.quantiteMin} à ${a.quantiteMax}'
            : '${a.quantiteMin}',
      if (a.niveau != null) a.niveau!.replaceAll('_', ' '),
      if (a.nuisible != null) a.nuisible!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            a.photosConformes
                ? 'Photos conformes à la demande'
                : 'Photos peu conformes : ${a.raisonNonConforme ?? ''}',
            style: AppText.bodyStrong),
        if (estimation.isNotEmpty)
          Text('Estimation IA : $estimation', style: AppText.body),
        Text('Confiance : ${(a.confiance * 100).round()} %',
            style: AppText.caption),
        for (final i in a.incoherences)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $i', style: AppText.body),
          ),
      ],
    );
  }
}

/// Formulaire de demande d'ajustement (aucun supplément sur place).
class FormulaireAjustement extends ConsumerStatefulWidget {
  final Sollicitation mission;
  const FormulaireAjustement({super.key, required this.mission});

  @override
  ConsumerState<FormulaireAjustement> createState() =>
      _FormulaireAjustementState();
}

class _FormulaireAjustementState extends ConsumerState<FormulaireAjustement> {
  int _minutes = 30;
  int _produits = 0;
  final _motif = TextEditingController();
  File? _photo;
  bool _envoi = false;
  Tarifs _tarifs = Tarifs.defaut;

  @override
  void initState() {
    super.initState();
    ref.read(tarifRepositoryProvider).charger().then((t) {
      if (mounted) setState(() => _tarifs = t);
    });
  }

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  /// Même calcul que demander_ajustement (011).
  int get _prix => arrondiCentaine(
      (_minutes * _tarifs.v('global', 'tarif_horaire') + 30) ~/ 60 + _produits);

  Future<void> _envoyer() async {
    if (_motif.text.trim().length < 3) {
      showAppSnackBar(context, 'Expliquez en quelques mots ce qui change.');
      return;
    }
    if (_minutes == 0 && _produits == 0) {
      showAppSnackBar(context, 'Indiquez le temps ou les produits en plus.');
      return;
    }
    setState(() => _envoi = true);
    final repo = ref.read(demandeRepositoryProvider);
    try {
      final photos = <String>[
        if (_photo != null)
          await repo.envoyerPhoto(_photo!,
              dossier: 'ajustement-${widget.mission.id}'),
      ];
      await repo.demanderAjustement(
        sollicitationId: widget.mission.id,
        minutes: _minutes,
        produits: _produits,
        motif: _motif.text,
        photos: photos,
      );
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message);
        setState(() => _envoi = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter,
          MediaQuery.viewInsetsOf(context).bottom + AppSpace.xl),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Demander un ajustement', style: AppText.sectionTitle),
            const SizedBox(height: 4),
            Text(
                'Aucun supplément sur place : le client accepte ou refuse '
                'dans l\'application. S\'il refuse, le prix initial reste dû.',
                style: AppText.caption),
            const SizedBox(height: AppSpace.md),
            Compteur(
              libelle: 'Temps en plus',
              aide: duree(_minutes),
              valeur: _minutes,
              max: 240,
              pas: 15,
              onChanged: (v) => setState(() => _minutes = v),
            ),
            Compteur(
              libelle: 'Produits en plus',
              aide: fcfa(_produits),
              valeur: _produits ~/ 500,
              max: 40,
              onChanged: (v) => setState(() => _produits = v * 500),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _motif,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Pourquoi ?',
                hintText: 'Ex. : une chambre de plus que déclaré',
              ),
            ),
            Row(children: [
              TextButton.icon(
                onPressed: _envoi
                    ? null
                    : () async {
                        final x = await ImagePicker().pickImage(
                            source: ImageSource.camera,
                            maxWidth: 1280,
                            imageQuality: 60);
                        if (x != null && mounted) {
                          setState(() => _photo = File(x.path));
                        }
                      },
                icon: Icon(
                    _photo == null
                        ? Icons.add_a_photo_outlined
                        : Icons.check_circle_rounded,
                    size: 20),
                label: Text(_photo == null
                    ? 'Joindre une photo (conseillé)'
                    : 'Photo jointe'),
              ),
            ]),
            const SizedBox(height: AppSpace.md),
            FilledButton(
              onPressed: _envoi ? null : _envoyer,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54)),
              child: Text(
                  _envoi ? 'Envoi…' : 'Envoyer au client : +${fcfa(_prix)}'),
            ),
          ],
        ),
      ),
    );
  }
}
