import 'package:intl/intl.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/weather_model.dart';

/// Formatting and parsing helpers for coordinates, units and dates.
abstract final class Fmt {
  static const _feetPerMetre = 3.28084;

  // ---------------------------------------------------------------- coordinates

  static String latitude(double v, CoordinateFormat f) => _coord(v, f, v >= 0 ? 'N' : 'S');
  static String longitude(double v, CoordinateFormat f) => _coord(v, f, v >= 0 ? 'E' : 'W');

  static String _coord(double v, CoordinateFormat f, String hemi) {
    final a = v.abs();
    switch (f) {
      case CoordinateFormat.decimal:
        return '${a.toStringAsFixed(6)}° $hemi';
      case CoordinateFormat.dms:
        var deg = a.floor();
        final minFull = (a - deg) * 60;
        var min = minFull.floor();
        var sec = double.parse(((minFull - min) * 60).toStringAsFixed(1));
        if (sec >= 60) {
          sec = 0;
          min += 1;
        }
        if (min >= 60) {
          min = 0;
          deg += 1;
        }
        return '$deg°$min\'${sec.toStringAsFixed(1)}" $hemi';
      case CoordinateFormat.ddm:
        final deg = a.floor();
        final min = (a - deg) * 60;
        return '$deg°${min.toStringAsFixed(3)}\' $hemi';
    }
  }

  static String latLng(double lat, double lon, CoordinateFormat f) => '${latitude(lat, f)}, ${longitude(lon, f)}';

  /// Parses decimal ("-12.5", "12.5 S"), DMS ("12°30'15.2\"S") or DDM text into
  /// signed decimal degrees. Returns null if the text is not a coordinate.
  static double? parseCoordinate(String input, {required bool isLatitude}) {
    final s = input.trim().toUpperCase();
    if (s.isEmpty) return null;
    final nums = RegExp(r'-?\d+(?:[.,]\d+)?').allMatches(s).map((m) => double.parse(m[0]!.replaceAll(',', '.'))).toList();
    if (nums.isEmpty || nums.length > 3) return null;
    var negative = nums.first < 0;
    var value = nums.first.abs();
    if (nums.length >= 2) {
      if (nums[1] < 0 || nums[1] >= 60) return null;
      value += nums[1] / 60;
    }
    if (nums.length == 3) {
      if (nums[2] < 0 || nums[2] >= 60) return null;
      value += nums[2] / 3600;
    }
    final hemis = isLatitude ? ['N', 'S'] : ['E', 'W'];
    // Ignore any "LAT"/"LONG" labels when looking for hemisphere letters.
    final letters = s.replaceAll(RegExp(r'LAT(ITUDE)?|LONG?(ITUDE)?|LNG'), '');
    if (letters.contains(hemis[1])) negative = true;
    if (letters.contains(hemis[0])) negative = false;
    final out = negative ? -value : value;
    final limit = isLatitude ? 90 : 180;
    if (out.abs() > limit) return null;
    return out;
  }

  // ---------------------------------------------------------------- units

  static String altitude(double? metres, AltitudeUnit unit, {bool unavailableText = true}) {
    if (metres == null) return unavailableText ? 'Altitude unavailable' : '';
    return unit == AltitudeUnit.metres
        ? '${metres.toStringAsFixed(1)} m'
        : '${(metres * _feetPerMetre).toStringAsFixed(0)} ft';
  }

  /// Parses "920 m", "3018 ft", "920" (assumed [unit]) into metres.
  static double? parseAltitude(String input, AltitudeUnit unit) {
    final s = input.trim().toLowerCase();
    final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(s);
    if (m == null) return null;
    final v = double.parse(m[0]!.replaceAll(',', '.'));
    final isFeet = s.contains('ft') || s.contains('feet') || (!s.contains('m') && unit == AltitudeUnit.feet);
    return isFeet ? v / _feetPerMetre : v;
  }

  static String accuracy(double? metres, DistanceUnit unit) {
    if (metres == null) return 'Accuracy unknown';
    return unit == DistanceUnit.metric
        ? '±${metres.toStringAsFixed(metres < 10 ? 1 : 0)} m'
        : '±${(metres * _feetPerMetre).toStringAsFixed(0)} ft';
  }

  static String speed(double? mps, DistanceUnit unit) {
    if (mps == null) return 'Unavailable';
    return unit == DistanceUnit.metric
        ? '${(mps * 3.6).toStringAsFixed(1)} km/h'
        : '${(mps * 2.23694).toStringAsFixed(1)} mph';
  }

  static String heading(double? deg) {
    if (deg == null) return 'Unavailable';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return '${deg.toStringAsFixed(0)}° ${dirs[((deg % 360) / 45).round() % 8]}';
  }

  static String temperature(double celsius, TemperatureUnit unit) => unit == TemperatureUnit.celsius
      ? '${celsius.toStringAsFixed(1)} °C'
      : '${(celsius * 9 / 5 + 32).toStringAsFixed(1)} °F';

  static String weather(WeatherModel w) => w.description;

  static String fileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ---------------------------------------------------------------- dates

  static String date(DateTime d, AppSettings s) => DateFormat(s.dateFormat, _locale(s)).format(d);
  static String time(DateTime d, AppSettings s) => DateFormat(s.timeFormat, _locale(s)).format(d);
  static String timeShort(DateTime d, AppSettings s) =>
      DateFormat(s.use24Hour ? 'HH:mm' : 'hh:mm a', _locale(s)).format(d);
  static String dateTime(DateTime d, AppSettings s) => '${date(d, s)} ${timeShort(d, s)}';

  /// Group header label for gallery sections.
  static String dayHeader(DateTime d, AppSettings s) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, d MMMM yyyy', _locale(s)).format(d);
  }

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  /// Tries the user's date format, then common fallbacks.
  static DateTime? parseDate(String input, AppSettings s) {
    final t = input.trim();
    if (t.isEmpty) return null;
    for (final p in [s.dateFormat, ...dateFormatOptions, 'yyyy:MM:dd', 'd/M/yyyy', 'M/d/yyyy']) {
      try {
        return DateFormat(p, _locale(s)).parseStrict(t);
      } catch (_) {}
    }
    return DateTime.tryParse(t);
  }

  static ({int h, int m, int s})? parseTime(String input) {
    final t = input.trim().toLowerCase();
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?\s*(am|pm)?$').firstMatch(t);
    if (m == null) return null;
    var h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    final sec = int.tryParse(m[3] ?? '0') ?? 0;
    final ampm = m[4];
    if (ampm != null) {
      if (h < 1 || h > 12) return null;
      if (ampm == 'pm' && h != 12) h += 12;
      if (ampm == 'am' && h == 12) h = 0;
    }
    if (h > 23 || min > 59 || sec > 59) return null;
    return (h: h, m: min, s: sec);
  }

  static String? _locale(AppSettings s) => s.locale?.languageCode;
}
