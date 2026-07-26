import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;

import '../config/supabase_config.dart';

class ApiService {
  ApiService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
          baseUrl: defaultBaseUrl,
          connectTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 120),
        ));

  final Dio _dio;

  /// Android emulator → host loopback. Desktop/web → localhost.
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://127.0.0.1:8000';
    }
  }

  Future<Map<String, dynamic>> analyzeVariantFile(PlatformFile file) async {
    if (file.bytes == null) {
      throw Exception('Could not read file bytes. Try a smaller VCF or re-pick the file.');
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
      'upload_id': 'user_upload_${DateTime.now().millisecondsSinceEpoch}',
      'drug_name': 'Clopidogrel',
    });

    final headers = <String, dynamic>{};
    if (SupabaseConfig.isConfigured) {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    try {
      final response = await _dio.post(
        '/analyze',
        data: formData,
        options: Options(headers: headers.isEmpty ? null : headers),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final detail = e.response?.data;
      final msg = detail is Map && detail['detail'] != null
          ? detail['detail'].toString()
          : (e.message ?? e.toString());
      throw Exception(
        'Backend error ($defaultBaseUrl): $msg. '
        'Confirm the Felino API is running on port 8000.',
      );
    }
  }

  Future<bool> ping() async {
    try {
      final res = await _dio.get('/health');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
