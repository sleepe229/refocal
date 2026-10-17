/// Output formats of the native export (FR-EXP-001, FR-EXP-002). HEIC is encoded by the platform
/// and offered only where it can be (`heicSupported`, Q-12).
enum ExportFormat {
  jpeg('jpeg', false, 'jpg', 'image/jpeg'),
  png('png', false, 'png', 'image/png'),
  webp('webp', false, 'webp', 'image/webp'),
  webpLossless('webp', true, 'webp', 'image/webp'),
  heic('heic', false, 'heic', 'image/heic');

  const ExportFormat(this.format, this.lossless, this.extension, this.mimeType);

  /// `format` of enh_export.
  final String format;
  final bool lossless;
  final String extension, mimeType;

  /// JPEG and lossy WebP quality range (FR-EXP-001).
  static const minQuality = 60, maxQuality = 100;

  /// Uses the quality setting (lossy).
  bool get hasQuality => this == jpeg || this == webp || this == heic;

  /// WebP encodes a whole picture in memory, HEIC one bitmap on the platform: the core refuses
  /// larger results (ENH_E_LIMIT).
  double get maxMegapixels => switch (this) {
    webp || heic => 50,
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
    this.faceModel,
    this.faceStrength = defaultFaceStrength,
    this.faceFidelity = defaultFaceFidelity,
    this.facesOnly = false,
    this.jpegModel,
    this.jpegQf,
    this.scratchModel,
    this.inpaintModel,
    this.lowlightModel,
    this.output,
  }) {
    if (lowlightModel?.isEmpty == true) throw ArgumentError('empty low-light model');
    if ((scratchModel == null) != (inpaintModel == null) ||
        scratchModel?.isEmpty == true ||
        inpaintModel?.isEmpty == true) {
      throw ArgumentError('scratch removal needs a detector and an inpainting model');
    }
    if (jpegModel != null && jpegModel!.isEmpty) throw ArgumentError('empty JPEG model');
    if (jpegQf case final q? when !(q >= 0 && q <= 1)) {
      throw ArgumentError('jpegQf must be 0..1, got $q');
    }
    if (!(faceFidelity >= 0 && faceFidelity <= 1)) {
      throw ArgumentError('faceFidelity must be 0..1, got $faceFidelity');
    }
    if (facesOnly && faceModel == null) throw ArgumentError('facesOnly needs a face model');
    if (_invalid(scale, fast2, srModel, strength, faceModel, faceStrength) case final why?) {
      throw ArgumentError(why);
    }
  }

  static String? _invalid(
    int scale,
    bool fast2,
    String srModel,
    double strength,
    String? faceModel,
    double faceStrength,
  ) {
    if (!scales.contains(scale)) return 'scale must be 1, 2, 4 or 8, got $scale';
    if (fast2 && scale != 2) return 'fast2 needs scale 2';
    if (srModel.isEmpty) return 'no SR model';
    if (!(strength >= 0 && strength <= 1)) return 'strength must be 0..1, got $strength';
    if (faceModel != null && faceModel.isEmpty) return 'empty face model';
    if (!(faceStrength >= 0 && faceStrength <= 1)) {
      return 'faceStrength must be 0..1, got $faceStrength';
    }
    return null;
  }

  /// 2: face restoration (faceModel, faceStrength). Schema 1 recipes are read as without faces;
  /// an older app refuses schema 2 rather than dropping the faces. 3: JPEG cleanup (jpegModel,
  /// jpegQf), written only when it is on, so other recipes stay readable by older apps. 4:
  /// scratch removal (scratchModel, inpaintModel), likewise only when it is on. 5: low light
  /// (lowlightModel), likewise.
  static const schemaVersion = 5;

  /// FR-FACE-004, ADR-0022: half the restored face over the SR result.
  static const defaultFaceStrength = 0.5;

  /// FR-FACE-005: CodeFormer's fidelity w (0 more detail from its codebook .. 1 closer to the
  /// photo), 0.7 by default as upstream recommends.
  static const defaultFaceFidelity = 0.7;

  /// Output scales (ADR-0014): x4 models, area-downscaled for 2x and 1x; 8x runs x4 twice
  /// (input at most [maxX8InputPx], T2).
  static const scales = {1, 2, 4, 8};

  /// ADR-0014: the largest input 8x runs on (the core asks for a smaller scale above it).
  static const maxX8InputPx = 1500000;

  final int scale;

  /// 2x by running x4 on a half-size input (ADR-0014).
  final bool fast2;

  /// Super-resolution model id (04-ml-models).
  final String srModel;

  /// FR-ENH-005: blend with the input, 0..1.
  final double strength;

  /// The face pack restoring faces (FR-FACE-002); null: no face restoration.
  final String? faceModel;

  /// How much of the restored face is blended in, 0..1 (FR-FACE-004).
  final double faceStrength;

  /// FR-FACE-005: CodeFormer's fidelity w, 0..1; face models without it ignore it.
  final double faceFidelity;

  /// FR-FACE-006 region "Faces": only faces are restored, the rest is a Lanczos upscale (the
  /// SR model does not run). Region "Background" is [faceModel] null; "All" is the default.
  final bool facesOnly;

  /// S9: the JPEG pack cleaning the photo before SR; null: no cleanup.
  final String? jpegModel;

  /// The cleanup's quality factor 0..1 (1 - JPEG quality/100); null: from the photo's own
  /// quantization table (quality 50 for other formats).
  final double? jpegQf;

  /// S9: the scratch detector and the inpainting pack filling what it finds (both or neither);
  /// null: no scratch removal.
  final String? scratchModel;
  final String? inpaintModel;

  /// S9: the low-light pack brightening the photo before SR; null: off.
  final String? lowlightModel;

  /// What was saved; null in presets, where the format is chosen when saving (06 §3.4).
  final OutputSpec? output;

  Recipe copyWith({
    double? strength,
    String? Function()? faceModel,
    double? faceStrength,
    double? faceFidelity,
    bool? facesOnly,
    String? Function()? jpegModel,
    double? Function()? jpegQf,
    (String, String)? Function()? scratches,
    String? Function()? lowlightModel,
    OutputSpec? Function()? output,
  }) => Recipe(
    scale: scale,
    fast2: fast2,
    srModel: srModel,
    strength: strength ?? this.strength,
    faceModel: faceModel != null ? faceModel() : this.faceModel,
    faceStrength: faceStrength ?? this.faceStrength,
    faceFidelity: faceFidelity ?? this.faceFidelity,
    facesOnly:
        (faceModel != null ? faceModel() : this.faceModel) != null && (facesOnly ?? this.facesOnly),
    jpegModel: jpegModel != null ? jpegModel() : this.jpegModel,
    jpegQf: jpegQf != null ? jpegQf() : this.jpegQf,
    scratchModel: scratches != null ? scratches()?.$1 : scratchModel,
    inpaintModel: scratches != null ? scratches()?.$2 : inpaintModel,
    lowlightModel: lowlightModel != null ? lowlightModel() : this.lowlightModel,
    output: output != null ? output() : this.output,
  );

  Map<String, Object?> toJson() => {
    'schema': lowlightModel != null
        ? 5
        : scratchModel != null
        ? 4
        : (jpegModel != null ? 3 : 2),
    'scale': scale,
    'fast2': fast2,
    'sr_model': srModel,
    'strength': strength,
    if (faceModel case final f?) ...{
      'face_model': f,
      'face_strength': faceStrength,
      if (faceFidelity != defaultFaceFidelity) 'face_fidelity': faceFidelity,
      if (facesOnly) 'faces_only': true,
    },
    if (jpegModel case final m?) ...{'jpeg_model': m, 'jpeg_qf': ?jpegQf},
    if (scratchModel case final m?) ...{'scratch_model': m, 'inpaint_model': inpaintModel},
    'lowlight_model': ?lowlightModel,
    if (output case final o?) 'output': {'format': o.format.name, 'quality': ?o.quality},
  };

  /// Throws [FormatException] for anything this version did not write: a newer schema, a
  /// missing or out-of-range field, an unknown format.
  factory Recipe.fromJson(Map<String, Object?> j) {
    if (j
        case {
          'schema': final int schema,
          'scale': final int scale,
          'fast2': final bool fast2,
          'sr_model': final String srModel,
          'strength': final num strength,
        }
        when schema >= 1 && schema <= schemaVersion) {
      final faceModel = switch (j['face_model']) {
        null => null,
        final String f when schema >= 2 => f,
        final other => throw FormatException('bad face_model', other),
      };
      final faceStrength = switch (j['face_strength']) {
        null => defaultFaceStrength,
        final num v when schema >= 2 => v.toDouble(),
        final other => throw FormatException('bad face_strength', other),
      };
      final faceFidelity = switch (j['face_fidelity']) {
        null => defaultFaceFidelity,
        final num v when schema >= 2 && v >= 0 && v <= 1 => v.toDouble(),
        final other => throw FormatException('bad face_fidelity', other),
      };
      final jpegModel = switch (j['jpeg_model']) {
        null => null,
        final String m when schema >= 3 && m.isNotEmpty => m,
        final other => throw FormatException('bad jpeg_model', other),
      };
      final jpegQf = switch (j['jpeg_qf']) {
        null => null,
        final num v when jpegModel != null && v >= 0 && v <= 1 => v.toDouble(),
        final other => throw FormatException('bad jpeg_qf', other),
      };
      final (scratchModel, inpaintModel) = switch ((j['scratch_model'], j['inpaint_model'])) {
        (null, null) => (null, null),
        (final String d, final String f) when schema >= 4 && d.isNotEmpty && f.isNotEmpty => (d, f),
        final other => throw FormatException('bad scratch_model / inpaint_model', other),
      };
      final lowlightModel = switch (j['lowlight_model']) {
        null => null,
        final String m when schema >= 5 && m.isNotEmpty => m,
        final other => throw FormatException('bad lowlight_model', other),
      };
      if (_invalid(scale, fast2, srModel, strength.toDouble(), faceModel, faceStrength)
          case final why?) {
        throw FormatException(why, j);
      }
      return Recipe(
        scale: scale,
        fast2: fast2,
        srModel: srModel,
        strength: strength.toDouble(),
        faceModel: faceModel,
        faceStrength: faceStrength,
        faceFidelity: faceFidelity,
        facesOnly: switch (j['faces_only']) {
          null => false,
          true when faceModel != null => true,
          final other => throw FormatException('bad faces_only', other),
        },
        jpegModel: jpegModel,
        jpegQf: jpegQf,
        scratchModel: scratchModel,
        inpaintModel: inpaintModel,
        lowlightModel: lowlightModel,
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
    throw FormatException('not a recipe of schema 1..$schemaVersion', j);
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
      other.faceModel == faceModel &&
      other.faceStrength == faceStrength &&
      other.faceFidelity == faceFidelity &&
      other.facesOnly == facesOnly &&
      other.jpegModel == jpegModel &&
      other.jpegQf == jpegQf &&
      other.scratchModel == scratchModel &&
      other.inpaintModel == inpaintModel &&
      other.lowlightModel == lowlightModel &&
      other.output == output;

  @override
  int get hashCode => Object.hash(
    scale,
    fast2,
    srModel,
    strength,
    faceModel,
    faceStrength,
    faceFidelity,
    facesOnly,
    jpegModel,
    jpegQf,
    scratchModel,
    inpaintModel,
    lowlightModel,
    output,
  );
}
