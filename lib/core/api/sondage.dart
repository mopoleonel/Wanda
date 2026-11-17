import 'dart:async';
import 'dart:convert';

/// Suivi « en direct » par interrogation régulière de l'API : lit tout de
/// suite, puis toutes les [intervalle], et n'émet que si le contenu a
/// changé. S'arrête dès que plus personne n'écoute.
///
/// Une erreur (réseau coupé…) est transmise une fois, puis le suivi
/// continue : il reprend tout seul quand la connexion revient.
Stream<T> sonder<T>(
  Future<T> Function() lire, {
  Duration intervalle = const Duration(seconds: 6),
  Object? Function(T valeur)? empreinte,
}) {
  late StreamController<T> controleur;
  Timer? minuterie;
  String? derniere;
  var enCours = false;
  var enErreur = false;

  Future<void> tour() async {
    if (enCours) return;
    enCours = true;
    try {
      final valeur = await lire();
      enErreur = false;
      final cle = jsonEncode(empreinte == null ? valeur : empreinte(valeur));
      if (cle != derniere && !controleur.isClosed) {
        derniere = cle;
        controleur.add(valeur);
      }
    } catch (e, st) {
      if (!enErreur && !controleur.isClosed) controleur.addError(e, st);
      enErreur = true;
    } finally {
      enCours = false;
    }
  }

  controleur = StreamController<T>(
    onListen: () {
      tour();
      minuterie = Timer.periodic(intervalle, (_) => tour());
    },
    onCancel: () {
      minuterie?.cancel();
      return controleur.close();
    },
  );
  return controleur.stream;
}
