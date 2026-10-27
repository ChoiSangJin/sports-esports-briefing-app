import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyStorageService {
  ApiKeyStorageService([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'gemini_api_key';
  Future<String?> read() => _storage.read(key: _key);
  Future<void> save(String value) =>
      _storage.write(key: _key, value: value.trim());
  Future<void> delete() => _storage.delete(key: _key);
}
