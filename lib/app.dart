import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'core/theme.dart';
import 'features/documents/ui/document_page.dart';
import 'features/folders/ui/folder_page.dart';
import 'features/folders/ui/home_page.dart';
import 'features/recorder/ui/recorder_page.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: HomePage.routeName,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/folder/:id',
        name: FolderPage.routeName,
        builder: (context, state) => FolderPage(folderId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/document/:id',
        name: DocumentPage.routeName,
        builder: (context, state) => DocumentPage(documentId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/recorder',
        name: RecorderPage.routeName,
        builder: (context, state) => RecorderPage(folderId: state.uri.queryParameters['folderId']),
      ),
    ],
  );
});

class App extends HookConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: 'Cours AI',
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
