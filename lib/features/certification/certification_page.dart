// certification_page.dart
// -----------------------------------------------------------------------------
// Certification FACULTATIVE du compte artisan, depuis son profil :
//   présentation → recto CNI → verso CNI → selfie → consentement & envoi.
// Récompense : le badge « Identité vérifiée » visible des citoyens, une fois
// la pièce validée par un administrateur WANDA.
// Le scan (texte + visages) se fait sur le téléphone avec Google ML Kit.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/error/app_exception.dart';
import '../../core/identity/cni_parser.dart';
import '../../core/identity/identity_scanner.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/city_backdrop.dart';

/// Version et texte exacts du consentement : enregistrés tels quels avec la
/// vérification (preuve en cas de litige). Changer le texte = changer la
/// version.
const kConsentVersion = 'cni-v1-2026-10';
const kConsentText =
    "J'accepte que WANDA conserve une copie de ma carte nationale d'identité "
    "(recto et verso), mon selfie et les informations qui y figurent (nom, "
    "prénoms, date de naissance, numéro et date d'expiration de la carte). "
    "Ces données servent uniquement à certifier mon identité et à pouvoir "
    "m'identifier en cas de litige avec un client. Elles sont stockées dans "
    "un espace privé, accessible seulement à l'équipe de vérification WANDA, "
    "pendant toute la durée de mon compte puis 5 ans après sa fermeture. "
    "Je peux demander à y accéder ou à les faire rectifier en contactant "
    "WANDA.";

enum _Step { intro, recto, verso, selfie, consent }

class CertificationPage extends ConsumerStatefulWidget {
  const CertificationPage({super.key});

  @override
  ConsumerState<CertificationPage> createState() => _CertificationPageState();
}

class _CertificationPageState extends ConsumerState<CertificationPage> {
  final _scanner = IdentityScanner();
  final _picker = ImagePicker();

  static const _steps = _Step.values;
  int _index = 0;
  _Step get _step => _steps[_index];

  File? _recto, _verso, _selfie;
  ScanResult<CniFront>? _rectoResult;
  ScanResult<CniMrz>? _versoResult;
  ScanResult<Face>? _selfieResult;
  bool _noMrz = false; // ancienne carte sans code au verso
  bool _analysing = false;
  bool _consent = false;
  bool _submitting = false;
  bool _done = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  // ================= DONNÉES LUES =================

  CniFront? get _front => _rectoResult?.data;
  CniMrz? get _mrz =>
      _versoResult?.accepted == true ? _versoResult!.data : null;

  /// La MRZ (contrôlée par ses chiffres) prime sur le recto.
  String get _nom {
    final mrz = _mrz;
    if (mrz != null && mrz.nom.isNotEmpty) return mrz.nom;
    return _front?.nom ?? '';
  }

  String get _prenoms {
    final mrz = _mrz;
    if (mrz != null && mrz.prenoms.isNotEmpty) return mrz.prenoms;
    return _front?.prenoms ?? '';
  }

  DateTime? get _birthDate => _mrz?.dateNaissance ?? _front?.dateNaissance;

  // ================= CAPTURE & ANALYSE =================

  Future<void> _capture(_Step step) async {
    final isSelfie = step == _Step.selfie;
    final XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice:
            isSelfie ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 92,
        maxWidth: isSelfie ? 1400 : 2400,
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, "Impossible d'ouvrir l'appareil photo.");
      }
      return;
    }
    if (shot == null) return;
    final file = File(shot.path);
    setState(() => _analysing = true);
    try {
      switch (step) {
        case _Step.recto:
          final r = await _scanner.scanRecto(file);
          setState(() {
            _recto = file;
            _rectoResult = r;
          });
        case _Step.verso:
          final r = await _scanner.scanVerso(file, recto: _front);
          setState(() {
            _verso = file;
            _versoResult = r;
            if (r.accepted) _noMrz = false;
          });
        case _Step.selfie:
          final r = await _scanner.checkSelfie(file);
          setState(() {
            _selfie = file;
            _selfieResult = r;
          });
        default:
          break;
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, "L'analyse de la photo a échoué. Réessayez.");
      }
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  // ================= NAVIGATION =================

  bool get _canContinue => switch (_step) {
        _Step.intro => true,
        _Step.recto => _rectoResult?.accepted ?? false,
        _Step.verso =>
          (_versoResult?.accepted ?? false) || (_noMrz && _verso != null),
        _Step.selfie => _selfieResult?.accepted ?? false,
        _Step.consent => _consent && !_submitting,
      };

  Future<void> _next() async {
    if (_step == _Step.consent) {
      await _submit();
      return;
    }
    setState(() => _index++);
  }

  void _back() {
    if (_index == 0 || _done) {
      context.pop(_done);
    } else {
      setState(() => _index--);
    }
  }

  // ================= ENVOI =================

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final userId = ref.read(authRepositoryProvider).currentUserId ??
          (throw const AppException('Session expirée : reconnectez-vous.'));
      await ref.read(verificationRepositoryProvider).submit(
            userId: userId,
            recto: _recto!,
            verso: _verso!,
            selfie: _selfie!,
            nom: _nom,
            prenoms: _prenoms,
            saisieCorrigee: false,
            front: _front!,
            mrz: _mrz,
            consentementAt: DateTime.now(),
            consentementVersion: kConsentVersion,
            consentementTexte: kConsentText,
          );
      if (mounted) setState(() => _done = true);
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ================= UI =================

  static const _titles = {
    _Step.intro: 'Certifier mon compte',
    _Step.recto: 'Recto de votre CNI',
    _Step.verso: 'Verso de votre CNI',
    _Step.selfie: 'Un selfie',
    _Step.consent: 'Dernière étape',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0 || _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting) _back();
      },
      child: Scaffold(
        body: Column(children: [
          _buildHeader(),
          Expanded(
            // L'en-tête gère déjà la barre d'état : pas de marge en double.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: const Threshold(1),
                // Étapes alignées en haut (par défaut elles seraient centrées).
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, if (current != null) current],
                ),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0.06, 0), end: Offset.zero)
                            .animate(a),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_done ? 'done' : _step),
                  child: _done ? _buildDone() : _buildStep(),
                ),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _done ? null : _buildBottomBar(),
      ),
    );
  }

  Widget _buildHeader() {
    final topInset = MediaQuery.paddingOf(context).top;
    final total = _steps.length - 1; // l'intro ne compte pas
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: SizedBox(
        height: topInset + 150,
        child: Stack(fit: StackFit.expand, children: [
          const CityBackdrop(images: ['assets/images/city3.jpg']),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.gutter - 8,
                topInset + AppSpace.sm, AppSpace.gutter, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                    onPressed: _submitting ? null : _back,
                    tooltip: _index == 0 ? 'Fermer' : 'Étape précédente',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(_index == 0 || _done
                        ? Icons.close_rounded
                        : Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    _done
                        ? 'Demande envoyée'
                        : _index == 0
                            ? 'Badge de confiance'
                            : 'Étape $_index sur $total',
                    style: AppText.label
                        .copyWith(color: AppColors.onLetterheadSoft),
                  ),
                ]),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  // Une seule ligne : réduit légèrement si l'écran est étroit.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _done ? 'Merci !' : _titles[_step]!,
                      maxLines: 1,
                      style: AppText.heading.copyWith(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                if (!_done)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: List.generate(total, (i) {
                        final active = i < _index;
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 4,
                            margin:
                                EdgeInsets.only(right: i < total - 1 ? 6 : 0),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.brandLeaf
                                  : Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const Positioned(
              left: 0, right: 0, bottom: 0, child: PerforatedEdge()),
        ]),
      ),
    );
  }

  Widget _buildStep() {
    final content = switch (_step) {
      _Step.intro => _buildIntro(),
      _Step.recto => _buildCapture(
          step: _Step.recto,
          file: _recto,
          result: _rectoResult,
          frameIcon: Icons.badge_outlined,
          hint: 'Le côté avec votre photo et vos noms.',
          tips: const [
            'Posez la carte à plat sur une surface sombre',
            'Toute la carte dans le cadre, sans doigt sur le texte',
            'En pleine lumière, sans reflet sur la photo',
          ],
        ),
      _Step.verso => _buildCapture(
          step: _Step.verso,
          file: _verso,
          result: _versoResult,
          frameIcon: Icons.qr_code_2_rounded,
          hint: 'Le côté avec les lignes « <<< » en bas.',
          tips: const [
            'Les 3 lignes de code en bas doivent être nettes',
            'Même carte que le recto',
            'Pas de reflet sur le code',
          ],
          footer: _buildNoMrzOption(),
        ),
      _Step.selfie => _buildCapture(
          step: _Step.selfie,
          file: _selfie,
          result: _selfieResult,
          frameIcon: Icons.face_retouching_natural_rounded,
          hint: 'Il permet de vérifier que la carte est bien la vôtre.',
          tips: const [
            'Visage de face, bien éclairé',
            'Sans lunettes de soleil, casquette ni masque',
            'Seul sur la photo',
          ],
          round: true,
        ),
      _Step.consent => _buildConsent(),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xl),
      child: content,
    );
  }

  // ---------- Présentation ----------

  Widget _buildIntro() {
    Widget item(
            IconData icon, Color tint, Color ink, String title, String text) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: tint, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: ink),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.cardTitle),
                  const SizedBox(height: 2),
                  Text(text, style: AppText.caption),
                ],
              ),
            ),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Le bénéfice d'abord : le badge tel que les citoyens le verront.
        FicheCard(
          color: AppColors.greenTint,
          child: Row(children: [
            const Icon(Icons.verified_rounded, color: AppColors.done, size: 36),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Badge « Identité vérifiée »',
                      style: AppText.cardTitle
                          .copyWith(color: AppColors.letterheadDeep)),
                  const SizedBox(height: 2),
                  Text(
                      'Affiché sur votre fiche : les citoyens choisissent plus volontiers un prestataire certifié.',
                      style: AppText.caption
                          .copyWith(color: AppColors.letterheadDeep)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.xl),
        Text('Facultatif · environ 2 minutes avec votre CNI.',
            style: AppText.body),
        const SizedBox(height: AppSpace.lg),
        item(
            Icons.badge_rounded,
            const Color(0xFFD8E7F8),
            const Color(0xFF1B4F8C),
            'Photo de votre CNI',
            'Recto et verso, lus automatiquement.'),
        item(
            Icons.face_rounded,
            const Color(0xFFF6D8DF),
            const Color(0xFF8E2F4C),
            'Un selfie',
            'Pour confirmer que la carte est bien la vôtre.'),
        item(
            Icons.lock_person_rounded,
            AppColors.surfaceSunk,
            AppColors.inkSoft,
            'Des informations figées',
            'Ensuite, vos nom, prénom et numéro ne pourront plus être modifiés, et vos services ne pourront plus être retirés : vérifiez-les avant de commencer.'),
        const SizedBox(height: AppSpace.md),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: AppColors.rule),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_rounded,
                color: AppColors.letterheadDeep, size: 20),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                'Vos pièces sont analysées sur votre téléphone puis stockées dans un espace privé. Elles ne sont jamais montrées aux clients.',
                style: AppText.caption.copyWith(color: AppColors.ink),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  // ---------- Recto / verso / selfie ----------

  Widget _buildCapture({
    required _Step step,
    required File? file,
    required ScanResult? result,
    required IconData frameIcon,
    required String hint,
    required List<String> tips,
    bool round = false,
    Widget? footer,
  }) {
    final accepted = result?.accepted ?? false;
    final frameColor = result == null
        ? AppColors.ruleStrong
        : accepted
            ? AppColors.done
            : AppColors.danger;

    final frame = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunk,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(AppRadius.card),
        border: Border.all(color: frameColor, width: result == null ? 1.5 : 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (file != null)
          Image.file(file, fit: BoxFit.cover)
        else
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(frameIcon, size: 52, color: AppColors.inkMuted),
            const SizedBox(height: AppSpace.sm),
            Text('Touchez pour prendre la photo', style: AppText.label),
          ]),
        if (_analysing)
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.45),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: AppSpace.md),
                Text('Analyse en cours…',
                    style: AppText.label.copyWith(color: Colors.white)),
              ],
            ),
          ),
      ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hint, style: AppText.body),
        const SizedBox(height: AppSpace.lg),
        Center(
          child: GestureDetector(
            onTap: _analysing ? null : () => _capture(step),
            child: round
                ? SizedBox.square(dimension: 240, child: frame)
                : AspectRatio(aspectRatio: 85.6 / 54, child: frame),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (result == null)
          ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_rounded,
                      size: 18, color: AppColors.letterhead),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(t, style: AppText.body)),
                ]),
              ))
        else ...[
          FicheCard(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in result.checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Icon(
                        c.ok
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 20,
                        color: c.ok ? AppColors.done : AppColors.danger,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text(c.label, style: AppText.bodyStrong)),
                    ]),
                  ),
                if (result.problem != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: AppColors.dangerTint,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: Text(result.problem!,
                        style: AppText.body.copyWith(color: AppColors.danger)),
                  ),
                ],
                if (accepted && step != _Step.selfie) ...[
                  const SizedBox(height: AppSpace.sm),
                  _readSummary(step),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _analysing ? null : () => _capture(step),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reprendre la photo'),
            ),
          ),
        ],
        if (footer != null) footer,
      ],
    );
  }

  /// Ce qui a été lu, pour que l'artisan le voie tout de suite.
  Widget _readSummary(_Step step) {
    final fmt = DateFormat('dd/MM/yyyy');
    final lines = <(String, String)>[
      if (step == _Step.recto) ...[
        ('Nom', _front?.nom ?? '—'),
        ('Prénoms', _front?.prenoms ?? '—'),
        if (_front?.dateNaissance != null)
          ('Né(e) le', fmt.format(_front!.dateNaissance!)),
      ],
      if (step == _Step.verso && _mrz != null) ...[
        ('N° de carte', _mrz!.numeroDocument),
        if (_mrz!.dateExpiration != null)
          ('Valide jusqu\'au', fmt.format(_mrz!.dateExpiration!)),
      ],
    ];
    return Column(
      children: [
        const Divider(),
        for (final (k, v) in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 110, child: Text(k, style: AppText.caption)),
              Expanded(
                child: Text(v,
                    style: AppText.number
                        .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
      ],
    );
  }

  /// Anciennes CNI sans code au verso : on accepte la photo, la revue
  /// manuelle fera le contrôle.
  Widget _buildNoMrzOption() {
    final failed = _versoResult != null && !_versoResult!.accepted;
    if (!failed) return const SizedBox.shrink();
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _noMrz,
      onChanged: (v) => setState(() => _noMrz = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text('Ma carte n\'a pas de lignes « <<< » au verso',
          style: AppText.bodyStrong),
      subtitle: Text('Ancien modèle : votre carte sera vérifiée manuellement.',
          style: AppText.caption),
    );
  }

  // ---------- Consentement & récapitulatif ----------

  Widget _buildConsent() {
    final fmt = DateFormat('dd/MM/yyyy');
    final rows = <(String, String)>[
      ('Nom', _nom.isNotEmpty ? _nom : '—'),
      ('Prénoms', _prenoms.isNotEmpty ? _prenoms : '—'),
      if (_birthDate != null) ('Né(e) le', fmt.format(_birthDate!)),
      if (_mrz != null) ('N° de CNI', _mrz!.numeroDocument),
      if (_mrz?.dateExpiration != null)
        ('Valide jusqu\'au', fmt.format(_mrz!.dateExpiration!)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FicheCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (_selfie != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_selfie!,
                        width: 64, height: 64, fit: BoxFit.cover),
                  ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child:
                      Text('Lu sur votre carte', style: AppText.sectionTitle),
                ),
                const StatusStamp(
                    FicheStatus('À VÉRIFIER', StampTone.received)),
              ]),
              const SizedBox(height: AppSpace.md),
              const Divider(),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                        width: 120, child: Text(k, style: AppText.caption)),
                    Expanded(child: Text(v, style: AppText.bodyStrong)),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: _consent ? AppColors.letterhead : AppColors.ruleStrong,
                width: _consent ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Conservation de votre pièce d\'identité',
                  style: AppText.cardTitle),
              const SizedBox(height: AppSpace.sm),
              Text(kConsentText, style: AppText.caption.copyWith(height: 1.45)),
              const SizedBox(height: AppSpace.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title:
                    Text('J\'ai lu et j\'accepte', style: AppText.bodyStrong),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Un membre de l\'équipe WANDA compare votre selfie à la photo de votre carte, généralement sous 48 h. Le badge apparaît dès la validation.',
          style: AppText.caption,
        ),
      ],
    );
  }

  // ---------- Fin ----------

  Widget _buildDone() {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: StatusStamp(
                FicheStatus('EN VÉRIFICATION', StampTone.received),
                large: true,
                angle: -6),
          ),
          const SizedBox(height: AppSpace.xl),
          Text('Votre demande de certification est envoyée.',
              textAlign: TextAlign.center, style: AppText.sectionTitle),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Nous vérifions votre identité, généralement sous 48 h. Vous continuez à travailler normalement en attendant ; le badge apparaîtra sur votre fiche dès la validation.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54)),
            child: const Text('Retour à mon espace'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasPhoto = switch (_step) {
      _Step.recto => _recto != null,
      _Step.verso => _verso != null,
      _Step.selfie => _selfie != null,
      _ => true,
    };
    final isCapture =
        _step == _Step.recto || _step == _Step.verso || _step == _Step.selfie;

    final (label, icon, onTap) = switch (_step) {
      _ when isCapture && !hasPhoto => (
          _step == _Step.selfie
              ? 'Prendre mon selfie'
              : 'Photographier la carte',
          Icons.photo_camera_rounded,
          _analysing ? null : () => _capture(_step),
        ),
      _Step.intro => ('Commencer', Icons.arrow_forward_rounded, _next),
      _Step.consent => (
          'Envoyer pour vérification',
          Icons.send_rounded,
          _canContinue ? _next : null,
        ),
      _ => (
          'Continuer',
          Icons.arrow_forward_rounded,
          _canContinue && !_analysing ? _next : null,
        ),
    };

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.md),
          child: _submitting
              ? const FilledButton(
                  onPressed: null,
                  style: ButtonStyle(
                      minimumSize:
                          WidgetStatePropertyAll(Size(double.infinity, 54))),
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4)),
                )
              : FilledButton.icon(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54)),
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                ),
        ),
      ),
    );
  }
}
