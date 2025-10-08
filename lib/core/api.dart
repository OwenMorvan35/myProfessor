import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'io/file_stub.dart' if (dart.library.io) 'io/file_io.dart';

const _defaultBaseUrl = 'http://localhost:8080/api';

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = dotenv.env['API_BASE_URL'] ?? _defaultBaseUrl;
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  dio.interceptors.add(
    LogInterceptor(
      requestBody: false,
      responseBody: false,
    ),
  );

  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = ref.watch(dioProvider);
  return ApiClient(dio);
});

class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<List<Map<String, dynamic>>> listFolders() async {
    final response = await _dio.get('/folders');
    return _asListOfMap(response.data);
  }

  Future<Map<String, dynamic>> createFolder(String name) async {
    final response = await _dio.post('/folders', data: {'name': name});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> renameFolder(String id, String name) async {
    final response = await _dio.patch('/folders/$id', data: {'name': name});
    return _asMap(response.data);
  }

  Future<void> deleteFolder(String id) async {
    await _dio.delete('/folders/$id');
  }

  Future<List<Map<String, dynamic>>> listDocuments(String folderId) async {
    final response = await _dio.get('/folders/$folderId/documents');
    return _asListOfMap(response.data);
  }

  Future<Map<String, dynamic>> getDocument(String id) async {
    final response = await _dio.get('/documents/$id');
    return _asMap(response.data);
  }

  Future<void> deleteDocument(String id) async {
    await _dio.delete('/documents/$id');
  }

  Future<Map<String, dynamic>> uploadDocument(
    String folderId, {
    File? file,
    MultipartFile? multipart,
  }) async {
    assert((file != null) ^ (multipart != null), 'Provide either a file or a multipart payload');

    final multipartFile = multipart ??
        await MultipartFile.fromFile(
          file!.path,
          filename: file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'audio_${DateTime.now().millisecondsSinceEpoch}',
        );

    final formData = FormData();
    formData.files.add(MapEntry('file', multipartFile));

    final response = await _dio.post(
      '/folders/$folderId/documents/upload',
      data: formData,
    );

    final data = _asMap(response.data);
    return _asMap(data['document'] ?? data);
  }

  Future<String> generatePdf(String documentId) async {
    final response = await _dio.post('/documents/$documentId/pdf');
    final data = _asMap(response.data);
    return data['pdfPath']?.toString() ?? '';
  }

  Future<String> shareDocument(String documentId) async {
    final response = await _dio.post('/documents/$documentId/share');
    final data = _asMap(response.data);
    return data['url']?.toString() ?? '';
  }

  List<Map<String, dynamic>> _asListOfMap(dynamic raw) {
    if (raw is List) {
      return raw.cast<Map<String, dynamic>>();
    }

    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    }

    return const [];
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded;
    }

    return <String, dynamic>{};
  }
}
