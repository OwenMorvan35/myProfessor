import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app.dart';
import 'features/documents/data/document.dart';
import 'features/folders/data/folder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env').catchError((error) {
    debugPrint('dotenv loading failed: $error');
  });

  await Hive.initFlutter();

  if (!Hive.isAdapterRegistered(FolderAdapter().typeId)) {
    Hive.registerAdapter(FolderAdapter());
  }
  if (!Hive.isAdapterRegistered(DocumentAdapter().typeId)) {
    Hive.registerAdapter(DocumentAdapter());
  }

  await Hive.openBox<Folder>('folders');
  await Hive.openBox<Document>('documents');

  runApp(const ProviderScope(child: App()));
}
