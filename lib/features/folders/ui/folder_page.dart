import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/io/file_stub.dart'
    if (dart.library.io) '../../../core/io/file_io.dart' as io;
import '../../../core/ui/app_card.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/section_title.dart';
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
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('Importer un audio'),
                    subtitle: const Text(
                        'Choisis un fichier existant sur ton appareil.'),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _pickAndUpload(rootContext, ref);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.mic_none_outlined),
                    title: const Text('Enregistrer maintenant'),
                    subtitle: const Text('Capture une nouvelle session audio.'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      rootContext.push('/recorder?folderId=$folderId');
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Future<void> _syncDocuments() async {
      final success =
          await _withLoader(context, () => repo.syncDocuments(folderId));
      if (success && context.mounted) {
        _showSnack(context, 'Dossier synchronisé');
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => context.go('/'),
        ),
        title: Text(folderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recharger',
            onPressed: _syncDocuments,
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: documentsAsync.when(
            data: (documents) => _FolderContent(
              documents: documents,
              onShowCreate: _showCreateSheet,
              onSync: _syncDocuments,
              folderId: folderId,
              pickAndUpload: (context) => _pickAndUpload(context, ref),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Erreur : $error')),
          ),
        ),
      ),
      floatingActionButton: SizedBox(
        width: 220,
        child: PrimaryButton(
          label: 'Nouveau document',
          icon: Icons.note_add_outlined,
          onPressed: _showCreateSheet,
        ),
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

class _FolderContent extends StatelessWidget {
  const _FolderContent({
    required this.documents,
    required this.onShowCreate,
    required this.onSync,
    required this.folderId,
    required this.pickAndUpload,
  });

  final List<Document> documents;
  final VoidCallback onShowCreate;
  final VoidCallback onSync;
  final String folderId;
  final Future<void> Function(BuildContext context) pickAndUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (documents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Icon(
                        Icons.library_music_outlined,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Aucun document', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Importe un audio existant ou enregistre directement un nouveau cours.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Importer un audio',
                      icon: Icons.file_upload_outlined,
                      onPressed: () => onShowCreate(),
                      expand: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 1100
            ? 3
            : width > 800
                ? 2
                : 1;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      'Documents du dossier',
                      icon: Icons.description_outlined,
                      trailing: SecondaryButton(
                        label: 'Synchroniser',
                        icon: Icons.refresh,
                        onPressed: onSync,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        PrimaryButton(
                          label: 'Importer un audio',
                          icon: Icons.file_upload_outlined,
                          onPressed: () => pickAndUpload(context),
                        ),
                        SecondaryButton(
                          label: 'Enregistrer',
                          icon: Icons.mic_outlined,
                          onPressed: () => GoRouter.of(context)
                              .push('/recorder?folderId=$folderId'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              sliver: crossAxisCount == 1
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final document = documents[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == documents.length - 1 ? 0 : 16,
                            ),
                            child: _DocumentCard(document: document),
                          );
                        },
                        childCount: documents.length,
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 20,
                        childAspectRatio: 4 / 3,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final document = documents[index];
                          return _DocumentCard(document: document);
                        },
                        childCount: documents.length,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DocumentCard extends ConsumerWidget {
  const _DocumentCard({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(documentsRepositoryProvider);
    final theme = Theme.of(context);
    final title = document.title.isEmpty ? 'Sans titre' : document.title;
    final updatedAt = document.updatedAt.toLocal();
    final updatedText =
        '${updatedAt.day.toString().padLeft(2, '0')}/${updatedAt.month.toString().padLeft(2, '0')}/${updatedAt.year}';

    return AppCard(
      onTap: () => GoRouter.of(context).push('/document/${document.id}'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.article_outlined,
                    color: theme.colorScheme.primary),
              ),
              const Spacer(),
              PopupMenuButton<_DocAction>(
                onSelected: (action) async {
                  switch (action) {
                    case _DocAction.view:
                      GoRouter.of(context).push('/document/${document.id}');
                      break;
                    case _DocAction.delete:
                      final confirm = await _showConfirmDialog(
                        context,
                        title: 'Supprimer le document',
                        message: 'Cette action est définitive.',
                      );
                      if (confirm == true) {
                        final success = await _withLoader(
                          context,
                          () => repo.deleteDocument(document.id),
                        );
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
                    child: Text('Ouvrir'),
                  ),
                  PopupMenuItem(
                    value: _DocAction.delete,
                    child: Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.schedule,
                label: 'Modifié le $updatedText',
              ),
              _InfoChip(
                icon: Icons.graphic_eq_outlined,
                label: document.processingStatus == 'completed'
                    ? 'Transcription prête'
                    : document.processingStatus == 'processing'
                        ? 'En cours de transcription'
                        : 'En attente',
              ),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: TextButton(
              onPressed: () =>
                  GoRouter.of(context).push('/document/${document.id}'),
              child: const Text('Ouvrir'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DocAction { view, delete }

Future<bool?> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
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
          PrimaryButton(
            label: 'Supprimer',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
}

Future<bool> _withLoader(
  BuildContext context,
  Future<void> Function() task,
) async {
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
