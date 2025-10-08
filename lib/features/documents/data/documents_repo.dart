import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/io/file_stub.dart' if (dart.library.io) '../../../core/io/file_io.dart';
import '../../folders/data/folder.dart';
import '../../folders/data/folders_repo.dart';
import 'document.dart';

final documentsBoxProvider = Provider<Box<Document>>((ref) {
  return Hive.box<Document>('documents');
});

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  final documentsBox = ref.watch(documentsBoxProvider);
  final foldersBox = ref.watch(foldersBoxProvider);
  return DocumentsRepository(api, documentsBox, foldersBox);
});

final documentsStreamProvider = StreamProvider.autoDispose.family<List<Document>, String>((ref, folderId) {
  final repo = ref.watch(documentsRepositoryProvider);
  return repo.watchDocuments(folderId);
});

final documentStreamProvider = StreamProvider.autoDispose.family<Document?, String>((ref, id) {
  final repo = ref.watch(documentsRepositoryProvider);
  return repo.watchDocument(id);
});

class DocumentsRepository {
  DocumentsRepository(this._api, this._documentsBox, this._foldersBox);

  final ApiClient _api;
  final Box<Document> _documentsBox;
  final Box<Folder> _foldersBox;

  Stream<List<Document>> watchDocuments(String folderId) async* {
    yield _documentsForFolder(folderId);
    await for (final _ in _documentsBox.watch()) {
      yield _documentsForFolder(folderId);
    }
  }

  Stream<Document?> watchDocument(String id) async* {
    yield _documentsBox.get(id);
    await for (final _ in _documentsBox.watch(key: id)) {
      yield _documentsBox.get(id);
    }
  }

  Future<List<Document>> syncDocuments(String folderId) async {
    final remote = await _api.listDocuments(folderId);
    final documents = remote.map(Document.fromJson).toList(growable: false);

    final remoteIds = documents.map((doc) => doc.id).toSet();
    for (final doc in documents) {
      _saveDocument(doc);
    }

    final existing = _documentsBox.values
        .where((doc) => doc.folderId == folderId)
        .map((doc) => doc.id)
        .toList();

    for (final id in existing) {
      if (!remoteIds.contains(id)) {
        _removeDocument(id);
      }
    }

    _updateFolderDocumentIds(folderId);
    return documents;
  }

  Future<Document> getDocument(String id, {bool refresh = true}) async {
    if (!refresh) {
      final cached = _documentsBox.get(id);
      if (cached != null) {
        return cached;
      }
    }

    final data = await _api.getDocument(id);
    final doc = Document.fromJson(data);
    _saveDocument(doc);
    _updateFolderDocumentIds(doc.folderId);
    return doc;
  }

  Future<void> deleteDocument(String id) async {
    final existing = _documentsBox.get(id);
    await _api.deleteDocument(id);
    _removeDocument(id);

    if (existing != null) {
      _updateFolderDocumentIds(existing.folderId);
    }
  }

  Future<Document> uploadDocument({
    required String folderId,
    required File file,
  }) async {
    final data = await _api.uploadDocument(folderId, file: file);
    final doc = Document.fromJson(data);
    _saveDocument(doc);
    _updateFolderDocumentIds(folderId);
    return doc;
  }

  Future<Document> uploadDocumentFromBytes({
    required String folderId,
    required List<int> bytes,
    required String filename,
  }) async {
    final multipart = MultipartFile.fromBytes(bytes, filename: filename);
    final data = await _api.uploadDocument(folderId, multipart: multipart);
    final doc = Document.fromJson(data);
    _saveDocument(doc);
    _updateFolderDocumentIds(folderId);
    return doc;
  }

  Future<String> generatePdf(String documentId) async {
    final path = await _api.generatePdf(documentId);
    final doc = _documentsBox.get(documentId);
    if (doc != null) {
      final updated = doc.copyWith(
        pdfPath: path.isEmpty ? doc.pdfPath : path,
        updatedAt: DateTime.now(),
      );
      _documentsBox.put(updated.id, updated);
    }
    return path;
  }

  Future<String> shareDocument(String documentId) {
    return _api.shareDocument(documentId);
  }

  List<Document> _documentsForFolder(String folderId) {
    final docs = _documentsBox.values.where((doc) => doc.folderId == folderId).toList(growable: false);
    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return docs;
  }

  void _saveDocument(Document document) {
    final updated = document.copyWith(
      updatedAt: document.updatedAt.millisecondsSinceEpoch == 0
          ? DateTime.now()
          : document.updatedAt,
    );
    _documentsBox.put(updated.id, updated);
    _attachDocumentToFolder(updated);
  }

  void _removeDocument(String id) {
    final document = _documentsBox.get(id);
    _documentsBox.delete(id);
    if (document != null) {
      _detachDocumentFromFolder(document.folderId, document.id);
    }
  }

  void _attachDocumentToFolder(Document document) {
    final folder = _foldersBox.get(document.folderId);
    if (folder == null) {
      return;
    }

    final ids = {...folder.documentIds, document.id}.toList(growable: false);
    final updated = folder.copyWith(
      documentIds: ids,
      updatedAt: DateTime.now(),
    );
    _foldersBox.put(updated.id, updated);
  }

  void _detachDocumentFromFolder(String folderId, String documentId) {
    final folder = _foldersBox.get(folderId);
    if (folder == null) return;

    final ids = folder.documentIds.where((id) => id != documentId).toList();
    final updated = folder.copyWith(
      documentIds: ids,
      updatedAt: DateTime.now(),
    );
    _foldersBox.put(updated.id, updated);
  }

  void _updateFolderDocumentIds(String folderId) {
    final folder = _foldersBox.get(folderId);
    if (folder == null) return;

    final ids = _documentsBox.values
        .where((doc) => doc.folderId == folderId)
        .map((doc) => doc.id)
        .toSet()
        .toList(growable: false);

    final updated = folder.copyWith(
      documentIds: ids,
      updatedAt: DateTime.now(),
    );
    _foldersBox.put(updated.id, updated);
  }
}
