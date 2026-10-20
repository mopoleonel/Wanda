// signal_page.dart
// -----------------------------------------------------------------------------
// Signalement d'incident citoyen : catégorie -> photo -> analyse IA -> envoi.
//
// L'analyse IA passe désormais par l'Edge Function Supabase
// `analyze-signalement` au lieu d'appeler Groq directement depuis le
// téléphone : la clé Groq ne quitte plus jamais le serveur.
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error/app_exception.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/bordereau.dart';
import '../../data/models/secteur.dart';

/// Catégorie d'incident proposée au citoyen.
class _Problem {
  final String title;
  final String hint;
  final IconData icon;
  final Color tint;
  final Color ink;
  const _Problem(this.title, this.hint, this.icon, this.tint, this.ink);
}

class SignalPage extends ConsumerStatefulWidget {
  const SignalPage({super.key});

  @override
  ConsumerState<SignalPage> createState() => _SignalPageState();
}

class _SignalPageState extends ConsumerState<SignalPage> {
  int? selectedIndex;
  int step = 1;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool analysing = false;
  String? _analysisError;

  static const problems = [
    _Problem("Dépôt d'ordures", 'Déchets, dépôt sauvage',
        Icons.delete_outline_rounded, Color(0xFFD5EEEA), Color(0xFF14665A)),
    _Problem("Fuite d'eau", 'Canalisation, inondation',
        Icons.water_drop_outlined, Color(0xFFD8E7F8), Color(0xFF1B4F8C)),
    _Problem('Électricité', 'Poteau, câble, panne', Icons.bolt_rounded,
        Color(0xFFF7E9A6), Color(0xFF6E5400)),
    _Problem('Autre (IA)', "L'IA détecte le type", Icons.auto_awesome_rounded,
        AppColors.stampVioletTint, AppColors.stampViolet),
  ];

  // --- LOGIQUE CAMERA ---
  Future<void> _openCamera() async {
    final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50 // Réduit le poids pour l'IA et Supabase
        );
    if (photo != null) {
      setState(() => _image = File(photo.path));
    }
  }

  void _nextStep() {
    if (step == 2) {
      setState(() => step = 3);
      _analyse();
    } else {
      setState(() => step++);
    }
  }

  // --- LOGIQUE IA (Edge Function Supabase -> Groq) ---
  Future<Map<String, dynamic>> _callAiAnalysis(
      File imageFile, String category) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await ref.read(supabaseClientProvider).functions.invoke(
      'analyze-signalement',
      body: {'category': category, 'imageBase64': base64Image},
    );

    final data = response.data;
    if (data is! Map || data['error'] != null) {
      throw const AppException(
          "L'analyse IA a échoué. Réessayez dans un instant.");
    }
    return Map<String, dynamic>.from(data);
  }

  // --- LOGIQUE GLOBALE (IA + GPS + SUPABASE) ---
  Future<void> _analyse() async {
    if (analysing) return;
    setState(() {
      analysing = true;
      _analysisError = null;
    });

    final userId = ref.read(authRepositoryProvider).currentUserId;
    if (userId == null) {
      // Signaler demande un compte : on renvoie vers la connexion citoyen.
      setState(() {
        analysing = false;
        step = 2;
      });
      showAppSnackBar(context, 'Connectez-vous pour envoyer un signalement.');
      context.push(AppRoutes.citoyenLogin);
      return;
    }

    try {
      // 1. RÉCUPÉRATION DE LA LOCALISATION
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const AppException(
            "Autorisez la localisation dans les réglages pour signaler un incident.");
      }

      final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));

      final selectedProblem = problems[selectedIndex!].title;

      // 2. VALIDATION IA
      final aiData = await _callAiAnalysis(_image!, selectedProblem);

      if (aiData['valid'] == false) {
        _showAIRejectDialog(aiData['reason'] as String? ??
            "L'image ne semble pas correspondre à un incident réel.");
        return;
      }

      final finalType = selectedProblem == "Autre (IA)"
          ? (aiData['detected_type'] as String? ?? "Incident divers")
          : selectedProblem;

      // 3. UPLOAD IMAGE VERS SUPABASE
      final fileName = 'signal_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageUrl = await ref.read(storageRepositoryProvider).uploadImage(
            bucket: 'signalements',
            path: 'uploads/$fileName',
            file: _image!,
          );

      // 4. ATTRIBUTION À L'ENTREPRISE DU SECTEUR (types libres de l'IA
      // compris, classés par mots-clés)
      final entrepriseId = await ref
          .read(signalementRepositoryProvider)
          .findEntrepriseIdForSecteur(secteurPourType(finalType));

      // 5. INSERTION FINALE (AVEC GPS ET IA DETAILS)
      await ref.read(signalementRepositoryProvider).create(
            typeProbleme: finalType,
            imageUrl: imageUrl,
            latitude: position.latitude,
            longitude: position.longitude,
            entrepriseId: entrepriseId,
            citoyenId: userId,
            iaValidationDetails: aiData['reason'] as String?,
          );

      if (mounted) _showSuccess();
    } on AppException catch (e) {
      setState(() {
        analysing = false;
        step = 2;
        _analysisError = e.message;
      });
      if (mounted) showAppSnackBar(context, e.message);
    } catch (e) {
      setState(() {
        analysing = false;
        step = 2;
      });
      if (mounted) {
        showAppSnackBar(context, 'Erreur technique. Vérifiez votre connexion.');
      }
    }
  }

  // --- INTERFACE UTILISATEUR (UI) ---

  void _showAIRejectDialog(String reason) {
    setState(() {
      analysing = false;
      step = 2;
    });
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.image_not_supported_outlined,
            color: AppColors.danger, size: 32),
        title: const Text('Photo refusée par la vérification'),
        content: Text(reason),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              _openCamera();
            },
            child: const Text('Reprendre la photo'),
          ),
        ],
      ),
    );
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SuccessDialog(
        type: problems[selectedIndex!].title,
        image: _image,
      ),
    );
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) context.go(AppRoutes.citoyenServices);
    });
  }

  static const _stepTitles = [
    "Quel est l'incident ?",
    'Prenez une photo',
    'Vérification en cours',
  ];

  @override
  Widget build(BuildContext context) {
    final content = switch (step) {
      1 => _buildStep1(),
      2 => _buildStep2(),
      _ => _buildStep3(),
    };
    return PopScope(
      canPop: !analysing,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Letterhead(
              showBack: !analysing,
              overline: 'Signalement · étape $step sur 3',
              title: _stepTitles[step - 1],
              bottom: _StepTrack(step: step),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xl),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                child: KeyedSubtree(key: ValueKey(step), child: content),
              ),
            ),
          ],
        ),
        bottomNavigationBar: step == 3 ? null : _buildBottomAction(),
      ),
    );
  }

  Widget _buildBottomAction() {
    final (label, icon, onTap) = step == 1
        ? (
            'Continuer',
            Icons.arrow_forward_rounded,
            selectedIndex == null ? null : _nextStep
          )
        : _image == null
            ? ('Ouvrir la caméra', Icons.photo_camera_rounded, _openCamera)
            : ('Envoyer le signalement', Icons.send_rounded, _nextStep);
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
          child: FilledButton.icon(
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

  Widget _buildStep1() {
    // Deux colonnes dont chaque rangée prend la hauteur de sa tuile la plus
    // haute : le texte agrandi par le système pousse la tuile au lieu d'être
    // coupé.
    final rows = <Widget>[];
    for (var i = 0; i < problems.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: AppSpace.md));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _problemTile(i)),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: i + 1 < problems.length
                  ? _problemTile(i + 1)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _problemTile(int index) {
    final item = problems[index];
    final isSelected = selectedIndex == index;
    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected ? item.tint : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: isSelected ? item.ink : AppColors.rule,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => selectedIndex = index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 148),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.surface : item.tint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, color: item.ink, size: 26),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: item.ink),
                  ]),
                  const SizedBox(height: AppSpace.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: AppText.cardTitle.copyWith(
                              color: isSelected ? item.ink : AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(item.hint, style: AppText.caption),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep2() {
    final item = problems[selectedIndex!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(item.icon, size: 18, color: item.ink),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Incident : ', style: AppText.caption),
                TextSpan(text: item.title, style: AppText.label),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => step = 1),
            child: const Text('Changer'),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Material(
            color: AppColors.surfaceSunk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: AppColors.ruleStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openCamera,
              child: _image != null
                  ? Image.file(_image!, fit: BoxFit.cover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_outlined,
                            size: 44, color: AppColors.inkSoft),
                        const SizedBox(height: AppSpace.md),
                        Text('Touchez pour prendre la photo',
                            style: AppText.bodyStrong),
                        const SizedBox(height: 4),
                        Text("Cadrez l'incident de près, en pleine lumière.",
                            style: AppText.caption),
                      ],
                    ),
            ),
          ),
        ),
        if (_image != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _openCamera,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reprendre la photo'),
            ),
          ),
        if (_analysisError != null) ...[
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.dangerTint,
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 20),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(_analysisError!,
                    style: AppText.body.copyWith(color: AppColors.danger)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(children: [
          const Icon(Icons.place_outlined, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              "Votre position est jointe automatiquement pour guider l'intervention.",
              style: AppText.caption,
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.file(_image!, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: AppSpace.xl),
        const LinearProgressIndicator(minHeight: 4),
        const SizedBox(height: AppSpace.lg),
        Text(
            "WANDA vérifie la photo avec l'IA, puis transmet votre signalement au service compétent.",
            style: AppText.body),
        const SizedBox(height: AppSpace.sm),
        Text('Gardez l\'application ouverte quelques secondes.',
            style: AppText.caption),
      ],
    );
  }
}

/// Piste des 3 étapes dans l'en-tête.
class _StepTrack extends StatelessWidget {
  final int step;
  const _StepTrack({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Type', 'Photo', 'Envoi'];
    return Row(
      children: List.generate(3, (i) {
        final active = step >= i + 1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? AppSpace.sm : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.brandLeaf
                        : Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(labels[i],
                    style: AppText.caption.copyWith(
                        color: active
                            ? Colors.white
                            : AppColors.onLetterheadSoft)),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Confirmation : le tampon « TRANSMIS » tombe sur la fiche du signalement.
class SuccessDialog extends StatelessWidget {
  final String type;
  final File? image;
  const SuccessDialog({super.key, required this.type, this.image});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              Row(children: [
                if (image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(image!,
                        width: 64, height: 64, fit: BoxFit.cover),
                  ),
                if (image != null) const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Signalement', style: AppText.caption),
                      Text(type, style: AppText.cardTitle),
                    ],
                  ),
                ),
              ]),
              const Positioned(
                right: -4,
                bottom: -18,
                child: _DelayedStamp(),
              ),
            ]),
            const SizedBox(height: AppSpace.xxl),
            Text('Merci, c\'est transmis.', style: AppText.sectionTitle),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Le service compétent a reçu votre alerte, avec la photo et la position.',
              style: AppText.body,
            ),
          ],
        ),
      ),
    );
  }
}

/// Le tampon apparaît après un court instant, pour qu'on le voie « tomber ».
class _DelayedStamp extends StatefulWidget {
  const _DelayedStamp();

  @override
  State<_DelayedStamp> createState() => _DelayedStampState();
}

class _DelayedStampState extends State<_DelayedStamp> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutExpo,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
            scale: Tween(begin: 1.6, end: 1.0).animate(anim), child: child),
      ),
      child: _shown
          ? const StatusStamp(FicheStatus('TRANSMIS', StampTone.done),
              angle: -8, large: true)
          : const SizedBox(width: 1, height: 1),
    );
  }
}
