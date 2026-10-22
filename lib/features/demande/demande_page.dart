// demande_page.dart
// -----------------------------------------------------------------------------
// Réserver un service ménager, en 4 étapes courtes :
//   1. formule (une fois / abonnement)   2. détails (questionnaire)
//   3. photos + vérification IA          4. récapitulatif et réservation
// Le prix s'affiche en direct (calcul Dart, miroir du SQL) ; au
// récapitulatif, c'est le prix calculé par le serveur qui est affiché et
// enregistré. L'IA ne bloque jamais : sans elle, le prix vient des réponses.
// -----------------------------------------------------------------------------

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/status_views.dart';
import '../../data/models/analyse_ia.dart';
import '../../data/models/avis_prestataire.dart';
import '../../data/models/categorie_service.dart';
import '../../data/models/citoyen.dart';
import '../../data/models/demande_menage.dart';
import '../../data/models/particulier.dart';
import '../../data/pricing/tarification.dart';
import 'composants.dart';
import 'questionnaires.dart';

/// Ce qu'on passe à l'écran (route `/citoyen/demande`, `extra`).
class DemandeArgs {
  final CategorieService service;

  /// Prestataire déjà choisi (depuis sa fiche) : pas de choix à la fin.
  final Particulier? prestataire;

  /// Reprise d'une demande refusée : réponses et photos conservées, on
  /// arrive directement au récapitulatif pour choisir un autre prestataire.
  final DemandeMenage? reprise;
  final List<String> photosEnvoyees;
  final String? analyseId;

  const DemandeArgs(
    this.service, {
    this.prestataire,
    this.reprise,
    this.photosEnvoyees = const [],
    this.analyseId,
  });
}

class DemandePage extends ConsumerStatefulWidget {
  final DemandeArgs args;
  const DemandePage({super.key, required this.args});

  @override
  ConsumerState<DemandePage> createState() => _DemandePageState();
}

class _DemandePageState extends ConsumerState<DemandePage> {
  static const _etapes = ['Formule', 'Détails', 'Photos', 'Réserver'];
  static const _titres = [
    'Quelle formule ?',
    'Décrivez votre besoin',
    'Ajoutez des photos',
    'Vérifiez et réservez',
  ];
  static const _maxPhotos = 3;

  late DemandeMenage _demande;
  int _etape = 1;
  Tarifs _tarifs = Tarifs.defaut;

  // Étape 3
  final List<File> _photos = [];
  List<String> _chemins = const [];
  bool _verification = false;
  bool _verifiee = false;
  AnalyseIa? _analyse;
  CorrectionIa? _correction;

  // Étape 4
  EstimationPrix? _prixServeur;
  bool _prixEnCours = false;
  String? _erreurPrix;
  List<Particulier>? _prestataires;
  String? _erreurPrestataires;
  Particulier? _choisi;
  Map<String, RatingSummary> _notes = const {};
  Position? _position;
  late DateTime _date;
  Creneau _creneau = Creneau.matin;
  bool _reservation = false;

  /// Profil du client : un compte tout juste créé par WhatsApp n'a pas
  /// encore de nom, exigé par le serveur pour réserver. On le demande ici
  /// plutôt que d'échouer à la dernière étape.
  Citoyen? _citoyen;
  final _nom = TextEditingController();
  bool get _nomManquant => _citoyen != null && _citoyen!.nom.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    final a = widget.args;
    _demande = a.reprise ?? DemandeMenage.initiale(a.service);
    _choisi = a.prestataire;
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day + 1);
    _chargerTarifs();
    if (a.reprise != null && a.photosEnvoyees.isNotEmpty) {
      _chemins = a.photosEnvoyees;
      _verifiee = true;
      _analyse = a.analyseId == null ? null : AnalyseIa(id: a.analyseId);
      _etape = 4;
      _preparerRecap();
    }
  }

  Future<void> _chargerTarifs() async {
    final t = await ref.read(tarifRepositoryProvider).charger();
    if (mounted) setState(() => _tarifs = t);
  }

  EstimationPrix get _estimation => calculerPrix(_demande, _tarifs);

  void _maj(DemandeMenage d) => setState(() {
        _demande = d;
        _prixServeur = null;
      });

  // ---------------------------------------------------------------- navigation

  void _suivant() {
    switch (_etape) {
      case 1:
        if (!_demande.formuleComplete) {
          showAppSnackBar(context, 'Choisissez le rythme de l\'abonnement.');
          return;
        }
      case 2:
        final manque = manqueQuestionnaire(_demande);
        if (manque != null) {
          showAppSnackBar(context, manque);
          return;
        }
      case 3:
        if (_photos.isEmpty && _chemins.isEmpty) {
          _prendrePhoto(ImageSource.camera);
          return;
        }
        if (!_verifiee) {
          _verifierPhotos();
          return;
        }
        setState(() => _etape = 4);
        _preparerRecap();
        return;
      case 4:
        _reserver();
        return;
    }
    setState(() => _etape++);
  }

  void _precedent() {
    if (_etape > 1 && !_verification && !_reservation) {
      setState(() => _etape--);
    }
  }

  // ------------------------------------------------------------------- photos

  Future<void> _prendrePhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) return;
    try {
      // Compression avant envoi (réseau lent, Android modestes).
      final x = await ImagePicker().pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 60);
      if (x == null || !mounted) return;
      setState(() {
        _photos.add(File(x.path));
        _reinitialiserVerification();
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Impossible d\'ouvrir l\'appareil photo.');
      }
    }
  }

  void _retirerPhoto(int i) => setState(() {
        _photos.removeAt(i);
        _reinitialiserVerification();
      });

  void _reinitialiserVerification() {
    _chemins = const [];
    _verifiee = false;
    _analyse = null;
    _correction = null;
  }

  /// Envoie les photos (dossier privé) puis demande l'analyse IA.
  Future<void> _verifierPhotos() async {
    setState(() => _verification = true);
    final repo = ref.read(demandeRepositoryProvider);
    try {
      if (_chemins.isEmpty) {
        final dossier = 'demande-${DateTime.now().millisecondsSinceEpoch}';
        final chemins = <String>[];
        for (final p in _photos) {
          chemins.add(await repo.envoyerPhoto(p, dossier: dossier));
        }
        _chemins = chemins;
      }
      final analyse = await repo.analyser(_demande, _chemins);
      if (!mounted) return;
      setState(() {
        _analyse = analyse;
        _correction = analyse == null
            ? null
            : comparerAvecIa(_demande, analyse,
                seuilPourcent: _tarifs.v('global', 'seuil_ecart_ia'));
        _verifiee = true;
      });
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _verification = false);
    }
  }

  // ------------------------------------------------------------ récapitulatif

  Future<void> _preparerRecap() async {
    _chargerPrixServeur();
    if (_choisi == null && _prestataires == null) _chargerPrestataires();
    _chargerProfil();
  }

  Future<void> _chargerProfil() async {
    final uid = ref.read(authRepositoryProvider).currentUserId;
    if (uid == null || _citoyen != null) return;
    try {
      final c = await ref.read(profileRepositoryProvider).fetchCitoyen(uid);
      if (mounted && c != null) setState(() => _citoyen = c);
    } on AppException catch (_) {
      // Le serveur redira ce qui manque au moment de réserver.
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _chargerPrixServeur() async {
    setState(() {
      _prixEnCours = true;
      _erreurPrix = null;
    });
    try {
      await _chargerTarifs();
      final p = await ref.read(demandeRepositoryProvider).prixServeur(_demande);
      if (mounted) setState(() => _prixServeur = p);
    } on AppException catch (e) {
      if (mounted) setState(() => _erreurPrix = e.message);
    } finally {
      if (mounted) setState(() => _prixEnCours = false);
    }
  }

  Future<void> _chargerPrestataires() async {
    setState(() => _erreurPrestataires = null);
    try {
      final liste = await ref
          .read(prestataireRepositoryProvider)
          .disponiblesPour(_demande.service.code);
      if (!mounted) return;
      // La liste s'affiche tout de suite ; notes et distances complètent.
      setState(() {
        _prestataires = _parDistance(liste, _position);
        if (liste.length == 1) _choisi = liste.first;
      });
      _completerPrestataires(liste);
    } on AppException catch (e) {
      if (mounted) setState(() => _erreurPrestataires = e.message);
    }
  }

  Future<void> _completerPrestataires(List<Particulier> liste) async {
    try {
      final notes = await ref
          .read(avisRepositoryProvider)
          .averagesForPrestataires([for (final p in liste) p.id]);
      if (mounted) setState(() => _notes = notes);
    } catch (_) {
      // Les notes s'afficheront « Nouveau ».
    }
    try {
      final pos = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(seconds: 3));
      if (pos != null && mounted) {
        setState(() {
          _position = pos;
          _prestataires = _parDistance(liste, pos);
        });
      }
    } catch (_) {
      // Sans position : pas de tri par distance.
    }
  }

  double? _distance(Particulier p, [Position? pos]) {
    final me = pos ?? _position;
    if (me == null || p.latitude == null || p.longitude == null) return null;
    return Geolocator.distanceBetween(
        me.latitude, me.longitude, p.latitude!, p.longitude!);
  }

  List<Particulier> _parDistance(List<Particulier> l, Position? pos) =>
      [...l]..sort((a, b) => (_distance(a, pos) ?? double.infinity)
          .compareTo(_distance(b, pos) ?? double.infinity));

  Future<void> _reserver() async {
    final prestataire = _choisi;
    if (prestataire == null) {
      showAppSnackBar(context, 'Choisissez un prestataire.');
      return;
    }
    if (_prixServeur == null) {
      _chargerPrixServeur();
      return;
    }
    if (_nomManquant && _nom.text.trim().length < 2) {
      showAppSnackBar(context, 'Indiquez votre nom pour le prestataire.');
      return;
    }
    setState(() => _reservation = true);
    try {
      final c = _citoyen;
      if (c != null && _nomManquant) {
        await ref.read(profileRepositoryProvider).updateCitoyen(Citoyen(
              citoyenId: c.citoyenId,
              nom: _nom.text.trim(),
              prenom: c.prenom,
              email: c.email,
              telephone: c.telephone,
            ));
        _citoyen = Citoyen(
            citoyenId: c.citoyenId,
            nom: _nom.text.trim(),
            prenom: c.prenom,
            email: c.email,
            telephone: c.telephone);
      }
      await ref.read(demandeRepositoryProvider).creer(
            prestataireId: prestataire.id,
            demande: _demande,
            photos: _chemins,
            analyseId: _analyse?.id,
            date: _date,
            creneau: _creneau,
          );
      if (!mounted) return;
      showAppSnackBar(context,
          'Demande envoyée à ${prestataire.prenom.isNotEmpty ? prestataire.prenom : 'votre prestataire'}.',
          isError: false);
      context.pop(true);
    } on AppException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message);
        setState(() => _reservation = false);
      }
    }
  }

  // ------------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final style = ServiceStyle.ofCategorie(_demande.service);
    return PopScope(
      canPop: _etape == 1 && !_reservation,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _precedent();
      },
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Letterhead(
              showBack: true,
              onBack: _etape > 1 ? _precedent : null,
              overline: '${style.label} · étape $_etape sur 4',
              title: _titres[_etape - 1],
              bottom: PisteEtapes(libelles: _etapes, etape: _etape),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xl),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: const Threshold(1),
                child: KeyedSubtree(
                  key: ValueKey(_etape),
                  child: switch (_etape) {
                    1 => QuestionsFormule(demande: _demande, onChanged: _maj),
                    2 => QuestionsService(
                        demande: _demande, tarifs: _tarifs, onChanged: _maj),
                    3 => _etapePhotos(),
                    _ => _etapeRecap(),
                  },
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _barre(),
      ),
    );
  }

  Widget _barre() {
    final (action, icone) = switch (_etape) {
      3 when _photos.isEmpty && _chemins.isEmpty => (
          'Prendre une photo',
          Icons.photo_camera_rounded
        ),
      3 when !_verifiee => ('Vérifier les photos', Icons.fact_check_rounded),
      4 => ('Réserver', Icons.check_rounded),
      _ => ('Continuer', Icons.arrow_forward_rounded),
    };
    final serveur = _etape == 4 ? _prixServeur : null;
    return BarrePrix(
      estimation: serveur ?? _estimation,
      confirme: serveur != null,
      action: action,
      icone: icone,
      chargement:
          _verification || _reservation || (_etape == 4 && _prixEnCours),
      onPressed: _suivant,
    );
  }

  // ----------------------------------------------------------- étape 3 : photos

  Widget _etapePhotos() {
    final style = ServiceStyle.ofCategorie(_demande.service);
    final nb = _photos.isNotEmpty ? _photos.length : _chemins.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(consignePhotos(_demande.service), style: AppText.body),
        const SizedBox(height: 4),
        Text(
            'Obligatoire : au moins une photo, trois au plus. Elles restent '
            'privées : seul le prestataire choisi les verra.',
            style: AppText.caption),
        const SizedBox(height: AppSpace.lg),
        Row(children: [
          for (var i = 0; i < _maxPhotos; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: i < _photos.length
                    ? _VignettePhoto(
                        fichier: _photos[i],
                        onRetirer:
                            _verification ? null : () => _retirerPhoto(i),
                      )
                    : i < nb
                        ? const _VignetteEnvoyee()
                        : _CaseVide(
                            encre: style.ink,
                            onTap: _verification || _photos.length != i
                                ? null
                                : () => _prendrePhoto(ImageSource.camera),
                          ),
              ),
            ),
          ],
        ]),
        if (_photos.length < _maxPhotos && !_verification)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _prendrePhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Choisir dans la galerie'),
            ),
          ),
        const SizedBox(height: AppSpace.md),
        if (_verification)
          const _Info(
            icone: Icons.hourglass_top_rounded,
            texte: 'Envoi et vérification des photos… Cela peut prendre '
                'quelques secondes.',
            chargement: true,
          )
        else if (_verifiee)
          _resultatIa(),
      ],
    );
  }

  Widget _resultatIa() {
    final a = _analyse;
    if (a == null) {
      return const _Info(
        icone: Icons.info_outline_rounded,
        texte: 'Vérification des photos indisponible pour le moment : le prix '
            'est calculé sur vos réponses. Le prestataire verra vos photos.',
      );
    }
    if (!a.photosConformes) {
      return _Carte(
        icone: Icons.image_not_supported_outlined,
        encre: AppColors.progress,
        titre: 'Ces photos ne semblent pas correspondre',
        texte: a.raisonNonConforme ??
            'Reprenez-les si possible : elles aident le prestataire à '
                'préparer son passage.',
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _photos.clear();
              _reinitialiserVerification();
            }),
            child: const Text('Reprendre les photos'),
          ),
        ],
      );
    }
    final c = _correction;
    if (c != null) {
      final nouveau = calculerPrix(c.corrigee, _tarifs);
      return _Carte(
        icone: Icons.auto_awesome_rounded,
        encre: AppColors.stampViolet,
        titre: 'Les photos montrent plus que déclaré',
        texte: '${c.explication} Corriger votre demande évite un ajustement '
            'de prix sur place.',
        actions: [
          FilledButton(
            onPressed: () => setState(() {
              _demande = c.corrigee;
              _correction = null;
            }),
            child: Text('Corriger (${fcfa(nouveau.prixTotal)})'),
          ),
          TextButton(
            onPressed: () => setState(() => _correction = null),
            child: const Text('Garder ma déclaration'),
          ),
        ],
      );
    }
    return _Carte(
      icone: Icons.verified_outlined,
      encre: AppColors.done,
      titre: 'Photos vérifiées',
      texte: a.incoherences.isEmpty
          ? 'Elles correspondent à votre demande.'
          : a.incoherences.join('\n'),
    );
  }

  // ----------------------------------------------------- étape 4 : récap

  Widget _etapeRecap() {
    final prix = _prixServeur;
    final lignes = (prix == null || !prix.memePrix(_estimation))
        ? null
        : _estimation.lignes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnteteService(_demande),
              const Divider(height: AppSpace.xl),
              for (final l in _demande.resumeReponses())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(l, style: AppText.body),
                ),
              if (_chemins.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      '${_chemins.length} photo${_chemins.length > 1 ? 's' : ''} jointe${_chemins.length > 1 ? 's' : ''}',
                      style: AppText.body),
                ),
              const Divider(height: AppSpace.xl),
              if (_prixEnCours && prix == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              else if (_erreurPrix != null)
                ErrorStateView(
                    message: _erreurPrix!, onRetry: _chargerPrixServeur)
              else if (prix != null) ...[
                if (lignes != null) DetailPrix(_estimation),
                const SizedBox(height: AppSpace.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                          prix.passages > 1
                              ? 'Prix fixé par WANDA, par mois'
                              : 'Prix fixé par WANDA',
                          style: AppText.label),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    // Montant insécable : il rétrécit plutôt que déborder.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(fcfa(prix.prixTotal),
                            style: AppText.number.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    'Aucun supplément sur place : si le travail est plus '
                    'important, le prestataire vous demande un ajustement dans '
                    "l'application, que vous acceptez ou non.",
                    style: AppText.caption),
              ],
            ],
          ),
        ),
        if (_nomManquant) ...[
          const SectionTitle('Votre nom',
              padding: EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.sm)),
          Text(
              'Transmis au prestataire avec votre numéro, pour qu\'il vous '
              'reconnaisse à son arrivée.',
              style: AppText.caption),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Nom',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
          ),
        ],
        const SectionTitle('Quand ?',
            padding: EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.md)),
        _choixDate(),
        const SizedBox(height: AppSpace.md),
        SegmentedButton<Creneau>(
          showSelectedIcon: false,
          style:
              SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          segments: [
            for (final c in Creneau.values)
              ButtonSegment(value: c, label: Text(c.libelle)),
          ],
          selected: {_creneau},
          onSelectionChanged: (s) => setState(() => _creneau = s.first),
        ),
        const SectionTitle('Votre prestataire',
            padding: EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.md)),
        _choixPrestataire(),
      ],
    );
  }

  Widget _choixDate() {
    const jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    final aujourdhui = DateTime.now();
    final debut = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final d = DateTime(debut.year, debut.month, debut.day + i);
          final choisi = d == _date;
          final haut = switch (i) {
            0 => "Aujourd'hui",
            1 => 'Demain',
            _ => jours[d.weekday - 1],
          };
          return Semantics(
            selected: choisi,
            button: true,
            child: Material(
              color: choisi ? AppColors.greenTint : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                side: BorderSide(
                    color: choisi ? AppColors.letterhead : AppColors.rule,
                    width: choisi ? 2 : 1),
              ),
              child: InkWell(
                onTap: () => setState(() => _date = d),
                borderRadius: BorderRadius.circular(AppRadius.field),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(haut, style: AppText.caption),
                        Text('${d.day}/${d.month.toString().padLeft(2, '0')}',
                            style: AppText.number.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: choisi
                                    ? AppColors.letterheadDeep
                                    : AppColors.ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _choixPrestataire() {
    final fixe = widget.args.prestataire;
    if (fixe != null) {
      return _CartePrestataire(
          p: fixe,
          note: _notes[fixe.id] ?? RatingSummary.empty,
          distance: _distance(fixe),
          choisi: true,
          onTap: null);
    }
    if (_erreurPrestataires != null) {
      return ErrorStateView(
          message: _erreurPrestataires!, onRetry: _chargerPrestataires);
    }
    final liste = _prestataires;
    if (liste == null) return const LoadingView();
    if (liste.isEmpty) {
      return EmptyStateView(
        icon: Icons.person_search_rounded,
        title: 'Personne en ligne pour ce service',
        subtitle:
            'Réessayez un peu plus tard : les prestataires se connectent tout au long de la journée.',
        action: OutlinedButton(
            onPressed: _chargerPrestataires, child: const Text('Actualiser')),
      );
    }
    return Column(children: [
      for (final p in liste) ...[
        _CartePrestataire(
          p: p,
          note: _notes[p.id] ?? RatingSummary.empty,
          distance: _distance(p),
          choisi: _choisi?.id == p.id,
          onTap: () => setState(() => _choisi = p),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------

class _VignettePhoto extends StatelessWidget {
  final File fichier;
  final VoidCallback? onRetirer;
  const _VignettePhoto({required this.fichier, this.onRetirer});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Image.file(fichier, fit: BoxFit.cover, cacheWidth: 360),
      ),
      if (onRetirer != null)
        Positioned(
          top: 4,
          right: 4,
          child: IconButton.filled(
            onPressed: onRetirer,
            tooltip: 'Retirer la photo',
            style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.ink),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ),
    ]);
  }
}

class _VignetteEnvoyee extends StatelessWidget {
  const _VignetteEnvoyee();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.greenTint,
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: const Center(
          child: Icon(Icons.image_rounded, color: AppColors.letterheadDeep),
        ),
      );
}

class _CaseVide extends StatelessWidget {
  final Color encre;
  final VoidCallback? onTap;
  const _CaseVide({required this.encre, this.onTap});

  @override
  Widget build(BuildContext context) {
    final actif = onTap != null;
    return Semantics(
      button: actif,
      label: actif ? 'Prendre une photo' : null,
      child: Material(
        color: AppColors.surfaceSunk,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          side:
              BorderSide(color: actif ? AppColors.ruleStrong : AppColors.rule),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Center(
            child: Icon(Icons.add_a_photo_outlined,
                color: actif ? encre : AppColors.inkMuted, size: 28),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icone;
  final String texte;
  final bool chargement;
  const _Info(
      {required this.icone, required this.texte, this.chargement = false});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      chargement
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icone, size: 20, color: AppColors.inkSoft),
      const SizedBox(width: AppSpace.md),
      Expanded(child: Text(texte, style: AppText.body)),
    ]);
  }
}

class _Carte extends StatelessWidget {
  final IconData icone;
  final Color encre;
  final String titre;
  final String texte;
  final List<Widget> actions;
  const _Carte({
    required this.icone,
    required this.encre,
    required this.titre,
    required this.texte,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: FicheCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icone, color: encre, size: 24),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre,
                        style: AppText.cardTitle.copyWith(color: encre)),
                    const SizedBox(height: 2),
                    Text(texte, style: AppText.body),
                  ],
                ),
              ),
            ]),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartePrestataire extends StatelessWidget {
  final Particulier p;
  final RatingSummary note;
  final double? distance;
  final bool choisi;
  final VoidCallback? onTap;
  const _CartePrestataire({
    required this.p,
    required this.note,
    required this.distance,
    required this.choisi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nom = '${p.prenom} ${p.nom}'.trim();
    return Semantics(
      selected: choisi,
      button: onTap != null,
      child: Material(
        color: choisi ? AppColors.greenTint : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
              color: choisi ? AppColors.letterhead : AppColors.rule,
              width: choisi ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(children: [
              IdPhoto(
                  url: p.photoProUrl,
                  size: 52,
                  tint: ServiceStyle.ofServices(p.services).tint),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(nom.isEmpty ? 'Prestataire' : nom,
                            style: AppText.cardTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (p.identiteVerifiee) ...[
                        const SizedBox(width: 4),
                        const VerifiedMark(size: 16),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: AppSpace.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RatingInline(note),
                        if (distance != null)
                          Text(distanceLabel(distance!),
                              style: AppText.number.copyWith(
                                  fontSize: 14, color: AppColors.inkSoft)),
                      ],
                    ),
                  ],
                ),
              ),
              if (choisi)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.letterhead),
            ]),
          ),
        ),
      ),
    );
  }
}
