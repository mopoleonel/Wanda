import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';

/// Point d'entrée unique pour l'upload de fichiers vers Supabase Storage.
class StorageRepository {
  final SupabaseClient _client;
  StorageRepository(this._client);

  Future<String> uploadImage({
    required String bucket,
    required String path,
    required File file,
    bool upsert = false,
  }) async {
    try {
      await _client.storage.from(bucket).upload(
            path,
            file,
            fileOptions: FileOptions(upsert: upsert),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e, st) {
      throw mapError('StorageRepository.uploadImage', e, st);
    }
  }
}
