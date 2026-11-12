import 'package:dio/dio.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../models/location_model.dart';
import 'geocoding_provider.dart';

/// Nominatim-compatible HTTP geocoder (OSM Nominatim, self-hosted, or a
/// compatible provider configured via GEOCODER_BASE_URL / GEOCODER_API_KEY).
class NominatimGeocodingProvider implements GeocodingProvider {
  NominatimGeocodingProvider(this._dio);

  final Dio _dio;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get name => 'OpenStreetMap Nominatim';

  /// Public Nominatim allows at most one request per second.
  Future<void> _throttle() async {
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_lastRequest);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _lastRequest = DateTime.now();
  }

  Map<String, dynamic> _baseParams(String? languageCode) => {
        'format': 'jsonv2',
        'addressdetails': 1,
        'accept-language': ?languageCode,
        if (Env.geocoderApiKey.isNotEmpty) 'key': Env.geocoderApiKey,
        if (Env.geocoderContactEmail.isNotEmpty) 'email': Env.geocoderContactEmail,
      };

  static String? _s(Map a, List<String> keys) {
    for (final k in keys) {
      final v = a[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  AddressModel _map(Map<String, dynamic> json) {
    final a = (json['address'] as Map?) ?? const {};
    return AddressModel(
      street: _s(a, ['road', 'pedestrian', 'footway', 'street']),
      buildingNumber: _s(a, ['house_number']),
      area: _s(a, ['neighbourhood', 'suburb', 'quarter', 'residential']),
      locality: _s(a, ['suburb', 'city_district', 'village', 'town', 'hamlet']),
      subLocality: _s(a, ['neighbourhood', 'quarter']),
      city: _s(a, ['city', 'town', 'village', 'municipality', 'hamlet']),
      district: _s(a, ['state_district', 'county', 'district']),
      state: _s(a, ['state', 'region', 'province']),
      postalCode: _s(a, ['postcode']),
      country: _s(a, ['country']),
      countryCode: _s(a, ['country_code'])?.toUpperCase(),
      fullAddress: json['display_name'] as String?,
      provider: name,
    );
  }

  @override
  Future<AddressModel?> reverse(double latitude, double longitude, {String? languageCode}) async {
    await _throttle();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${Env.geocoderBaseUrl}/reverse',
        queryParameters: {..._baseParams(languageCode), 'lat': latitude, 'lon': longitude, 'zoom': 18},
      );
      final data = res.data;
      if (data == null || data['error'] != null) return null;
      return _map(data);
    } on DioException catch (e) {
      throw _error(e, 'Address lookup failed');
    }
  }

  @override
  Future<List<PlaceResult>> search(String query, {String? languageCode}) async {
    await _throttle();
    try {
      final res = await _dio.get<List<dynamic>>(
        '${Env.geocoderBaseUrl}/search',
        queryParameters: {..._baseParams(languageCode), 'q': query, 'limit': 8},
      );
      return (res.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((j) {
            final lat = double.tryParse('${j['lat']}');
            final lon = double.tryParse('${j['lon']}');
            if (lat == null || lon == null) return null;
            final a = _map(j);
            return PlaceResult(
              latitude: lat,
              longitude: lon,
              title: (j['name'] as String?)?.isNotEmpty == true ? j['name'] as String : (a.city ?? query),
              subtitle: a.fullAddress,
              address: a,
            );
          })
          .whereType<PlaceResult>()
          .toList();
    } on DioException catch (e) {
      throw _error(e, 'Search failed');
    }
  }

  AppException _error(DioException e, String context) {
    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout;
    if (offline) {
      return AppException(AppErrorKind.offline, '$context: no internet connection.', cause: e);
    }
    final code = e.response?.statusCode;
    if (code == 429) {
      return AppException(AppErrorKind.geocoding, '$context: rate limited by the geocoding service. Try again shortly.',
          cause: e);
    }
    return AppException(AppErrorKind.geocoding, '$context (${code ?? e.type.name}).', cause: e);
  }
}
