import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api.dart';
import '../../../core/env.dart';
import '../../../core/io/file_stub.dart'
    if (dart.library.io) '../../../core/io/file_io.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/instructions_field.dart';
import '../../../core/ui/section_title.dart';
import '../data/document.dart';
import '../data/documents_repo.dart';

class DocumentPage extends HookConsumerWidget {
  const DocumentPage({super.key, required this.documentId});

  final String documentId;

  static const routeName = 'document';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);
    final dio = ref.read(dioProvider);
    final api = ref.read(apiClientProvider);
    final documentAsync = ref.watch(documentStreamProvider(documentId));

    useEffect(() {
      Future.microtask(() => repo.getDocument(documentId));
      return null;
    }, [documentId]);

    final isGeneratingSummary = useState(false);
    final isGeneratingCourse = useState(false);
    final isTranscribing = useState(false);

    final summaryPresetController = useTextEditingController(
      text:
          'Tu es un assistant pédagogique. Résume ce cours en bullet points clairs. '
          'Sépare Définitions, Concepts, Exemples.',
    );

    Future<void> generatePdf(Document doc) async {
      String? pdfPath;
      final success = await _withLoader(context, () async {
        pdfPath = await repo.generatePdf(doc.id);
      });

      if (!success || !context.mounted || pdfPath == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pdfPath!.isEmpty ? 'PDF indisponible' : 'PDF généré: $pdfPath',
          ),
        ),
      );
    }

    Future<void> shareDocument(Document doc) async {
      String? url;
      final success = await _withLoader(context, () async {
        url = await repo.shareDocument(doc.id);
      });

      if (!success || url == null || url!.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Partage indisponible')),
          );
        }
        return;
      }

      await Clipboard.setData(ClipboardData(text: url!));

      if (Env.shareOpenInBrowser) {
        final uri = Uri.parse(url!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lien copié et '
              '${Env.shareOpenInBrowser ? 'ouvert dans le navigateur' : 'prêt à partager'}',
            ),
          ),
        );
      }
    }

    Future<void> deleteDocument(Document doc) async {
      final confirm = await _showConfirmDialog(
        context,
        title: 'Supprimer le document',
        message: 'Cette action est définitive.',
      );
      if (confirm != true) return;

      final success =
          await _withLoader(context, () => repo.deleteDocument(doc.id));
      if (success && context.mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document supprimé')),
        );
      }
    }

    Future<void> openPdf(Document doc) async {
      if (doc.pdfPath == null || doc.pdfPath!.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucun PDF disponible. Génère-le d’abord.')),
        );
        return;
      }

      final uri = Uri.parse(doc.pdfPath!);
      if (!await canLaunchUrl(uri)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’ouvrir ${doc.pdfPath}')),
        );
        return;
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    Future<void> previewPdf(Document doc) async {
      if (doc.pdfPath == null || doc.pdfPath!.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucun PDF disponible. Génère-le d’abord.')),
        );
        return;
      }

      Uint8List? bytes;
      final success = await _withLoader(context, () async {
        final uri = Uri.parse(doc.pdfPath!);
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          final response = await dio.getUri(
            uri,
            options: Options(responseType: ResponseType.bytes),
          );
          bytes = Uint8List.fromList((response.data as List<int>).cast<int>());
        } else {
          if (kIsWeb) {
            throw Exception('Prévisualisation locale indisponible sur le Web');
          }
          final file = File(doc.pdfPath!);
          bytes = await file.readAsBytes();
        }
      });

      if (!success || bytes == null) {
        return;
      }

      await Printing.layoutPdf(onLayout: (_) async => bytes!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document'),
        actions: [
          documentAsync.maybeWhen(
            data: (doc) => doc == null
                ? const SizedBox.shrink()
                : IconActionButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Supprimer le document',
                    onPressed: () => deleteDocument(doc),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: documentAsync.when(
          data: (doc) {
            if (doc == null) {
              return const Center(child: Text('Document introuvable'));
            }

            final summaryBullets = _parseSummary(doc.summary);
            final statusLabel = _transcriptionStatusLabel(doc.processingStatus);
            final processingError = doc.processingError;
            final status = doc.processingStatus.toLowerCase();
            final isProcessing = status == 'processing';
            Future<void> handleTranscribe() async {
              if (isTranscribing.value) return;
              isTranscribing.value = true;
              try {
                await repo.transcribeDocument(doc.id);
                if (context.mounted) {
                  _showSnack(context, 'Transcription terminée');
                }
              } catch (error) {
                if (context.mounted) {
                  _showSnack(context, 'Erreur : $error');
                }
              } finally {
                isTranscribing.value = false;
              }
            }

            Future<void> handleGenerateCourse() async {
              isGeneratingCourse.value = true;
              try {
                final course = await api.generateCourse(doc.id, '');
                await repo.updateCachedDocument(
                  doc.copyWith(course: course, updatedAt: DateTime.now()),
                );
                if (context.mounted) {
                  _showSnack(context, 'Cours généré');
                }
              } catch (error) {
                if (context.mounted) {
                  _showSnack(context, 'Erreur : $error');
                }
              } finally {
                isGeneratingCourse.value = false;
              }
            }

            Future<void> handleGenerateSummary() async {
              isGeneratingSummary.value = true;
              try {
                const instructions =
                    'Tu es un assistant pédagogique. Résume ce cours en bullet points clairs. '
                    'Sépare Définitions, Concepts, Exemples.';
                final summary = await api.generateCourse(doc.id, instructions);
                await api.updateDocumentContent(
                  doc.id,
                  field: 'summary',
                  content: summary,
                );
                await repo.updateCachedDocument(
                  doc.copyWith(summary: summary, updatedAt: DateTime.now()),
                );
                if (context.mounted) {
                  _showSnack(context, 'Résumé généré');
                }
              } catch (error) {
                if (context.mounted) {
                  _showSnack(context, 'Erreur : $error');
                }
              } finally {
                isGeneratingSummary.value = false;
              }
            }

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: _HeaderCard(
                      document: doc,
                      statusLabel: statusLabel,
                      processingError: processingError,
                      onTranscribe: isProcessing || isTranscribing.value
                          ? null
                          : handleTranscribe,
                      onSummary:
                          doc.transcription.isEmpty || isGeneratingSummary.value
                              ? null
                              : handleGenerateSummary,
                      onGenerateCourse:
                          doc.transcription.isEmpty || isGeneratingCourse.value
                              ? null
                              : handleGenerateCourse,
                      onEdit: () => context.push('/document/${doc.id}/edit'),
                      isTranscribing: isProcessing || isTranscribing.value,
                      isGeneratingSummary: isGeneratingSummary.value,
                      isGeneratingCourse: isGeneratingCourse.value,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(
                          'Actions rapides',
                          icon: Icons.flash_on_outlined,
                          trailing: SecondaryButton(
                            label: 'Partager',
                            icon: Icons.share_outlined,
                            onPressed: () => shareDocument(doc),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SecondaryButton(
                              label: 'Générer PDF',
                              icon: Icons.picture_as_pdf_outlined,
                              onPressed: () => generatePdf(doc),
                            ),
                            SecondaryButton(
                              label: 'Prévisualiser',
                              icon: Icons.visibility_outlined,
                              onPressed: () => previewPdf(doc),
                            ),
                            SecondaryButton(
                              label: 'Ouvrir PDF',
                              icon: Icons.open_in_new,
                              onPressed: () => openPdf(doc),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        AppCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionTitle(
                                'Consignes utilisées',
                                icon: Icons.auto_awesome,
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 8),
                              InstructionsField(
                                controller: summaryPresetController,
                                enabled: false,
                                hint: '',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _ContentSection(
                          title: 'Cours généré',
                          icon: Icons.menu_book_outlined,
                          content: doc.course.isEmpty
                              ? 'Aucun cours généré pour le moment.'
                              : doc.course,
                        ),
                        const SizedBox(height: 24),
                        _SummarySection(summaryBullets: summaryBullets),
                        const SizedBox(height: 24),
                        _ContentSection(
                          title: 'Transcription complète',
                          icon: Icons.notes_outlined,
                          content: doc.transcription.isEmpty
                              ? 'Aucune transcription disponible.'
                              : doc.transcription,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Erreur : $error')),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.document,
    required this.statusLabel,
    required this.processingError,
    required this.onTranscribe,
    required this.onSummary,
    required this.onGenerateCourse,
    required this.onEdit,
    required this.isTranscribing,
    required this.isGeneratingSummary,
    required this.isGeneratingCourse,
  });

  final Document document;
  final String statusLabel;
  final String? processingError;
  final VoidCallback? onTranscribe;
  final VoidCallback? onSummary;
  final VoidCallback? onGenerateCourse;
  final VoidCallback onEdit;
  final bool isTranscribing;
  final bool isGeneratingSummary;
  final bool isGeneratingCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = document.title.isEmpty ? 'Sans titre' : document.title;
    final updatedAt = document.updatedAt.toLocal();
    final updatedLabel =
        '${updatedAt.day.toString().padLeft(2, '0')}/${updatedAt.month.toString().padLeft(2, '0')}/${updatedAt.year}';

    return AppCard(
      gradient: const LinearGradient(
        colors: [
          Color(0xFF1E3A8A),
          Color(0xFF0066FF),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mis à jour le $updatedLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle,
                        color: Color(0xFF3DD9C1), size: 10),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((processingError ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Dernière erreur : $processingError',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFFFE1E1),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              PrimaryButton(
                label:
                    isTranscribing ? 'Transcription en cours...' : 'Transcrire',
                icon: Icons.graphic_eq_outlined,
                onPressed: onTranscribe,
              ),
              SecondaryButton(
                label: isGeneratingSummary ? 'Résumé en cours...' : 'Résumer',
                icon: Icons.summarize_outlined,
                onPressed: onSummary,
              ),
              SecondaryButton(
                label: isGeneratingCourse
                    ? 'Cours en cours...'
                    : 'Générer un cours',
                icon: Icons.menu_book_outlined,
                onPressed: onGenerateCourse,
              ),
              SecondaryButton(
                label: 'Éditer',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.title,
    required this.icon,
    required this.content,
  });

  final String title;
  final IconData icon;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title,
            icon: icon,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          SelectableText(
            content,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summaryBullets});

  final List<String> summaryBullets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Résumé synthétique',
            icon: Icons.list_alt_outlined,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          if (summaryBullets.isEmpty)
            Text(
              'Aucun résumé pour le moment.',
              style: theme.textTheme.bodyMedium,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: summaryBullets
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              line,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
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

List<String> _parseSummary(String summary) {
  final lines = summary.split(RegExp(r'[\r\n]+'));
  return lines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) {
        if (line.startsWith('•')) return line.substring(1).trim();
        if (line.startsWith('-')) return line.substring(1).trim();
        return line;
      })
      .where((line) => line.isNotEmpty)
      .toList();
}

String _transcriptionStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'processing':
      return 'Transcription en cours';
    case 'completed':
      return 'Transcription terminée';
    case 'failed':
      return 'Transcription échouée';
    case 'pending':
    default:
      return 'Transcription en attente';
  }
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
