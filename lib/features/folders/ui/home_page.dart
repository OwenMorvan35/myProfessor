import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
      final name = await _showNameDialog(context, title: 'Nouveau dossier', controller: nameController);
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
      appBar: AppBar(
        title: const Text('Mes cours'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic),
            onPressed: () => context.push('/recorder'),
            tooltip: 'Enregistrer un audio',
          ),
        ],
      ),
      body: foldersAsync.when(
        data: (folders) {
          if (folders.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: folders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                title: Text(folder.name.isEmpty ? 'Sans titre' : folder.name),
                subtitle: Text('Documents : ${folder.documentIds.length}'),
                trailing: PopupMenuButton<_FolderAction>(
                  onSelected: (action) async {
                    switch (action) {
                      case _FolderAction.rename:
                        {
                          final controller = TextEditingController(text: folder.name);
                          final newName = await _showNameDialog(
                            context,
                            title: 'Renommer le dossier',
                            controller: controller,
                          );
                          controller.dispose();
                          if (newName != null && newName.isNotEmpty) {
                            final success = await _withLoader(context, () async {
                              await repo.renameFolder(folder.id, newName);
                            });
                            if (success && context.mounted) {
                              _showSnack(context, 'Dossier renommé');
                            }
                          }
                        }
                        break;
                      case _FolderAction.delete:
                        {
                          final confirm = await _showConfirmDialog(
                            context,
                            title: 'Supprimer le dossier',
                            message: 'Supprimer "${folder.name.isEmpty ? 'Sans titre' : folder.name}" ? Les documents associés seront retirés localement.',
                          );
                          if (confirm == true) {
                            final success = await _withLoader(context, () async {
                              await repo.deleteFolder(folder.id);
                            });
                            if (success && context.mounted) {
                              _showSnack(context, 'Dossier supprimé');
                            }
                          }
                        }
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
                onTap: () => context.go('/folder/${folder.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: createFolder,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Nouveau dossier'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Crée ton premier dossier pour organiser tes cours.'),
          ],
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
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(textController.text.trim()),
            child: const Text('Valider'),
          ),
        ],
      );
    },
  );
}

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
