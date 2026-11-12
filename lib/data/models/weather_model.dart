/// Current weather at a location (fetched online only, with consent).
class WeatherModel {
  const WeatherModel({required this.temperatureC, required this.code, required this.observedAt});

  final double temperatureC;

  /// WMO weather interpretation code.
  final int code;
  final DateTime observedAt;

  double get temperatureF => temperatureC * 9 / 5 + 32;

  String get description => describe(code);

  static String describe(int code) {
    if (code == 0) return 'Clear sky';
    if (code == 1) return 'Mainly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code == 85 || code == 86) return 'Snow showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Unknown';
  }

  Map<String, dynamic> toJson() =>
      {'temperatureC': temperatureC, 'code': code, 'observedAt': observedAt.toIso8601String()};

  factory WeatherModel.fromJson(Map<String, dynamic> j) => WeatherModel(
        temperatureC: (j['temperatureC'] as num).toDouble(),
        code: (j['code'] as num).toInt(),
        observedAt: DateTime.tryParse(j['observedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
