import 'package:dio/dio.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../models/weather_model.dart';

/// Current conditions from an Open-Meteo compatible API (no API key needed).
class WeatherService {
  WeatherService(this._dio);

  final Dio _dio;
  ({double lat, double lon, WeatherModel w})? _cache;

  Future<WeatherModel> current(double lat, double lon) async {
    final c = _cache;
    if (c != null &&
        (c.lat - lat).abs() < 0.02 &&
        (c.lon - lon).abs() < 0.02 &&
        DateTime.now().difference(c.w.observedAt) < const Duration(minutes: 20)) {
      return c.w;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(Env.weatherBaseUrl, queryParameters: {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code',
      });
      final cur = res.data?['current'] as Map<String, dynamic>?;
      if (cur == null || cur['temperature_2m'] == null) {
        throw const AppException(AppErrorKind.unknown, 'Weather service returned no data.');
      }
      final w = WeatherModel(
        temperatureC: (cur['temperature_2m'] as num).toDouble(),
        code: (cur['weather_code'] as num?)?.toInt() ?? -1,
        observedAt: DateTime.now(),
      );
      _cache = (lat: lat, lon: lon, w: w);
      return w;
    } on DioException catch (e) {
      throw AppException(AppErrorKind.offline, 'Weather unavailable (${e.type.name}).', cause: e);
    }
  }
}
