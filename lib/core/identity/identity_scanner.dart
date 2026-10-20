import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'cni_parser.dart';

/// Un contrôle affiché à l'utilisateur (✓ ou ✗) après un scan.
class ScanCheck {
  final String label;
  final bool ok;
  const ScanCheck(this.label, this.ok);
}

/// Résultat d'un scan : accepté seulement si tous les contrôles bloquants
/// passent. [problem] explique quoi faire quand ce n'est pas le cas.
class ScanResult<T> {
  final T? data;
  final List<ScanCheck> checks;
  final String? problem;
  const ScanResult({this.data, required this.checks, this.problem});
  bool get accepted => problem == null;
}

/// Scans de la CNI et du selfie, entièrement sur le téléphone (Google ML
/// Kit) : aucune image n'est envoyée à un service tiers pour l'analyse.
class IdentityScanner {
  final TextRecognizer _text =
      TextRecognizer(script: TextRecognitionScript.latin);
  final FaceDetector _faces = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true, // probabilité « yeux ouverts »
      minFaceSize: 0.05,
    ),
  );

  /// En dessous, le texte d'une CNI est rarement lisible.
  static const _minWidthPx = 900;

  Future<void> dispose() async {
    // Sans moteur ML Kit (tests, plateforme non prise en charge), la
    // fermeture peut échouer : rien à libérer dans ce cas.
    try {
      await _text.close();
      await _faces.close();
    } catch (_) {}
  }

  Future<ui.Size> _imageSize(File file) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    final size =
        ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    return size;
  }

  // ------------------------------------------------------------- Recto ---

  Future<ScanResult<CniFront>> scanRecto(File file) async {
    final size = await _imageSize(file);
    final longSide = size.width > size.height ? size.width : size.height;
    final input = InputImage.fromFile(file);
    final recognized = await _text.processImage(input);
    final front = CniParser.parseFront(recognized.text);
    final faces = await _faces.processImage(input);

    final sharpEnough = longSide >= _minWidthPx;
    final checks = [
      ScanCheck('Photo assez nette', sharpEnough),
      ScanCheck(
          'Carte d\'identité camerounaise reconnue', front.looksLikeCameroonId),
      ScanCheck('Nom et prénoms lus', front.hasNames),
      ScanCheck('Photo de la carte visible', faces.isNotEmpty),
    ];

    String? problem;
    if (!sharpEnough) {
      problem = 'Photo trop petite ou floue : rapprochez-vous de la carte.';
    } else if (!front.looksLikeCameroonId) {
      problem =
          'Carte non reconnue. Cadrez tout le recto, à plat, sans reflet ni doigt sur le texte.';
    } else if (!front.hasNames) {
      problem =
          'Le nom ou les prénoms sont illisibles. Reprenez la photo en pleine lumière.';
    } else if (faces.isEmpty) {
      problem =
          'La photo d\'identité de la carte n\'est pas visible. Évitez les reflets sur le portrait.';
    }
    return ScanResult(data: front, checks: checks, problem: problem);
  }

  // ------------------------------------------------------------- Verso ---

  /// [recto] sert à vérifier que le verso est bien celui de la même carte.
  Future<ScanResult<CniMrz>> scanVerso(File file, {CniFront? recto}) async {
    final recognized = await _text.processImage(InputImage.fromFile(file));
    final mrz = CniParser.parseMrz(recognized.text);

    if (mrz == null) {
      return const ScanResult(
        checks: [ScanCheck('Code du verso (lignes « <<< ») lu', false)],
        problem:
            'Le code en bas du verso (les lignes avec des « <<< ») est illisible. Cadrez-le bien à plat, sans reflet.',
      );
    }

    final namesMatch = recto == null ||
        CniParser.nameSimilarity(
                '${recto.nom} ${recto.prenoms}', '${mrz.nom} ${mrz.prenoms}') >=
            0.5;
    final checks = [
      const ScanCheck('Code du verso lu', true),
      ScanCheck('Numéro et dates vérifiés', mrz.isValid),
      ScanCheck('Carte en cours de validité', !mrz.isExpired),
      if (recto != null) ScanCheck('Même personne qu\'au recto', namesMatch),
    ];

    String? problem;
    if (!mrz.isValid) {
      problem =
          'Lecture incertaine du code (contrôle incorrect). Reprenez la photo plus nettement.';
    } else if (mrz.isExpired) {
      problem =
          'Cette carte est expirée. Une CNI en cours de validité est nécessaire.';
    } else if (!namesMatch) {
      problem =
          'Les noms du recto et du verso ne correspondent pas. Photographiez les deux faces de la même carte.';
    }
    return ScanResult(data: mrz, checks: checks, problem: problem);
  }

  // ------------------------------------------------------------ Selfie ---

  Future<ScanResult<Face>> checkSelfie(File file) async {
    final size = await _imageSize(file);
    final faces = await _faces.processImage(InputImage.fromFile(file));

    if (faces.length != 1) {
      return ScanResult(
        checks: const [ScanCheck('Un seul visage', false)],
        problem: faces.isEmpty
            ? 'Aucun visage détecté. Placez votre visage face à l\'écran, en pleine lumière.'
            : 'Plusieurs visages détectés. Prenez le selfie seul.',
      );
    }
    final face = faces.first;
    final shortSide = size.width < size.height ? size.width : size.height;
    final wellFramed = face.boundingBox.width >= shortSide * 0.28;
    final straight = (face.headEulerAngleY ?? 0).abs() < 20 &&
        (face.headEulerAngleZ ?? 0).abs() < 20;
    final eyesOpen = (face.leftEyeOpenProbability ?? 1) > 0.4 &&
        (face.rightEyeOpenProbability ?? 1) > 0.4;

    final checks = [
      const ScanCheck('Un seul visage', true),
      ScanCheck('Visage bien cadré et de face', wellFramed && straight),
      ScanCheck('Yeux ouverts', eyesOpen),
    ];
    String? problem;
    if (!wellFramed) {
      problem = 'Rapprochez-vous : votre visage doit remplir le cadre.';
    } else if (!straight) {
      problem = 'Regardez l\'objectif bien de face.';
    } else if (!eyesOpen) {
      problem = 'Gardez les yeux ouverts pendant la photo.';
    }
    return ScanResult(data: face, checks: checks, problem: problem);
  }
}
