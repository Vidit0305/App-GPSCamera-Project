import 'stamp_values.dart';

enum StampPosition {
  topLeft('Top left'),
  topRight('Top right'),
  bottomLeft('Bottom left'),
  bottomRight('Bottom right'),
  center('Center'),
  custom('Custom');

  const StampPosition(this.label);
  final String label;
}

enum StampAlign { left, center, right }

enum MapSnapshotSize {
  small('Small', 0.16),
  medium('Medium', 0.22),
  large('Large', 0.30);

  const MapSnapshotSize(this.label, this.fraction);
  final String label;

  /// Size of the square map relative to the shorter image side.
  final double fraction;
}

enum MapPlacement { left, right }

/// Bundled stamp fonts (see pubspec.yaml).
const stampFontFamilies = <String, String>{
  'Inter': 'Inter (Sans)',
  'RobotoMono': 'Roboto Mono',
  'Lora': 'Lora (Serif)',
  'Oswald': 'Oswald (Condensed)',
};

/// A reusable visible-stamp design: which fields are shown and how they look.
/// Sizes are in "reference pixels" for an image whose shorter side is 1080 px
/// and are scaled to the real export resolution when rendering.
class StampTemplateModel {
  const StampTemplateModel({
    required this.id,
    required this.name,
    this.description = '',
    this.isBuiltIn = false,
    this.enabledFields = const {},
    this.fontFamily = 'Inter',
    this.fontSize = 30,
    this.bold = false,
    this.italic = false,
    this.alignment = StampAlign.left,
    this.textColor = 0xFFFFFFFF,
    this.accentColor = 0xFFFFC94D,
    this.backgroundColor = 0xFF000000,
    this.backgroundOpacity = 0.55,
    this.borderColor = 0xFFFFFFFF,
    this.borderWidth = 0,
    this.borderRadius = 18,
    this.padding = 22,
    this.margin = 28,
    this.lineSpacing = 1.25,
    this.shadow = false,
    this.showIcons = true,
    this.fullWidth = false,
    this.maxWidthFraction = 0.8,
    this.position = StampPosition.bottomLeft,
    this.customX = 0.05,
    this.customY = 0.85,
    this.showMap = false,
    this.mapSize = MapSnapshotSize.medium,
    this.mapRounded = true,
    this.mapPlacement = MapPlacement.left,
    this.mapShowMarker = true,
    this.mapZoom = 16,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final bool isBuiltIn;
  final Set<StampField> enabledFields;

  final String fontFamily;
  final double fontSize;
  final bool bold;
  final bool italic;
  final StampAlign alignment;

  /// ARGB colours.
  final int textColor;
  final int accentColor;
  final int backgroundColor;
  final double backgroundOpacity;
  final int borderColor;
  final double borderWidth;

  final double borderRadius;
  final double padding;
  final double margin;
  final double lineSpacing;
  final bool shadow;
  final bool showIcons;

  /// Stamp spans the full image width (banner style).
  final bool fullWidth;

  /// Maximum stamp width as a fraction of the image width (when not full width).
  final double maxWidthFraction;

  final StampPosition position;

  /// Normalised position (0..1) of the stamp's top-left corner within the free
  /// space of the image, used when [position] is [StampPosition.custom].
  final double customX;
  final double customY;

  final bool showMap;
  final MapSnapshotSize mapSize;
  final bool mapRounded;
  final MapPlacement mapPlacement;
  final bool mapShowMarker;
  final int mapZoom;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Aliases matching the specification's model fields.
  String get fontWeight => bold ? 'bold' : 'normal';
  bool get includesMap => showMap && enabledFields.contains(StampField.map);

  bool shows(StampField f) => enabledFields.contains(f);

  StampTemplateModel copyWith({
    String? id,
    String? name,
    String? description,
    bool? isBuiltIn,
    Set<StampField>? enabledFields,
    String? fontFamily,
    double? fontSize,
    bool? bold,
    bool? italic,
    StampAlign? alignment,
    int? textColor,
    int? accentColor,
    int? backgroundColor,
    double? backgroundOpacity,
    int? borderColor,
    double? borderWidth,
    double? borderRadius,
    double? padding,
    double? margin,
    double? lineSpacing,
    bool? shadow,
    bool? showIcons,
    bool? fullWidth,
    double? maxWidthFraction,
    StampPosition? position,
    double? customX,
    double? customY,
    bool? showMap,
    MapSnapshotSize? mapSize,
    bool? mapRounded,
    MapPlacement? mapPlacement,
    bool? mapShowMarker,
    int? mapZoom,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StampTemplateModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      enabledFields: enabledFields ?? this.enabledFields,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      alignment: alignment ?? this.alignment,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      borderRadius: borderRadius ?? this.borderRadius,
      padding: padding ?? this.padding,
      margin: margin ?? this.margin,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      shadow: shadow ?? this.shadow,
      showIcons: showIcons ?? this.showIcons,
      fullWidth: fullWidth ?? this.fullWidth,
      maxWidthFraction: maxWidthFraction ?? this.maxWidthFraction,
      position: position ?? this.position,
      customX: customX ?? this.customX,
      customY: customY ?? this.customY,
      showMap: showMap ?? this.showMap,
      mapSize: mapSize ?? this.mapSize,
      mapRounded: mapRounded ?? this.mapRounded,
      mapPlacement: mapPlacement ?? this.mapPlacement,
      mapShowMarker: mapShowMarker ?? this.mapShowMarker,
      mapZoom: mapZoom ?? this.mapZoom,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  StampTemplateModel toggleField(StampField f, bool on) {
    final set = {...enabledFields};
    on ? set.add(f) : set.remove(f);
    return copyWith(enabledFields: set, showMap: f == StampField.map ? on : showMap);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isBuiltIn': isBuiltIn,
        'enabledFields': [for (final f in StampField.values) if (enabledFields.contains(f)) f.name],
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'alignment': alignment.name,
        'textColor': textColor,
        'accentColor': accentColor,
        'backgroundColor': backgroundColor,
        'backgroundOpacity': backgroundOpacity,
        'borderColor': borderColor,
        'borderWidth': borderWidth,
        'borderRadius': borderRadius,
        'padding': padding,
        'margin': margin,
        'lineSpacing': lineSpacing,
        'shadow': shadow,
        'showIcons': showIcons,
        'fullWidth': fullWidth,
        'maxWidthFraction': maxWidthFraction,
        'position': position.name,
        'customX': customX,
        'customY': customY,
        'showMap': showMap,
        'mapSize': mapSize.name,
        'mapRounded': mapRounded,
        'mapPlacement': mapPlacement.name,
        'mapShowMarker': mapShowMarker,
        'mapZoom': mapZoom,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory StampTemplateModel.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((e) => e.name == name, orElse: () => fallback);
    double d(String k, double fb) => (j[k] as num?)?.toDouble() ?? fb;
    int i(String k, int fb) => (j[k] as num?)?.toInt() ?? fb;
    bool b(String k, bool fb) => j[k] as bool? ?? fb;
    return StampTemplateModel(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Untitled',
      description: j['description'] as String? ?? '',
      isBuiltIn: b('isBuiltIn', false),
      enabledFields: {
        for (final n in (j['enabledFields'] as List? ?? const []))
          if (StampField.tryParse('$n') != null) StampField.tryParse('$n')!,
      },
      fontFamily: stampFontFamilies.containsKey(j['fontFamily']) ? j['fontFamily'] as String : 'Inter',
      fontSize: d('fontSize', 30),
      bold: b('bold', false),
      italic: b('italic', false),
      alignment: pick(StampAlign.values, j['alignment'], StampAlign.left),
      textColor: i('textColor', 0xFFFFFFFF),
      accentColor: i('accentColor', 0xFFFFC94D),
      backgroundColor: i('backgroundColor', 0xFF000000),
      backgroundOpacity: d('backgroundOpacity', 0.55),
      borderColor: i('borderColor', 0xFFFFFFFF),
      borderWidth: d('borderWidth', 0),
      borderRadius: d('borderRadius', 18),
      padding: d('padding', 22),
      margin: d('margin', 28),
      lineSpacing: d('lineSpacing', 1.25),
      shadow: b('shadow', false),
      showIcons: b('showIcons', true),
      fullWidth: b('fullWidth', false),
      maxWidthFraction: d('maxWidthFraction', 0.8),
      position: pick(StampPosition.values, j['position'], StampPosition.bottomLeft),
      customX: d('customX', 0.05),
      customY: d('customY', 0.85),
      showMap: b('showMap', false),
      mapSize: pick(MapSnapshotSize.values, j['mapSize'], MapSnapshotSize.medium),
      mapRounded: b('mapRounded', true),
      mapPlacement: pick(MapPlacement.values, j['mapPlacement'], MapPlacement.left),
      mapShowMarker: b('mapShowMarker', true),
      mapZoom: i('mapZoom', 16).clamp(3, 18),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    );
  }
}
