import '../models/location_model.dart';

/// A search hit from forward geocoding.
class PlaceResult {
  const PlaceResult({required this.latitude, required this.longitude, required this.title, this.subtitle, this.address});

  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
  final AddressModel? address;
}

/// Provider abstraction so the geocoding backend can be swapped without
/// touching the rest of the app.
abstract interface class GeocodingProvider {
  String get name;

  /// Converts coordinates to an address. Returns null when nothing was found.
  /// Throws on network / service errors.
  Future<AddressModel?> reverse(double latitude, double longitude, {String? languageCode});

  /// Searches places by free text.
  Future<List<PlaceResult>> search(String query, {String? languageCode});
}
