import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart' as geo;

import '../../core/errors/app_exception.dart';
import '../models/location_model.dart';
import 'geocoding_provider.dart';

/// Uses the operating system geocoder (Google on Android, Apple on iOS).
/// Both require network access.
class PlatformGeocodingProvider implements GeocodingProvider {
  @override
  String get name => 'Device geocoder';

  geo.Geocoding _client(String? languageCode) =>
      geo.Geocoding(locale: languageCode == null ? null : Locale(languageCode));

  static String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  AddressModel _map(geo.Placemark p) {
    final street = _clean(p.thoroughfare) ?? _clean(p.street);
    final number = _clean(p.subThoroughfare);
    final parts = <String>[];
    void add(String? s) {
      if (s != null && s.isNotEmpty && !parts.contains(s)) parts.add(s);
    }

    add([number, street].whereType<String>().join(' ').trim().isEmpty
        ? null
        : [number, street].whereType<String>().join(' '));
    add(_clean(p.subLocality));
    add(_clean(p.locality));
    add(_clean(p.subAdministrativeArea));
    add([_clean(p.administrativeArea), _clean(p.postalCode)].whereType<String>().join(' '));
    add(_clean(p.country));
    return AddressModel(
      street: street,
      buildingNumber: number,
      area: _clean(p.subLocality),
      locality: _clean(p.locality),
      subLocality: _clean(p.subLocality),
      city: _clean(p.locality) ?? _clean(p.subAdministrativeArea),
      district: _clean(p.subAdministrativeArea),
      state: _clean(p.administrativeArea),
      postalCode: _clean(p.postalCode),
      country: _clean(p.country),
      countryCode: _clean(p.isoCountryCode),
      fullAddress: parts.join(', '),
      provider: name,
    );
  }

  @override
  Future<AddressModel?> reverse(double latitude, double longitude, {String? languageCode}) async {
    try {
      final client = _client(languageCode);
      if (!await client.isPresent()) {
        throw const AppException(AppErrorKind.geocoding, 'No geocoder is available on this device.');
      }
      final marks = await client.placemarkFromCoordinates(latitude, longitude);
      if (marks.isEmpty) return null;
      return _map(marks.first);
    } on PlatformException catch (e) {
      if (e.code.toUpperCase().contains('NOT_FOUND')) return null;
      throw AppException.from(e, fallback: AppErrorKind.geocoding, context: 'Address lookup failed');
    } catch (e) {
      throw AppException.from(e, fallback: AppErrorKind.geocoding, context: 'Address lookup failed');
    }
  }

  @override
  Future<List<PlaceResult>> search(String query, {String? languageCode}) async {
    try {
      final client = _client(languageCode);
      final locations = await client.locationFromAddress(query);
      final results = <PlaceResult>[];
      for (final l in locations.take(5)) {
        AddressModel? a;
        try {
          a = await reverse(l.latitude, l.longitude, languageCode: languageCode);
        } catch (_) {}
        results.add(PlaceResult(
          latitude: l.latitude,
          longitude: l.longitude,
          title: a?.city ?? a?.locality ?? query,
          subtitle: a?.fullAddress,
          address: a,
        ));
      }
      return results;
    } on PlatformException catch (e) {
      if (e.code.toUpperCase().contains('NOT_FOUND')) return const [];
      throw AppException.from(e, fallback: AppErrorKind.geocoding, context: 'Search failed');
    } catch (e) {
      throw AppException.from(e, fallback: AppErrorKind.geocoding, context: 'Search failed');
    }
  }
}
