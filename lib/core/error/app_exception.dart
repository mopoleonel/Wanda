/// Exception applicative portant un message déjà traduit et prêt à afficher
/// à l'utilisateur. Les repositories convertissent systématiquement les
/// erreurs Supabase/réseau brutes en [AppException] via [mapError] pour ne
/// jamais exposer de détails techniques dans l'interface.
class AppException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() => message;
}
