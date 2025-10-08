import 'dart:async';

import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/api.dart';
import '../../documents/data/document.dart';
import 'folder.dart';

final foldersBoxProvider = Provider<Box<Folder>>((ref) {
  return Hive.box<Folder>('folders');
});

final foldersRepositoryProvider = Provider<FoldersRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  final foldersBox = ref.watch(foldersBoxProvider);
  final documentsBox = Hive.box<Document>('documents');
  return FoldersRepository(api, foldersBox, documentsBox);
});

final foldersStreamProvider = StreamProvider.autoDispose<List<Folder>>((ref) {
  final repo = ref.watch(foldersRepositoryProvider);
  return repo.watchFolders();
});

class FoldersRepository {
  FoldersRepository(
    this._api,
    this._foldersBox,
    this._documentsBox,
  );

  final ApiClient _api;
  final Box<Folder> _foldersBox;
  final Box<Document> _documentsBox;

  Stream<List<Folder>> watchFolders() async* {
    yield _foldersBox.values.toList(growable: false);
    await for (final _ in _foldersBox.watch()) {
      yield _foldersBox.values.toList(growable: false);
    }
  }

  Future<List<Folder>> syncFolders() async {
    final remote = await _api.listFolders();
    final folders = remote.map(Folder.fromJson).toList(growable: false);

    final remoteIds = folders.map((f) => f.id).toSet();
    for (final key in _foldersBox.keys.cast<dynamic>().toList()) {
      if (!remoteIds.contains(key.toString())) {
        _foldersBox.delete(key);
      }
    }

    for (final folder in folders) {
      _foldersBox.put(folder.id, folder);
    }

    return folders;
  }

  Future<Folder> createFolder(String name) async {
    final data = await _api.createFolder(name);
    final folder = Folder.fromJson(data);
    _foldersBox.put(folder.id, folder);
    return folder;
  }

  Future<Folder> renameFolder(String id, String name) async {
    final data = await _api.renameFolder(id, name);
    final updated = Folder.fromJson(data);
    _foldersBox.put(updated.id, updated);
    return updated;
  }

  Future<void> deleteFolder(String id) async {
    await _api.deleteFolder(id);

    // Remove linked documents locally.
    final docIdsToRemove = _documentsBox.values
        .where((doc) => doc.folderId == id)
        .map((doc) => doc.id)
        .toList();

    for (final docId in docIdsToRemove) {
      _documentsBox.delete(docId);
    }

    _foldersBox.delete(id);
  }

  void attachDocumentToFolder(String folderId, String documentId) {
    final folder = _foldersBox.get(folderId);
    if (folder == null) return;

    final ids = {...folder.documentIds, documentId}.toList(growable: false);
    final updated = folder.copyWith(
      documentIds: ids,
      updatedAt: DateTime.now(),
    );
    _foldersBox.put(updated.id, updated);
  }

  void detachDocumentFromFolder(String folderId, String documentId) {
    final folder = _foldersBox.get(folderId);
    if (folder == null) return;

    final ids = folder.documentIds.where((id) => id != documentId).toList();
    final updated = folder.copyWith(
      documentIds: ids,
      updatedAt: DateTime.now(),
    );
    _foldersBox.put(updated.id, updated);
  }
}
