/// Every piece of information that can appear in a visible stamp.
enum StampField {
  date('Date'),
  time('Time'),
  city('City'),
  area('Area'),
  locality('Locality'),
  street('Street'),
  district('District'),
  state('State'),
  country('Country'),
  postalCode('Postal code'),
  fullAddress('Full address'),
  latitude('Latitude'),
  longitude('Longitude'),
  altitude('Altitude'),
  accuracy('GPS accuracy'),
  weather('Weather'),
  temperature('Temperature'),
  note('Custom note'),
  map('Map snapshot');

  const StampField(this.label);
  final String label;

  bool get isText => this != map;

  static StampField? tryParse(String v) {
    for (final f in values) {
      if (f.name == v) return f;
    }
    return null;
  }
}

/// The text values shown on a visible stamp. These are free text: the user
/// can type anything, independent of detected GPS data or EXIF metadata.
class StampValues {
  const StampValues({this.values = const {}, this.mapLatitude, this.mapLongitude});

  final Map<StampField, String> values;

  /// Location the map snapshot is centred on (the photo's location,
  /// never the device location at export time).
  final double? mapLatitude;
  final double? mapLongitude;

  String operator [](StampField f) => values[f] ?? '';

  bool get hasMapLocation => mapLatitude != null && mapLongitude != null;

  StampValues set(StampField f, String v) => StampValues(
        values: {...values, f: v},
        mapLatitude: mapLatitude,
        mapLongitude: mapLongitude,
      );

  StampValues merge(Map<StampField, String> changes, {double? mapLatitude, double? mapLongitude}) => StampValues(
        values: {...values, ...changes},
        mapLatitude: mapLatitude ?? this.mapLatitude,
        mapLongitude: mapLongitude ?? this.mapLongitude,
      );

  StampValues withMapLocation(double? lat, double? lon) =>
      StampValues(values: values, mapLatitude: lat, mapLongitude: lon);

  Map<String, dynamic> toJson() => {
        'values': {for (final e in values.entries) e.key.name: e.value},
        'mapLatitude': mapLatitude,
        'mapLongitude': mapLongitude,
      };

  factory StampValues.fromJson(Map<String, dynamic> j) {
    final out = <StampField, String>{};
    (j['values'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final f = StampField.tryParse(k);
      if (f != null && v is String) out[f] = v;
    });
    return StampValues(
      values: out,
      mapLatitude: (j['mapLatitude'] as num?)?.toDouble(),
      mapLongitude: (j['mapLongitude'] as num?)?.toDouble(),
    );
  }
}
