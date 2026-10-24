import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/around_you_scene.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/city_backdrop.dart';
import '../../core/widgets/app_primary_button.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/app_text_field.dart';
import '../../data/repositories/auth_repository.dart';

/// Étapes de l'écran citoyen.
/// - [phone] / [code] : inscription ET connexion via un code WhatsApp
///   (le compte est créé automatiquement au premier code vérifié). C'est
///   le seul moyen de connexion : il n'y a plus de mot de passe.
enum _Step { phone, code }

class LoginCitoyenPage extends ConsumerStatefulWidget {
  const LoginCitoyenPage({super.key});

  @override
  ConsumerState<LoginCitoyenPage> createState() => _LoginCitoyenPageState();
}

class _LoginCitoyenPageState extends ConsumerState<LoginCitoyenPage> {
  static const _resendDelay = 60;

  _Step _step = _Step.phone;
  bool isLoading = false;

  /// Numéro normalisé (E.164) auquel le dernier code a été envoyé.
  String? _sentToPhone;
  int _resendIn = 0;
  Timer? _resendTimer;

  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;

  /// Focus du champ code : `autofocus` ne suffit pas (le champ apparaît
  /// pendant la transition), on ouvre le clavier explicitement.
  final _codeFocus = FocusNode();

  final phoneController = TextEditingController();
  final codeController = TextEditingController();

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeFocus.dispose();
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  // ================= ACTIONS =================

  Future<void> _run(Future<void> Function() action) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _submitted = true);
      return;
    }
    final phone = normalizePhone(phoneController.text)!;
    await _run(() async {
      await ref.read(authRepositoryProvider).sendWhatsAppOtp(phone);
      if (!mounted) return;
      codeController.clear();
      setState(() {
        _sentToPhone = phone;
        _step = _Step.code;
      });
      _startResendCountdown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
      showAppSnackBar(context, "Code envoyé sur WhatsApp au $phone",
          isError: false);
    });
  }

  Future<void> _resendCode() async {
    final phone = _sentToPhone;
    if (phone == null || _resendIn > 0) return;
    await _run(() async {
      await ref.read(authRepositoryProvider).sendWhatsAppOtp(phone);
      if (!mounted) return;
      _startResendCountdown();
      showAppSnackBar(context, "Nouveau code envoyé sur WhatsApp",
          isError: false);
    });
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendDelay);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _submitted = true);
      return;
    }
    final phone = _sentToPhone;
    if (phone == null) return;
    await _run(() async {
      final auth = ref.read(authRepositoryProvider);
      final userId =
          await auth.verifyWhatsAppOtp(phone: phone, code: codeController.text);
      final isNew = await _ensureCitoyenProfile(userId, phone);
      _onSignedIn(userId, isNew: isNew);
    });
  }

  /// Crée les lignes `profiles` + `citoyens` au premier passage.
  /// Retourne `true` si le compte vient d'être créé.
  Future<bool> _ensureCitoyenProfile(String userId, String phone) async {
    final auth = ref.read(authRepositoryProvider);
    final profiles = ref.read(profileRepositoryProvider);

    final type = await auth.fetchUserType(userId);
    if (type != null && type != UserType.citoyen) {
      await auth.signOut();
      throw const AppException(
          "Ce numéro est déjà lié à un compte prestataire.");
    }
    if (type == null) {
      await profiles.createProfileEntry(userId, 'citoyen');
    }
    // Couvre aussi une inscription interrompue entre les deux insertions.
    if (await profiles.fetchCitoyen(userId) == null) {
      await profiles.createCitoyen(citoyenId: userId, telephone: phone);
      return true;
    }
    return false;
  }

  void _onSignedIn(String userId, {required bool isNew}) {
    unawaited(ref
        .read(pushNotificationServiceProvider)
        .registerDeviceForUser(userId));
    if (!mounted) return;
    if (isNew) {
      showAppSnackBar(context,
          "Bienvenue sur WANDA ! Complétez votre profil quand vous voulez.",
          isError: false);
    }
    context.go(AppRoutes.citoyenServices);
  }

  void _goTo(_Step step) => setState(() => _step = step);

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_step) {
      _Step.phone => (
          'Connexion par WhatsApp',
          'Pas de mot de passe : on vous envoie un code. Le compte est créé automatiquement.',
        ),
      _Step.code => (
          'Entrez le code',
          'Code à 6 chiffres envoyé sur WhatsApp au ${_sentToPhone ?? ''}.',
        ),
    };
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Form(
          key: _formKey,
          // Après une première tentative, chaque correction efface l'erreur.
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: LayoutBuilder(builder: (context, body) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // La ville + la scène « autour de vous » ; se replie quand le
                // clavier s'ouvre ou que l'écran est petit.
                // L'en-tête descend sous le haut de la carte (chevauchement)
                // sans réserver d'espace vide sous elle.
                Expanded(
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      bottom: -_overlap,
                      child: LayoutBuilder(
                        builder: (context, c) => _buildHero(c.maxHeight),
                      ),
                    ),
                  ]),
                ),
                ConstrainedBox(
                  // Le formulaire laisse toujours voir un peu de ville ;
                  // s'il manque de place (clavier + petit écran), seul
                  // l'intérieur de la carte défile.
                  constraints: BoxConstraints(maxHeight: body.maxHeight * 0.86),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(AppSpace.gutter, 0,
                        AppSpace.gutter, bottomInset + AppSpace.md),
                    child: FicheCard(
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpace.lg + 2),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: const Threshold(1),
                          child: Column(
                            key: ValueKey(_step),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(title,
                                  style: AppText.sectionTitle
                                      .copyWith(fontSize: 20)),
                              const SizedBox(height: 4),
                              Text(subtitle, style: AppText.caption),
                              const SizedBox(height: AppSpace.lg),
                              ...switch (_step) {
                                _Step.phone => _phoneStep(),
                                _Step.code => _codeStep(),
                              },
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  static const double _overlap = 36;

  /// En-tête en paliers selon la hauteur disponible : scène + titre, puis
  /// titre seul, puis juste la ville (clavier ouvert sur petit écran).
  Widget _buildHero(double height) {
    final topInset = MediaQuery.paddingOf(context).top;
    const bottomPad = 52.0;
    final topBar = topInset + AppSpace.sm + 48;
    final showTop = height >= topBar + bottomPad;
    final showTitle = height >= topBar + bottomPad + 64;
    final showScene = height >= 340;
    final showSubtitle = height >= 300;

    return Stack(fit: StackFit.expand, children: [
      const CityBackdrop(images: _cityImages),
      if (showTop)
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.gutter - 8,
              topInset + AppSpace.sm, AppSpace.gutter, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.home),
                  tooltip: 'Retour',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: AppSpace.sm),
                Text('Espace citoyen',
                    style: AppText.label
                        .copyWith(color: AppColors.onLetterheadSoft)),
              ]),
              Expanded(
                child: showScene
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: AroundYouScene(),
                      )
                    : const SizedBox.shrink(),
              ),
              if (showTitle)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'De quoi avez-vous\nbesoin ?',
                        style: AppText.display.copyWith(
                            color: Colors.white,
                            fontSize: showScene ? 32 : 26,
                            height: 1.05),
                      ),
                      if (showSubtitle) ...[
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          'Ménage, linge, poubelles, nuisibles : un prestataire de confiance près de chez vous, à prix fixe.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body
                              .copyWith(color: AppColors.onLetterheadSoft),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      const Positioned(left: 0, right: 0, bottom: 0, child: PerforatedEdge()),
    ]);
  }

  static const _cityImages = [
    'assets/images/city2.png',
    'assets/images/city3.jpg',
    'assets/images/city1.png',
    'assets/images/city4.jpg',
  ];

  List<Widget> _phoneStep() => [
        AppTextField(
          controller: phoneController,
          label: 'Numéro WhatsApp',
          icon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          // La touche « OK » du clavier envoie le code, sans chercher le bouton.
          textInputAction: TextInputAction.send,
          onFieldSubmitted: (_) => _sendCode(),
          helperText:
              'Ex : 699 00 00 00. Sans indicatif, le +$kDefaultCountryCode (Cameroun) est ajouté.',
          validator: (v) =>
              normalizePhone(v ?? '') == null ? 'Numéro invalide' : null,
        ),
        const SizedBox(height: AppSpace.lg),
        AppPrimaryButton(
          label: 'Recevoir le code WhatsApp',
          icon: Icons.chat_rounded,
          isLoading: isLoading,
          onPressed: _sendCode,
        ),
      ];

  List<Widget> _codeStep() => [
        TextFormField(
          controller: codeController,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppText.number.copyWith(fontSize: 34, letterSpacing: 14),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '······',
            labelText: 'Code de vérification',
          ),
          validator: (v) => (v == null || v.length != 6)
              ? 'Le code contient 6 chiffres'
              : null,
          onChanged: (v) {
            if (v.length == 6) _verifyCode();
          },
        ),
        const SizedBox(height: AppSpace.xl),
        AppPrimaryButton(
          label: 'Valider',
          isLoading: isLoading,
          onPressed: _verifyCode,
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: (isLoading || _resendIn > 0) ? null : _resendCode,
              child: Text(_resendIn > 0
                  ? 'Renvoyer le code (${_resendIn}s)'
                  : 'Renvoyer le code'),
            ),
            TextButton(
              onPressed: isLoading ? null : () => _goTo(_Step.phone),
              child: const Text('Modifier le numéro'),
            ),
          ],
        ),
      ];
}
