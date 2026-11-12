import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera/data/models/location_model.dart';
import 'package:gps_camera/data/models/photo_metadata_model.dart';
import 'package:gps_camera/data/models/photo_model.dart';
import 'package:gps_camera/data/models/stamp_template_model.dart';
import 'package:gps_camera/data/models/stamp_values.dart';
import 'package:gps_camera/features/exif_editor/services/exif_service.dart';
import 'package:gps_camera/features/templates/services/default_templates.dart';

void main() {
  group('PhotoMetadataModel', () {
    test('parses native map including references and rational GPS time', () {
      final m = PhotoMetadataModel.fromNative({
        'dateTimeOriginal': '2026:11:12 09:30:15',
        'gpsLatitude': -33.8688,
        'gpsLongitude': 151.2093,
        'gpsAltitude': -2.5,
        'gpsTimeStamp': '23/1,5/1,9/1',
        'userComment': 'ASCII\u0000\u0000\u0000hello',
        'format': 'jpeg',
        'writeSupported': true,
        'rawTags': {'Make': 'Acme'},
      });
      expect(m.dateTimeOriginal, DateTime(2026, 11, 12, 9, 30, 15));
      expect(m.latitudeReference, 'S');
      expect(m.longitudeReference, 'E');
      expect(m.altitudeReference, 1);
      expect(m.gpsTimeStamp, '23:05:09');
      expect(m.userComment, 'hello');
      expect(m.writeSupported, isTrue);
      expect(m.rawTags['Make'], 'Acme');
    });

    test('ignores zeroed EXIF dates', () {
      expect(PhotoMetadataModel.parseExifDate('0000:00:00 00:00:00'), isNull);
    });

    test('sameField uses tolerances for numbers', () {
      const a = PhotoMetadataModel(latitude: 10.0000001, longitude: 20, altitude: 100.01);
      const b = PhotoMetadataModel(latitude: 10.0, longitude: 20, altitude: 100.0);
      expect(a.sameField(ExifField.gpsCoordinates, b), isTrue);
      expect(a.sameField(ExifField.gpsAltitude, b), isTrue);
      const c = PhotoMetadataModel(latitude: 10.001, longitude: 20);
      expect(c.sameField(ExifField.gpsCoordinates, b), isFalse);
    });

    test('offset formatting and validation', () {
      expect(PhotoMetadataModel.formatOffset(const Duration(hours: 5, minutes: 30)), '+05:30');
      expect(PhotoMetadataModel.formatOffset(const Duration(hours: -3)), '-03:00');
      expect(PhotoMetadataModel.isValidOffset('+05:30'), isTrue);
      expect(PhotoMetadataModel.isValidOffset('5:30'), isFalse);
    });
  });

  group('ExifService.validate', () {
    test('rejects non-ASCII in ASCII-only fields', () {
      const m = PhotoMetadataModel(artist: 'José');
      expect(ExifService.validate(ExifField.artist, m), isNotNull);
      expect(ExifService.validate(ExifField.artist, const PhotoMetadataModel(artist: 'Jose')), isNull);
    });

    test('requires both coordinates and valid ranges', () {
      expect(ExifService.validate(ExifField.gpsCoordinates, const PhotoMetadataModel(latitude: 10)), isNotNull);
      expect(ExifService.validate(ExifField.gpsCoordinates, const PhotoMetadataModel(latitude: 95, longitude: 1)),
          isNotNull);
      expect(ExifService.validate(ExifField.gpsCoordinates, const PhotoMetadataModel(latitude: 45, longitude: 1)),
          isNull);
    });

    test('checks GPS date/time formats', () {
      expect(ExifService.validate(ExifField.gpsDateStamp, const PhotoMetadataModel(gpsDateStamp: '2026-11-12')),
          isNotNull);
      expect(ExifService.validate(ExifField.gpsTimeStamp, const PhotoMetadataModel(gpsTimeStamp: '24:00:00')),
          isNotNull);
      expect(ExifService.validate(ExifField.gpsTimeStamp, const PhotoMetadataModel(gpsTimeStamp: '23:59:59')), isNull);
    });
  });

  group('StampTemplateModel', () {
    test('JSON round trip preserves all built-ins', () {
      for (final t in DefaultTemplates.all) {
        final back = StampTemplateModel.fromJson(t.toJson());
        expect(back.toJson(), t.toJson(), reason: t.name);
      }
    });

    test('there are 8 built-in templates with unique ids', () {
      expect(DefaultTemplates.all.length, 8);
      expect(DefaultTemplates.all.map((t) => t.id).toSet().length, 8);
    });

    test('toggleField keeps map flag consistent', () {
      final t = DefaultTemplates.all.first.toggleField(StampField.map, true);
      expect(t.includesMap, isTrue);
      expect(t.toggleField(StampField.map, false).includesMap, isFalse);
    });
  });

  group('PhotoModel', () {
    test('row round trip keeps the three value sets separate', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1762939815000);
      final p = PhotoModel(
        id: 'a',
        originalFilePath: '/o.jpg',
        editedFilePath: '/e.jpg',
        createdAt: now,
        updatedAt: now,
        capturedAt: now,
        detectedLocation: const LocationModel(latitude: 1, longitude: 2, city: 'Detected', source: LocationSource.gps),
        stampValues: const StampValues(values: {StampField.city: 'Typed by user'}),
        exifEdits: const PhotoMetadataModel(latitude: 3, longitude: 4),
        exifOverrides: const {ExifField.gpsCoordinates, ExifField.artist},
        exifStatus: ExifStatus.verified,
        addressPending: true,
      );
      final back = PhotoModel.fromRow(p.toRow());
      expect(back.detectedLocation!.city, 'Detected');
      expect(back.stampValues![StampField.city], 'Typed by user');
      expect(back.exifEdits!.latitude, 3);
      expect(back.exifOverrides, {ExifField.gpsCoordinates, ExifField.artist});
      expect(back.exifStatus, ExifStatus.verified);
      expect(back.addressPending, isTrue);
      expect(back.displayPath, '/e.jpg');
    });
  });
}
