import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera/core/utils/formatters.dart';
import 'package:gps_camera/data/models/app_settings.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  group('coordinate formatting', () {
    test('decimal keeps 6 decimals and hemisphere', () {
      expect(Fmt.latitude(12.9715987, CoordinateFormat.decimal), '12.971599° N');
      expect(Fmt.longitude(-77.5945627, CoordinateFormat.decimal), '77.594563° W');
      expect(Fmt.latitude(-33.8688, CoordinateFormat.decimal), '33.868800° S');
    });

    test('DMS rounds seconds without producing 60"', () {
      expect(Fmt.latitude(12.9715987, CoordinateFormat.dms), '12°58\'17.8" N');
      // 10.9999999° would naively render as 10°59'60.0"
      expect(Fmt.latitude(10.9999999, CoordinateFormat.dms), '11°0\'0.0" N');
    });

    test('DDM', () {
      expect(Fmt.longitude(77.5945627, CoordinateFormat.ddm), '77°35.674\' E');
    });
  });

  group('coordinate parsing', () {
    test('signed decimal', () {
      expect(Fmt.parseCoordinate('-33.8688', isLatitude: true), closeTo(-33.8688, 1e-9));
    });

    test('decimal with hemisphere letter', () {
      expect(Fmt.parseCoordinate('33.8688 S', isLatitude: true), closeTo(-33.8688, 1e-9));
      expect(Fmt.parseCoordinate('151.2093° E', isLatitude: false), closeTo(151.2093, 1e-9));
    });

    test('DMS round trip is precise to < 1e-4 degrees', () {
      const v = 12.9715987;
      final text = Fmt.latitude(v, CoordinateFormat.dms);
      expect(Fmt.parseCoordinate(text, isLatitude: true), closeTo(v, 1e-4));
    });

    test('stamp labels like "Lat" do not flip hemisphere', () {
      expect(Fmt.parseCoordinate('Lat 12.5° N', isLatitude: true), closeTo(12.5, 1e-9));
      expect(Fmt.parseCoordinate('Long 77.1° W', isLatitude: false), closeTo(-77.1, 1e-9));
    });

    test('rejects out-of-range and garbage', () {
      expect(Fmt.parseCoordinate('91', isLatitude: true), isNull);
      expect(Fmt.parseCoordinate('181', isLatitude: false), isNull);
      expect(Fmt.parseCoordinate('hello', isLatitude: true), isNull);
      expect(Fmt.parseCoordinate('', isLatitude: true), isNull);
      expect(Fmt.parseCoordinate('12 75 0', isLatitude: true), isNull); // minutes >= 60
    });
  });

  group('altitude', () {
    test('format honours units and unavailable', () {
      expect(Fmt.altitude(920.04, AltitudeUnit.metres), '920.0 m');
      expect(Fmt.altitude(100, AltitudeUnit.feet), '328 ft');
      expect(Fmt.altitude(null, AltitudeUnit.metres), 'Altitude unavailable');
    });

    test('parse handles units', () {
      expect(Fmt.parseAltitude('920 m', AltitudeUnit.feet), closeTo(920, 1e-9));
      expect(Fmt.parseAltitude('328 ft', AltitudeUnit.metres), closeTo(99.97, 0.01));
      expect(Fmt.parseAltitude('328', AltitudeUnit.feet), closeTo(99.97, 0.01));
      expect(Fmt.parseAltitude('-12.5', AltitudeUnit.metres), closeTo(-12.5, 1e-9));
      expect(Fmt.parseAltitude('Altitude unavailable', AltitudeUnit.metres), isNull);
    });
  });

  group('time parsing', () {
    test('24h and 12h forms', () {
      expect(Fmt.parseTime('14:05:09'), (h: 14, m: 5, s: 9));
      expect(Fmt.parseTime('02:05 pm'), (h: 14, m: 5, s: 0));
      expect(Fmt.parseTime('12:00:00 AM'), (h: 0, m: 0, s: 0));
      expect(Fmt.parseTime('25:00'), isNull);
    });
  });

  group('date parsing', () {
    test('uses the configured format first', () {
      const s = AppSettings(dateFormat: 'MM/dd/yyyy');
      final d = Fmt.parseDate('03/04/2026', s)!;
      expect((d.year, d.month, d.day), (2026, 3, 4));
    });

    test('formats round-trip', () {
      const s = AppSettings(dateFormat: 'dd MMM yyyy', localeCode: 'en');
      final when = DateTime(2026, 11, 12, 9, 30);
      final d = Fmt.parseDate(Fmt.date(when, s), s)!;
      expect((d.year, d.month, d.day), (2026, 11, 12));
    });
  });
}
