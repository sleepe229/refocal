/// Output formats of the native export (FR-EXP-001). HEIC output is 0.5+ (FR-EXP-002).
enum ExportFormat {
  jpeg('jpeg', false, 'jpg', 'image/jpeg'),
  png('png', false, 'png', 'image/png'),
  webp('webp', false, 'webp', 'image/webp'),
  webpLossless('webp', true, 'webp', 'image/webp');

  const ExportFormat(this.format, this.lossless, this.extension, this.mimeType);

  /// `format` of enh_export.
  final String format;
  final bool lossless;
  final String extension, mimeType;

  /// JPEG and lossy WebP quality range (FR-EXP-001).
  static const minQuality = 60, maxQuality = 100;

  /// Uses the quality setting (lossy).
  bool get hasQuality => this == jpeg || this == webp;

  /// WebP encodes a whole picture in memory: the core refuses larger results (ENH_E_LIMIT).
  double get maxMegapixels => switch (this) {
    webp => 50,
    webpLossless => 24,
    _ => double.infinity,
  };
}

/// How a result was written: the format and, for lossy formats, the quality.
class OutputSpec {
  OutputSpec(this.format, {int? quality}) : quality = format.hasQuality ? quality : null {
    if (_invalid(format, this.quality) case final why?) throw ArgumentError(why);
  }

  static String? _invalid(ExportFormat format, int? quality) =>
      format.hasQuality &&
          (quality == null ||
              quality < ExportFormat.minQuality ||
              quality > ExportFormat.maxQuality)
      ? 'quality of ${format.name} must be 60..100, got $quality'
      : null;

  final ExportFormat format;

  /// Null for PNG and lossless WebP.
  final int? quality;

  @override
  bool operator ==(Object other) =>
      other is OutputSpec && other.format == format && other.quality == quality;

  @override
  int get hashCode => Object.hash(format, quality);
}

/// The parameters of an enhancement without its input (03 §4.1: EnhanceRequest = Recipe). Kept
/// with history entries (FR-HIST-001/002: the recipe, not a copy of the photo) and presets
/// (FR-PRE-002). Serialized as JSON with a `schema` version (TEST-UNIT-007).
class Recipe {
  Recipe({
    required this.scale,
    this.fast2 = false,
    required this.srModel,
    this.strength = 1,
    this.output,
  }) {
    if (_invalid(scale, fast2, srModel, strength) case final why?) throw ArgumentError(why);
  }

  static String? _invalid(int scale, bool fast2, String srModel, double strength) {
    if (!scales.contains(scale)) return 'scale must be 1, 2 or 4, got $scale';
    if (fast2 && scale != 2) return 'fast2 needs scale 2';
    if (srModel.isEmpty) return 'no SR model';
    if (!(strength >= 0 && strength <= 1)) return 'strength must be 0..1, got $strength';
    return null;
  }

  static const schemaVersion = 1;

  /// Output scales of the bundled SR model (ADR-0014); 8x is 0.5.
  static const scales = {1, 2, 4};

  final int scale;

  /// 2x by running x4 on a half-size input (ADR-0014).
  final bool fast2;

  /// Super-resolution model id (04-ml-models).
  final String srModel;

  /// FR-ENH-005: blend with the input, 0..1.
  final double strength;

  /// What was saved; null in presets, where the format is chosen when saving (06 §3.4).
  final OutputSpec? output;

  Recipe copyWith({double? strength, OutputSpec? Function()? output}) => Recipe(
    scale: scale,
    fast2: fast2,
    srModel: srModel,
    strength: strength ?? this.strength,
    output: output != null ? output() : this.output,
  );

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'scale': scale,
    'fast2': fast2,
    'sr_model': srModel,
    'strength': strength,
    if (output case final o?) 'output': {'format': o.format.name, 'quality': ?o.quality},
  };

  /// Throws [FormatException] for anything this version did not write: a newer schema, a
  /// missing or out-of-range field, an unknown format.
  factory Recipe.fromJson(Map<String, Object?> j) {
    if (j case {
      'schema': schemaVersion,
      'scale': final int scale,
      'fast2': final bool fast2,
      'sr_model': final String srModel,
      'strength': final num strength,
    }) {
      if (_invalid(scale, fast2, srModel, strength.toDouble()) case final why?) {
        throw FormatException(why, j);
      }
      return Recipe(
        scale: scale,
        fast2: fast2,
        srModel: srModel,
        strength: strength.toDouble(),
        output: switch (j['output']) {
          null => null,
          {'format': final String name} && final Map<String, Object?> o => _output(
            name,
            o['quality'],
          ),
          final other => throw FormatException('bad output', other),
        },
      );
    }
    throw FormatException('not a recipe of schema $schemaVersion', j);
  }

  static OutputSpec _output(String name, Object? quality) {
    final format = ExportFormat.values.asNameMap()[name];
    if (format == null) throw FormatException('unknown format', name);
    if (quality is! int?) throw FormatException('bad quality', quality);
    if (OutputSpec._invalid(format, quality) case final why?) throw FormatException(why);
    return OutputSpec(format, quality: quality);
  }

  @override
  bool operator ==(Object other) =>
      other is Recipe &&
      other.scale == scale &&
      other.fast2 == fast2 &&
      other.srModel == srModel &&
      other.strength == strength &&
      other.output == output;

  @override
  int get hashCode => Object.hash(scale, fast2, srModel, strength, output);
}
