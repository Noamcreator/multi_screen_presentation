/// Représente un écran physique détecté par l'OS.
class ScreenInfo {
  /// Identifiant stable côté natif (handle moniteur, NSScreen index, displayId...).
  final String id;

  /// Nom lisible ("Built-in Retina Display", "DELL U2720Q", "HDMI-1"...).
  final String name;

  /// Position en pixels logiques dans l'espace virtuel du bureau (0,0 = écran principal).
  final double x;
  final double y;

  /// Taille en pixels logiques.
  final double width;
  final double height;

  /// Facteur d'échelle (Retina / DPI).
  final double scaleFactor;

  /// True si c'est l'écran principal du système.
  final bool isPrimary;

  const ScreenInfo({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.scaleFactor,
    required this.isPrimary,
  });

  factory ScreenInfo.fromMap(Map<dynamic, dynamic> map) {
    return ScreenInfo(
      id: map['id'].toString(),
      name: map['name'] as String? ?? 'Screen',
      x: (map['x'] as num? ?? 0).toDouble(),
      y: (map['y'] as num? ?? 0).toDouble(),
      width: (map['width'] as num? ?? 0).toDouble(),
      height: (map['height'] as num? ?? 0).toDouble(),
      scaleFactor: (map['scaleFactor'] as num? ?? 1).toDouble(),
      isPrimary: map['isPrimary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'scaleFactor': scaleFactor,
        'isPrimary': isPrimary,
      };

  @override
  String toString() =>
      'ScreenInfo($id, $name, ${width}x$height @($x,$y), primary=$isPrimary)';
}
