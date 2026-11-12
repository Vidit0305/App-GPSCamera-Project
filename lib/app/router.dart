import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/location_model.dart';
import '../features/batch_editor/screens/batch_editor_screen.dart';
import '../features/camera/screens/camera_screen.dart';
import '../features/gallery/screens/gallery_screen.dart';
import '../features/gallery/screens/photo_details_screen.dart';
import '../features/gallery/screens/photo_picker_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/map_location/screens/map_location_screen.dart';
import '../features/photo_editor/screens/photo_editor_screen.dart';
import '../features/settings/screens/legal_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/templates/screens/template_editor_screen.dart';
import '../features/templates/screens/templates_screen.dart';

/// Route paths used across the app.
abstract final class Routes {
  static const home = '/';
  static const gallery = '/gallery';
  static const templates = '/templates';
  static const settings = '/settings';
  static const camera = '/camera';
  static const batch = '/batch';
  static const mapLocation = '/map-location';
  static const templateEditor = '/template-editor';

  /// `/editor/:id?tab=stamp|style|exif&fresh=1`
  static String editor(String id, {String? tab, bool fresh = false}) =>
      Uri(path: '/editor/$id', queryParameters: {'tab': ?tab, if (fresh) 'fresh': '1'}).toString();

  static String photo(String id) => '/photo/$id';

  /// `/pick?purpose=exif|stamp`
  static String pick(String purpose) => '/pick?purpose=$purpose';

  /// `/template-editor?id=..` edits; `?base=..` creates from a base template.
  static String editTemplate({String? id, String? base}) =>
      Uri(path: templateEditor, queryParameters: {'id': ?id, 'base': ?base}).toString();

  static String legal(String doc) => '/legal/$doc';
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.gallery, builder: (_, _) => const GalleryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.templates, builder: (_, _) => const TemplatesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen())]),
        ],
      ),
      GoRoute(
        path: Routes.camera,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CameraScreen(),
      ),
      GoRoute(
        path: '/editor/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PhotoEditorScreen(
          photoId: s.pathParameters['id']!,
          initialTab: s.uri.queryParameters['tab'],
          isNewCapture: s.uri.queryParameters['fresh'] == '1',
        ),
      ),
      GoRoute(
        path: '/photo/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PhotoDetailsScreen(photoId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pick',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PhotoPickerScreen(purpose: s.uri.queryParameters['purpose'] ?? 'exif'),
      ),
      GoRoute(
        path: Routes.batch,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BatchEditorScreen(),
      ),
      GoRoute(
        path: Routes.mapLocation,
        parentNavigatorKey: _rootKey,
        builder: (_, s) => MapLocationScreen(initial: s.extra is LocationModel ? s.extra as LocationModel : null),
      ),
      GoRoute(
        path: Routes.templateEditor,
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TemplateEditorScreen(
          templateId: s.uri.queryParameters['id'],
          baseTemplateId: s.uri.queryParameters['base'],
        ),
      ),
      GoRoute(
        path: '/legal/:doc',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => LegalScreen(doc: s.pathParameters['doc']!),
      ),
    ],
  );
});

/// Bottom navigation: Home, Gallery, Camera (opens full-screen), Templates, Settings.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _branchForIndex = [0, 1, -1, 2, 3];

  int get _selected => switch (shell.currentIndex) { 0 => 0, 1 => 1, 2 => 3, _ => 4 };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (i) {
          final branch = _branchForIndex[i];
          if (branch < 0) {
            context.push(Routes.camera);
          } else {
            shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
          }
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Gallery'),
          NavigationDestination(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.photo_camera, color: Theme.of(context).colorScheme.onSecondary, size: 22),
            ),
            label: 'Camera',
          ),
          const NavigationDestination(
              icon: Icon(Icons.dashboard_customize_outlined),
              selectedIcon: Icon(Icons.dashboard_customize),
              label: 'Templates'),
          const NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
