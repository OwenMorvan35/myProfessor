import 'dart:typed_data';

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
import '../../../core/io/file_stub.dart' if (dart.library.io) '../../../core/io/file_io.dart';
import '../data/documents_repo.dart';
import '../data/document.dart';

class DocumentPage extends HookConsumerWidget {
  const DocumentPage({super.key, required this.documentId});

  final String documentId;

  static const routeName = 'document';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);
    final dio = ref.read(dioProvider);
    final documentAsync = ref.watch(documentStreamProvider(documentId));

    useEffect(() {
      Future.microtask(() => repo.getDocument(documentId));
      return null;
    }, [documentId]);

    Future<void> generatePdf(Document doc) async {
      String? pdfPath;
      final success = await _withLoader(context, () async {
        pdfPath = await repo.generatePdf(doc.id);
      });

      if (!success || !context.mounted || pdfPath == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pdfPath!.isEmpty ? 'PDF indisponible' : 'PDF généré: $pdfPath')),
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
          SnackBar(content: Text('Lien copié et ${Env.shareOpenInBrowser ? 'ouvert dans le navigateur' : 'prêt à partager'}')),
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

      final success = await _withLoader(context, () => repo.deleteDocument(doc.id));
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
          const SnackBar(content: Text('Aucun PDF disponible. Génère-le d’abord.')),
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
          const SnackBar(content: Text('Aucun PDF disponible. Génère-le d’abord.')),
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
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => deleteDocument(doc),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: documentAsync.when(
          data: (doc) {
            if (doc == null) {
              return const Center(child: Text('Document introuvable'));
            }

            final summaryBullets = _parseSummary(doc.summary);

            return ListView(
              children: [
                Text(
                  doc.title.isEmpty ? 'Sans titre' : doc.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => generatePdf(doc),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Générer PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => previewPdf(doc),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Prévisualiser'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => openPdf(doc),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Ouvrir PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => shareDocument(doc),
                      icon: const Icon(Icons.share),
                      label: const Text('Partager'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Résumé', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (summaryBullets.isEmpty)
                  const Text('Aucun résumé pour le moment.')
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: summaryBullets
                        .map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(line)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 24),
                Text('Transcription', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                SelectableText(doc.transcription.isEmpty ? 'Aucune transcription disponible.' : doc.transcription),
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
