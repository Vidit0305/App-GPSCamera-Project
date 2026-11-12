import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/location_model.dart';
import '../features/camera/screens/camera_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/map_location/screens/map_location_screen.dart';
import '../features/photo_editor/screens/photo_editor_screen.dart';

/// Route paths. The app has a single main screen (Home); the camera, the
/// photo editor and the map picker open on top of it.
abstract final class Routes {
  static const home = '/';
  static const camera = '/camera';
  static const mapLocation = '/map-location';

  /// `/editor/:id?tab=stamp|style|exif&fresh=1`
  static String editor(String id, {String? tab, bool fresh = false}) =>
      Uri(path: '/editor/$id', queryParameters: {'tab': ?tab, if (fresh) 'fresh': '1'}).toString();
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(path: Routes.camera, builder: (_, _) => const CameraScreen()),
      GoRoute(
        path: '/editor/:id',
        builder: (_, s) => PhotoEditorScreen(
          photoId: s.pathParameters['id']!,
          initialTab: s.uri.queryParameters['tab'],
          isNewCapture: s.uri.queryParameters['fresh'] == '1',
        ),
      ),
      GoRoute(
        path: Routes.mapLocation,
        builder: (_, s) => MapLocationScreen(initial: s.extra is LocationModel ? s.extra as LocationModel : null),
      ),
    ],
  );
});
