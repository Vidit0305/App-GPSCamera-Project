/// Where a set of location values came from. Shown to the user so detected
/// GPS data is never confused with manual or stale data.
enum LocationSource {
  /// Live fix from the device GPS / location service.
  gps,

  /// The OS's last known position (may be stale; shown with its age).
  lastKnown,

  /// Chosen by the user on the map or typed in manually.
  manual,

  /// Read from the EXIF metadata of an imported photo.
  exif,

  /// No location available.
  none;

  String get label => switch (this) {
        gps => 'Device GPS',
        lastKnown => 'Last known position',
        manual => 'Manually selected',
        exif => 'From photo metadata',
        none => 'No location',
      };

  static LocationSource parse(String? v) =>
      LocationSource.values.firstWhere((e) => e.name == v, orElse: () => LocationSource.none);
}

/// Structured address returned by a reverse-geocoding provider.
class AddressModel {
  const AddressModel({
    this.street,
    this.buildingNumber,
    this.area,
    this.locality,
    this.subLocality,
    this.city,
    this.district,
    this.state,
    this.postalCode,
    this.country,
    this.countryCode,
    this.fullAddress,
    this.provider,
  });

  final String? street;
  final String? buildingNumber;
  final String? area;
  final String? locality;
  final String? subLocality;
  final String? city;
  final String? district;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? countryCode;
  final String? fullAddress;
  final String? provider;

  bool get isEmpty =>
      [street, area, locality, city, district, state, country, fullAddress].every((e) => e == null || e.isEmpty);

  Map<String, dynamic> toJson() => {
        'street': street,
        'buildingNumber': buildingNumber,
        'area': area,
        'locality': locality,
        'subLocality': subLocality,
        'city': city,
        'district': district,
        'state': state,
        'postalCode': postalCode,
        'country': country,
        'countryCode': countryCode,
        'fullAddress': fullAddress,
        'provider': provider,
      };

  factory AddressModel.fromJson(Map<String, dynamic> j) => AddressModel(
        street: j['street'] as String?,
        buildingNumber: j['buildingNumber'] as String?,
        area: j['area'] as String?,
        locality: j['locality'] as String?,
        subLocality: j['subLocality'] as String?,
        city: j['city'] as String?,
        district: j['district'] as String?,
        state: j['state'] as String?,
        postalCode: j['postalCode'] as String?,
        country: j['country'] as String?,
        countryCode: j['countryCode'] as String?,
        fullAddress: j['fullAddress'] as String?,
        provider: j['provider'] as String?,
      );
}

/// A location: coordinates (when known) plus an optional resolved address.
class LocationModel {
  const LocationModel({
    this.latitude,
    this.longitude,
    this.altitude,
    this.accuracy,
    this.altitudeAccuracy,
    this.speed,
    this.heading,
    this.street,
    this.buildingNumber,
    this.area,
    this.locality,
    this.subLocality,
    this.city,
    this.district,
    this.state,
    this.postalCode,
    this.country,
    this.countryCode,
    this.fullAddress,
    this.detectedAt,
    this.source = LocationSource.none,
    this.isMocked = false,
    this.addressResolved = false,
    this.addressProvider,
  });

  final double? latitude;
  final double? longitude;

  /// Metres above the WGS84 ellipsoid / sea level as reported by the platform.
  /// Null when the device did not provide an altitude.
  final double? altitude;

  /// Horizontal accuracy radius in metres.
  final double? accuracy;
  final double? altitudeAccuracy;

  /// Metres per second; null when unavailable.
  final double? speed;

  /// Degrees from north; null when unavailable.
  final double? heading;

  final String? street;
  final String? buildingNumber;
  final String? area;
  final String? locality;
  final String? subLocality;
  final String? city;
  final String? district;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? countryCode;
  final String? fullAddress;

  /// Timestamp of the location fix (not of the reverse geocode).
  final DateTime? detectedAt;
  final LocationSource source;
  final bool isMocked;
  final bool addressResolved;
  final String? addressProvider;

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasAltitude => altitude != null;

  /// "City, State, Country" style one-line summary.
  String get shortAddress {
    final parts = <String>[];
    for (final p in [city ?? locality, state, country]) {
      if (p != null && p.trim().isNotEmpty && !parts.contains(p)) parts.add(p);
    }
    return parts.join(', ');
  }

  LocationModel withAddress(AddressModel a) => LocationModel(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        accuracy: accuracy,
        altitudeAccuracy: altitudeAccuracy,
        speed: speed,
        heading: heading,
        street: a.street,
        buildingNumber: a.buildingNumber,
        area: a.area,
        locality: a.locality,
        subLocality: a.subLocality,
        city: a.city,
        district: a.district,
        state: a.state,
        postalCode: a.postalCode,
        country: a.country,
        countryCode: a.countryCode,
        fullAddress: a.fullAddress,
        detectedAt: detectedAt,
        source: source,
        isMocked: isMocked,
        addressResolved: !a.isEmpty,
        addressProvider: a.provider,
      );

  /// Same coordinates, address dropped (used when coordinates change).
  LocationModel withoutAddress() => LocationModel(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        accuracy: accuracy,
        altitudeAccuracy: altitudeAccuracy,
        speed: speed,
        heading: heading,
        detectedAt: detectedAt,
        source: source,
        isMocked: isMocked,
      );

  LocationModel copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    bool clearAltitude = false,
    double? accuracy,
    bool clearAccuracy = false,
    String? street,
    String? area,
    String? locality,
    String? city,
    String? district,
    String? state,
    String? postalCode,
    String? country,
    String? fullAddress,
    DateTime? detectedAt,
    LocationSource? source,
    bool? addressResolved,
  }) {
    return LocationModel(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: clearAltitude ? null : (altitude ?? this.altitude),
      accuracy: clearAccuracy ? null : (accuracy ?? this.accuracy),
      altitudeAccuracy: altitudeAccuracy,
      speed: speed,
      heading: heading,
      street: street ?? this.street,
      buildingNumber: buildingNumber,
      area: area ?? this.area,
      locality: locality ?? this.locality,
      subLocality: subLocality,
      city: city ?? this.city,
      district: district ?? this.district,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      countryCode: countryCode,
      fullAddress: fullAddress ?? this.fullAddress,
      detectedAt: detectedAt ?? this.detectedAt,
      source: source ?? this.source,
      isMocked: isMocked,
      addressResolved: addressResolved ?? this.addressResolved,
      addressProvider: addressProvider,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'accuracy': accuracy,
        'altitudeAccuracy': altitudeAccuracy,
        'speed': speed,
        'heading': heading,
        'street': street,
        'buildingNumber': buildingNumber,
        'area': area,
        'locality': locality,
        'subLocality': subLocality,
        'city': city,
        'district': district,
        'state': state,
        'postalCode': postalCode,
        'country': country,
        'countryCode': countryCode,
        'fullAddress': fullAddress,
        'detectedAt': detectedAt?.toIso8601String(),
        'source': source.name,
        'isMocked': isMocked,
        'addressResolved': addressResolved,
        'addressProvider': addressProvider,
      };

  factory LocationModel.fromJson(Map<String, dynamic> j) => LocationModel(
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        altitude: (j['altitude'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        altitudeAccuracy: (j['altitudeAccuracy'] as num?)?.toDouble(),
        speed: (j['speed'] as num?)?.toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
        street: j['street'] as String?,
        buildingNumber: j['buildingNumber'] as String?,
        area: j['area'] as String?,
        locality: j['locality'] as String?,
        subLocality: j['subLocality'] as String?,
        city: j['city'] as String?,
        district: j['district'] as String?,
        state: j['state'] as String?,
        postalCode: j['postalCode'] as String?,
        country: j['country'] as String?,
        countryCode: j['countryCode'] as String?,
        fullAddress: j['fullAddress'] as String?,
        detectedAt: DateTime.tryParse(j['detectedAt'] as String? ?? ''),
        source: LocationSource.parse(j['source'] as String?),
        isMocked: j['isMocked'] as bool? ?? false,
        addressResolved: j['addressResolved'] as bool? ?? false,
        addressProvider: j['addressProvider'] as String?,
      );
}
