import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/io/file_stub.dart' if (dart.library.io) '../../../core/io/file_io.dart';
import '../../documents/data/documents_repo.dart';

class RecorderPage extends HookConsumerWidget {
  const RecorderPage({super.key, this.folderId});

  static const routeName = 'recorder';

  final String? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorder = useMemoized(AudioRecorder.new);
    final isRecording = useState(false);
    final elapsed = useState(Duration.zero);
    final timer = useRef<Timer?>(null);
    final repo = ref.watch(documentsRepositoryProvider);

    Future<void> startRecording() async {
      if (!context.mounted) return;
      if (kIsWeb) {
        _showSnack(context, 'Enregistrement non disponible sur le Web.');
        return;
      }

      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        _showSnack(context, 'Permission micro refusée');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
        ),
        path: path,
      );

      isRecording.value = true;
      elapsed.value = Duration.zero;
      timer.value?.cancel();
      timer.value = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed.value += const Duration(seconds: 1);
      });
    }

    Future<void> stopRecording() async {
      final path = await recorder.stop();
      timer.value?.cancel();
      isRecording.value = false;

      if (path == null || path.isEmpty) {
        _showSnack(context, 'Enregistrement annulé.');
        return;
      }

      _showSnack(context, 'Transcription en cours…');
      try {
        final folder = folderId;
        if (folder == null || folder.isEmpty) {
          _showSnack(context, 'Impossible d’associer le document à un dossier.');
          return;
        }

        final file = File(path);
        await repo.uploadDocument(folderId: folder, file: file);
        if (context.mounted) {
          _showSnack(context, 'Résumé généré.');
          context.pop();
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(context, 'Erreur pendant le téléversement: $error');
        }
      }
    }

    useEffect(() {
      return () {
        timer.value?.cancel();
        recorder.dispose();
      };
    }, const []);

    final minutes = elapsed.value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.value.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('Enregistreur')), 
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$minutes:$seconds', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: isRecording.value ? stopRecording : startRecording,
              child: Text(isRecording.value ? 'Stop' : 'Start'),
            ),
            const SizedBox(height: 16),
            Text(isRecording.value ? 'Enregistrement…' : 'Prêt à enregistrer'),
          ],
        ),
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
