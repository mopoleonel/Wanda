// presta_login_page.dart
// -----------------------------------------------------------------------------
// Espace prestataire : inscription ET connexion par NUMÉRO DE TÉLÉPHONE + code
// reçu sur WhatsApp (pas de mot de passe). Au premier code vérifié, on demande
// seulement « Artisan ou Entreprise ? » : l'artisan est créé avec son numéro
// seul et complète nom, services, photo puis certification depuis son espace.
// C'est le seul moyen de connexion : il n'y a plus de mot de passe.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/app_primary_button.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/around_you_scene.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/city_backdrop.dart';
import '../../data/models/secteur.dart';
import '../../data/repositories/auth_repository.dart';

/// Étapes de l'écran prestataire.
/// - [phone] / [code] : inscription ET connexion via un code WhatsApp.
/// - [accountType] : premier passage seulement, artisan ou entreprise.
enum _Step { phone, code, accountType }

class LoginPrestaPage extends ConsumerStatefulWidget {
  const LoginPrestaPage({super.key});

  @override
  ConsumerState<LoginPrestaPage> createState() => _LoginPrestaPageState();
}

class _LoginPrestaPageState extends ConsumerState<LoginPrestaPage> {
  static const _resendDelay = 60;

  _Step _step = _Step.phone;
  bool isEntreprise = false;
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
  final entrepriseController = TextEditingController();

  String? selectedSector;
  File? entrepriseLogo;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeFocus.dispose();
    for (final c in [
      phoneController,
      codeController,
      entrepriseController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validatePhone(String? v) =>
      normalizePhone(v ?? '') == null ? 'Numéro invalide' : null;
  String? _validateRequired(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

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
      final type = await auth.fetchUserType(userId);
      if (type == UserType.citoyen) {
        await auth.signOut();
        throw const AppException(
            "Ce numéro est lié à un compte citoyen. Utilisez l'espace citoyen.");
      }
      if (type != null) return _enterSpace();

      // Nouveau numéro. S'il figure déjà sur un ancien compte pas encore
      // rattaché à ce numéro, on n'en crée pas un second : l'équipe WANDA
      // le rattache (voir supabase/sql/007).
      final used = await ref
          .read(profileRepositoryProvider)
          .isPhoneUsedByOtherPrestataire(phone, userId);
      if (used) {
        await auth.signOut();
        if (mounted) _goTo(_Step.phone);
        throw const AppException(
            "Ce numéro est déjà lié à un compte WANDA. Contactez l'équipe "
            'WANDA pour retrouver l\'accès à votre compte.');
      }
      if (mounted) setState(() => _step = _Step.accountType);
    });
  }

  /// Premier passage : crée le compte artisan (numéro seul) ou entreprise.
  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _submitted = true);
      return;
    }
    final phone = _sentToPhone;
    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (phone == null || userId == null) return _goTo(_Step.phone);
    await _run(() async {
      final profiles = ref.read(profileRepositoryProvider);
      await profiles.createProfileEntry(
          userId, isEntreprise ? 'entreprise' : 'particulier');
      if (isEntreprise) {
        var logoUrl = '';
        if (entrepriseLogo != null) {
          logoUrl = await ref.read(storageRepositoryProvider).uploadImage(
              bucket: 'profils',
              path: 'profiles/$userId',
              file: entrepriseLogo!);
        }
        await profiles.createEntreprise(
          id: userId,
          nomEntreprise: entrepriseController.text.trim(),
          secteurActivite: selectedSector ?? '',
          telephone: phone,
          logoUrl: logoUrl,
        );
      } else {
        await profiles.createParticulier(id: userId, telephone: phone);
      }
      if (mounted) {
        showAppSnackBar(
            context,
            isEntreprise
                ? 'Bienvenue sur WANDA !'
                : 'Bienvenue sur WANDA ! Complétez votre profil pour recevoir des missions.',
            isError: false);
      }
      await _enterSpace();
    });
  }

  /// Abandon au choix du type de compte : on ferme la session ouverte par
  /// le code (le choix sera reproposé au prochain code).
  Future<void> _cancelAccountCreation() async {
    await _run(() async {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) _goTo(_Step.phone);
    });
  }

  /// Après connexion ou inscription : vers le bon espace.
  Future<void> _enterSpace() async {
    final auth = ref.read(authRepositoryProvider);
    final userId = auth.currentUserId;
    if (userId == null) throw const AppException('Connexion impossible.');
    final userType = await auth.fetchUserType(userId);
    final phone = _sentToPhone;
    if (userType == UserType.particulier && phone != null) {
      // Couvre une inscription interrompue entre les deux insertions.
      final profiles = ref.read(profileRepositoryProvider);
      if (await profiles.fetchParticulier(userId) == null) {
        await profiles.createParticulier(id: userId, telephone: phone);
      }
    }
    unawaited(ref
        .read(pushNotificationServiceProvider)
        .registerDeviceForUser(userId));
    if (!mounted) return;
    if (userType == UserType.entreprise) {
      context.go(AppRoutes.dashboardEntreprise);
    } else if (userType == UserType.particulier) {
      context.go(AppRoutes.dashboardParticulier);
    } else {
      await auth.signOut();
      throw const AppException(
          "Ce compte n'est pas un compte prestataire. Utilisez l'espace citoyen.");
    }
  }

  void _goTo(_Step step) => setState(() => _step = step);

  Future<void> _pickLogo() async {
    try {
      final image = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;
      final file = File(image.path);
      if (file.lengthSync() > 5 * 1024 * 1024) {
        if (mounted) {
          showAppSnackBar(context, "L'image est trop lourde (5 Mo max).");
        }
        return;
      }
      setState(() => entrepriseLogo = file);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, "Erreur lors de la sélection de l'image.");
      }
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final (cardTitle, cardSubtitle) = switch (_step) {
      _Step.phone => (
          'Espace prestataire',
          'Inscription ou connexion avec votre numéro : on vous envoie un code sur WhatsApp.',
        ),
      _Step.code => (
          'Entrez le code',
          'Code à 6 chiffres envoyé sur WhatsApp au ${_sentToPhone ?? ''}.',
        ),
      _Step.accountType => (
          'Créer votre compte',
          'Numéro vérifié. Dernière question avant votre espace.',
        ),
    };

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
                // La ville + la scène ; se replie quand le clavier s'ouvre,
                // que l'écran est petit ou que le formulaire est long.
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
                  // Toujours un peu de ville visible ; si le formulaire est
                  // plus haut, seul l'intérieur de la carte défile.
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
                              Text(cardTitle,
                                  style: AppText.sectionTitle
                                      .copyWith(fontSize: 20)),
                              const SizedBox(height: 4),
                              Text(cardSubtitle, style: AppText.caption),
                              const SizedBox(height: AppSpace.lg),
                              ...switch (_step) {
                                _Step.phone => _phoneStep(),
                                _Step.code => _codeStep(),
                                _Step.accountType => _accountTypeStep(),
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

  Widget _phoneField() => AppTextField(
        controller: phoneController,
        label: 'Numéro de téléphone',
        icon: Icons.phone_iphone_rounded,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        textInputAction: TextInputAction.next,
        helperText: _step == _Step.phone
            ? 'Ex : 699 00 00 00. Votre numéro WhatsApp, où les clients vous joignent.'
            : null,
        validator: _validatePhone,
      );

  List<Widget> _phoneStep() => [
        _phoneField(),
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

  List<Widget> _accountTypeStep() => [
        Text('Vous êtes', style: AppText.label),
        const SizedBox(height: AppSpace.sm),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: false,
                icon: Icon(Icons.person_rounded),
                label: Text('Indépendant')),
            ButtonSegment(
                value: true,
                icon: Icon(Icons.apartment_rounded),
                label: Text('Entreprise')),
          ],
          selected: {isEntreprise},
          onSelectionChanged: (s) => setState(() => isEntreprise = s.first),
          style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 48))),
        ),
        const SizedBox(height: AppSpace.xl),
        if (isEntreprise) ...[
          AppTextField(
            controller: entrepriseController,
            label: "Nom de l'entreprise",
            icon: Icons.business_rounded,
            textInputAction: TextInputAction.next,
            validator: _validateRequired,
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            initialValue: selectedSector,
            isExpanded: true,
            validator: (v) => v == null ? 'Choisissez un secteur' : null,
            borderRadius: BorderRadius.circular(AppRadius.field),
            dropdownColor: AppColors.surface,
            style: AppText.bodyStrong,
            items: secteursActivite
                .map((s) => DropdownMenuItem(
                    value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => selectedSector = v),
            decoration: const InputDecoration(
              labelText: "Secteur d'intervention",
              prefixIcon: Icon(Icons.category_outlined, size: 20),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          _buildLogoPicker(),
        ] else
          Row(children: [
            const Icon(Icons.verified_outlined,
                size: 16, color: AppColors.inkMuted),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                'Nom, services et photo se complètent ensuite dans votre espace, puis vous pourrez obtenir le badge « Identité vérifiée ».',
                style: AppText.caption,
              ),
            ),
          ]),
        const SizedBox(height: AppSpace.xl),
        AppPrimaryButton(
          label: 'Créer mon compte',
          isLoading: isLoading,
          onPressed: _createAccount,
        ),
        const SizedBox(height: AppSpace.xs),
        TextButton(
          onPressed: isLoading ? null : _cancelAccountCreation,
          child: const Text('Annuler'),
        ),
      ];

  Widget _buildLogoPicker() {
    final file = entrepriseLogo;
    return FicheCard(
      onTap: _pickLogo,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surfaceSunk,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.ruleStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: file != null
              ? Image.file(file, fit: BoxFit.cover)
              : const Icon(Icons.add_a_photo_outlined,
                  color: AppColors.inkSoft, size: 26),
        ),
        const SizedBox(width: AppSpace.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Logo de l'entreprise", style: AppText.cardTitle),
              const SizedBox(height: 2),
              Text(
                  file != null
                      ? 'Touchez pour changer'
                      : 'Facultatif · 5 Mo max',
                  style: AppText.caption),
            ],
          ),
        ),
      ]),
    );
  }

  static const double _overlap = 36;

  static const _cityImages = [
    'assets/images/city3.jpg',
    'assets/images/city2.png',
    'assets/images/city4.jpg',
    'assets/images/city1.png',
  ];

  /// En-tête en paliers selon la hauteur disponible : scène + titre, titre
  /// seul, ou juste la ville (clavier ouvert, formulaire long).
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
                Text('Espace prestataire',
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
                        _step == _Step.accountType
                            ? 'Rejoignez le\nréseau WANDA'
                            : 'Recevez des missions\nprès de chez vous',
                        style: AppText.display.copyWith(
                            color: Colors.white,
                            fontSize: showScene ? 32 : 26,
                            height: 1.05),
                      ),
                      if (showSubtitle) ...[
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          'Les citoyens de votre quartier vous trouvent, vous sollicitent et vous notent.',
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
}
