import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/api.dart';
import '../data/documents_repo.dart';

class DocumentEditPage extends HookConsumerWidget {
  const DocumentEditPage({super.key, required this.documentId});

  final String documentId;
  static const routeName = 'document_edit';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);
    final api = ref.read(apiClientProvider);
    final documentAsync = ref.watch(documentStreamProvider(documentId));

    useEffect(() {
      Future.microtask(() => repo.getDocument(documentId));
      return null;
    }, [documentId]);

    final instructionsController = useTextEditingController();
    final generatedCourse = useState<String?>(null);
    final isGeneratingCourse = useState(false);

    final editorTargets = <String, String>{
      'Transcription': 'transcription',
      'Résumé': 'summary',
      'Cours': 'course',
    };

    final selectedEditorKey = useState<String>('Transcription');
    final editorController = useTextEditingController();
    final isSavingEditor = useState(false);

    void showSnack(String message) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Édition du document'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: documentAsync.when(
          data: (doc) {
            if (doc == null) {
              return const Center(child: Text('Document introuvable'));
            }

            useEffect(() {
              switch (selectedEditorKey.value) {
                case 'Résumé':
                  editorController.text = doc.summary;
                  break;
                case 'Cours':
                  editorController.text = doc.course;
                  break;
                default:
                  editorController.text = doc.transcription;
              }
              return null;
            }, [
              doc.transcription,
              doc.summary,
              doc.course,
              selectedEditorKey.value
            ]);

            Future<void> handleGenerateCourse() async {
              isGeneratingCourse.value = true;
              try {
                final course = await api.generateCourse(
                    doc.id, instructionsController.text.trim());
                generatedCourse.value = course;
                await repo.updateCachedDocument(
                  doc.copyWith(course: course, updatedAt: DateTime.now()),
                );
                showSnack('Cours généré');
              } catch (error) {
                generatedCourse.value = 'Erreur : $error';
                showSnack('Erreur : $error');
              } finally {
                isGeneratingCourse.value = false;
              }
            }

            Future<void> handleSave() async {
              final field = editorTargets[selectedEditorKey.value]!;
              isSavingEditor.value = true;
              try {
                await api.updateDocumentContent(
                  doc.id,
                  field: field,
                  content: editorController.text,
                );

                switch (field) {
                  case 'transcription':
                    await repo.updateCachedDocument(
                      doc.copyWith(
                          transcription: editorController.text,
                          updatedAt: DateTime.now()),
                    );
                    break;
                  case 'summary':
                    await repo.updateCachedDocument(
                      doc.copyWith(
                          summary: editorController.text,
                          updatedAt: DateTime.now()),
                    );
                    break;
                  case 'course':
                    await repo.updateCachedDocument(
                      doc.copyWith(
                          course: editorController.text,
                          updatedAt: DateTime.now()),
                    );
                    break;
                }

                showSnack('Sauvegardé');
              } catch (error) {
                showSnack('Erreur : $error');
              } finally {
                isSavingEditor.value = false;
              }
            }

            return ListView(
              children: [
                Text(
                  doc.title.isEmpty ? 'Sans titre' : doc.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text('Consigne (optionnel)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: instructionsController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Ajoute des instructions complémentaires pour la génération du cours',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      doc.transcription.isEmpty || isGeneratingCourse.value
                          ? null
                          : handleGenerateCourse,
                  icon: isGeneratingCourse.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.menu_book_outlined),
                  label: const Text('Générer un cours'),
                ),
                if (generatedCourse.value != null) ...[
                  const SizedBox(height: 16),
                  Text('Cours généré',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(generatedCourse.value!),
                  ),
                ],
                const SizedBox(height: 24),
                Text('Éditeur', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedEditorKey.value,
                  items: editorTargets.keys
                      .map(
                        (label) => DropdownMenuItem<String>(
                          value: label,
                          child: Text(label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    selectedEditorKey.value = value;
                    switch (value) {
                      case 'Résumé':
                        editorController.text = doc.summary;
                        break;
                      case 'Cours':
                        editorController.text = doc.course;
                        break;
                      default:
                        editorController.text = doc.transcription;
                    }
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Champ à éditer',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: editorController,
                  minLines: 10,
                  maxLines: 20,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Modifie le contenu puis enregistre',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: isSavingEditor.value ? null : handleSave,
                  icon: isSavingEditor.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer'),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('Erreur : $error')),
        ),
      ),
    );
  }
}
