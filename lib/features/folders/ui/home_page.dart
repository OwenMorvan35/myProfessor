import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ui/app_card.dart';
import '../../../core/ui/buttons.dart';
import '../../folders/data/folder.dart';
import '../data/folders_repo.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  static const routeName = 'home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(foldersRepositoryProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);
    final nameController = useTextEditingController();

    useEffect(() {
      Future.microtask(() => repo.syncFolders());
      return null;
    }, const []);

    Future<void> createFolder() async {
      final name = await _showNameDialog(
        context,
        title: 'Nouveau dossier',
        controller: nameController,
      );

      if (name == null || name.isEmpty) return;

      final success = await _withLoader(context, () async {
        await repo.createFolder(name);
        nameController.clear();
      });

      if (success && context.mounted) {
        _showSnack(context, 'Dossier créé');
      }
    }

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: foldersAsync.when(
            data: (folders) => _HomeContent(
              folders: folders,
              onCreateFolder: createFolder,
              onRename: (folder) async {
                final controller = TextEditingController(text: folder.name);
                final newName = await _showNameDialog(
                  context,
                  title: 'Renommer le dossier',
                  controller: controller,
                );
                controller.dispose();
                if (newName == null || newName.isEmpty) return;
                final success = await _withLoader(context, () async {
                  await repo.renameFolder(folder.id, newName);
                });
                if (success && context.mounted) {
                  _showSnack(context, 'Dossier renommé');
                }
              },
              onDelete: (folder) async {
                final confirm = await _showConfirmDialog(
                  context,
                  title: 'Supprimer le dossier',
                  message:
                      'Supprimer "${folder.name.isEmpty ? 'Sans titre' : folder.name}" ? '
                      'Les documents associés seront retirés localement.',
                );
                if (confirm != true) return;
                final success = await _withLoader(
                  context,
                  () => repo.deleteFolder(folder.id),
                );
                if (success && context.mounted) {
                  _showSnack(context, 'Dossier supprimé');
                }
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Erreur : $error')),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.folders,
    required this.onCreateFolder,
    required this.onRename,
    required this.onDelete,
  });

  final List<Folder> folders;
  final VoidCallback onCreateFolder;
  final void Function(Folder folder) onRename;
  final void Function(Folder folder) onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1120
            ? 3
            : width >= 780
                ? 2
                : 1;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  crossAxisCount == 1 ? 24 : 12,
                ),
                child: _Header(onCreateFolder: onCreateFolder),
              ),
            ),
            if (folders.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const _EmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                sliver: crossAxisCount == 1
                    ? SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final folder = folders[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == folders.length - 1 ? 0 : 16,
                              ),
                              child: _FolderCard(
                                folder: folder,
                                onRename: () => onRename(folder),
                                onDelete: () => onDelete(folder),
                              ),
                            );
                          },
                          childCount: folders.length,
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
                            final folder = folders[index];
                            return _FolderCard(
                              folder: folder,
                              onRename: () => onRename(folder),
                              onDelete: () => onDelete(folder),
                            );
                          },
                          childCount: folders.length,
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCreateFolder});

  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      gradient: const LinearGradient(
        colors: [
          Color(0xFF0066FF),
          Color(0xFF6F9BFF),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16),
                child: const Text('📘', style: TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mes dossiers',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Organise tes enregistrements et transforme-les en cours clairs en un instant.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Accéder à l’enregistreur',
                  icon: Icons.mic_outlined,
                  expand: true,
                  onPressed: () => GoRouter.of(context).push('/recorder'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: '+ Nouveau dossier',
                  icon: Icons.create_new_folder_outlined,
                  expand: true,
                  onPressed: onCreateFolder,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.onRename,
    required this.onDelete,
  });

  final Folder folder;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = folder.name.isEmpty ? 'Sans titre' : folder.name;
    final docCount = folder.documentIds.length;

    return AppCard(
      onTap: () => GoRouter.of(context).go('/folder/${folder.id}'),
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
                child: Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              PopupMenuButton<_FolderAction>(
                onSelected: (action) {
                  switch (action) {
                    case _FolderAction.rename:
                      onRename();
                      break;
                    case _FolderAction.delete:
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _FolderAction.rename,
                    child: Text('Renommer'),
                  ),
                  PopupMenuItem(
                    value: _FolderAction.delete,
                    child: Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: theme.textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            docCount == 0
                ? 'Aucun document'
                : '$docCount ${docCount > 1 ? 'documents' : 'document'}',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 18,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                'Mis à jour récemment',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(24),
                child: Icon(
                  Icons.auto_stories_outlined,
                  color: theme.colorScheme.primary,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Crée ton premier dossier',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Organise tes cours par matière, thématique ou semestre pour les retrouver instantanément.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FolderAction { rename, delete }

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  TextEditingController? controller,
}) {
  final textController = controller ?? TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom du dossier'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          PrimaryButton(
            label: 'Valider',
            onPressed: () =>
                Navigator.of(context).pop(textController.text.trim()),
          ),
        ],
      );
    },
  );
}

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
