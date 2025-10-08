import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/io/file_stub.dart' if (dart.library.io) '../../../core/io/file_io.dart' as io;
import '../../documents/data/document.dart';
import '../../documents/data/documents_repo.dart';
import '../../folders/data/folders_repo.dart';

class FolderPage extends HookConsumerWidget {
  const FolderPage({super.key, required this.folderId});

  final String folderId;

  static const routeName = 'folder';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);
    final documentsAsync = ref.watch(documentsStreamProvider(folderId));
    final foldersAsync = ref.watch(foldersStreamProvider);

    final folderTitle = foldersAsync.maybeWhen(
      data: (folders) {
        for (final folder in folders) {
          if (folder.id == folderId) {
            return folder.name.isEmpty ? 'Sans titre' : folder.name;
          }
        }
        return 'Dossier';
      },
      orElse: () => 'Dossier',
    );

    useEffect(() {
      Future.microtask(() => repo.syncDocuments(folderId));
      return null;
    }, [folderId]);

    Future<void> _showCreateSheet() async {
      final rootContext = context;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload),
                  title: const Text('Importer un audio'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickAndUpload(rootContext, ref);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic_outlined),
                  title: const Text('Enregistrer maintenant'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    rootContext.push('/recorder?folderId=$folderId');
                  },
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(folderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recharger',
            onPressed: () async {
              final success = await _withLoader(context, () => repo.syncDocuments(folderId));
              if (success && context.mounted) {
                _showSnack(context, 'Dossier synchronisé');
              }
            },
          ),
        ],
      ),
      body: documentsAsync.when(
        data: (documents) {
          if (documents.isEmpty) {
            return const _EmptyDocuments();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: documents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final document = documents[index];
              return ListTile(
                title: Text(document.title.isEmpty ? 'Sans titre' : document.title),
                subtitle: Text('Modifié le ${document.updatedAt.toLocal()}'),
                trailing: PopupMenuButton<_DocAction>(
                  onSelected: (action) async {
                    switch (action) {
                      case _DocAction.view:
                        context.push('/document/${document.id}');
                        break;
                      case _DocAction.delete:
                        final confirm = await _showConfirmDialog(
                          context,
                          title: 'Supprimer le document',
                          message: 'Cette action est définitive.',
                        );
                        if (confirm == true) {
                          final success = await _withLoader(context, () => repo.deleteDocument(document.id));
                          if (success && context.mounted) {
                            _showSnack(context, 'Document supprimé');
                          }
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _DocAction.view,
                      child: Text('Voir'),
                    ),
                    PopupMenuItem(
                      value: _DocAction.delete,
                      child: Text('Supprimer'),
                    ),
                  ],
                ),
                onTap: () => context.push('/document/${document.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Nouveau document'),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(documentsRepositoryProvider);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: const ['mp3', 'm4a', 'wav', 'webm'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;

      final success = await _withLoader(context, () async {
        if (kIsWeb) {
          final Uint8List? bytes = picked.bytes;
          if (bytes == null) throw Exception('Fichier invalide');
          await repo.uploadDocumentFromBytes(
            folderId: folderId,
            bytes: bytes,
            filename: picked.name,
          );
        } else {
          final path = picked.path;
          if (path == null) throw Exception('Fichier invalide');
          final file = io.File(path);
          await repo.uploadDocument(folderId: folderId, file: file);
        }
      });

      if (success && context.mounted) {
        _showSnack(context, 'Document importé');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur import : $error')),
        );
      }
    }
  }
}

class _EmptyDocuments extends StatelessWidget {
  const _EmptyDocuments();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Aucun document pour ce dossier. Téléverse un audio ou enregistre-en un nouveau.'),
          ],
        ),
      ),
    );
  }
}

enum _DocAction { view, delete }

Future<bool?> _showConfirmDialog(BuildContext context, {required String title, required String message}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      );
    },
  );
}

Future<bool> _withLoader(BuildContext context, Future<void> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await task();
    return true;
  } catch (error) {
    if (context.mounted) {
      _showSnack(context, 'Erreur : $error');
    }
    return false;
  } finally {
    if (navigator.mounted) {
      navigator.pop();
    }
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
