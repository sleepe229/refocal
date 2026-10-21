import 'dart:math' as math;

import 'recipe.dart';
import 'tiers.dart';

/// A face box in pixels of the oriented input (enh_analyze `faces.boxes`, the request's
/// `faces_off`, FR-FACE-007).
class FaceBox {
  const FaceBox(this.x, this.y, this.w, this.h);
  final double x, y, w, h;

  /// Throws [FormatException] unless [j] is four non-negative numbers.
  factory FaceBox.fromJson(Object? j) {
    if (j case [final num x, final num y, final num w, final num h]
        when x >= 0 && y >= 0 && w >= 0 && h >= 0) {
      return FaceBox(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
    }
    throw FormatException('not a face box', j);
  }

  List<double> toJson() => [x, y, w, h];

  @override
  bool operator ==(Object other) =>
      other is FaceBox && other.x == x && other.y == y && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

/// What enh_analyze reports about a photo (FR-ENH-007).
class PhotoAnalysis {
  const PhotoAnalysis({
    required this.width,
    required this.height,
    required this.noiseSigma,
    required this.faces,
    required this.largestFacePx,
    required this.detector,
    this.boxes = const [],
    this.jpegQuality = 0,
    this.effScale = 1,
  });

  /// Throws [FormatException] for anything the core did not write.
  factory PhotoAnalysis.fromJson(Map<String, Object?> j) {
    if (j case {
      'schema': 1,
      'width': final int w,
      'height': final int h,
      'noise_sigma': final num noise,
      'faces': {
        'count': final int count,
        'largest_px': final int largest,
        'detector': final bool detector,
        'boxes': final List<Object?> boxes,
      },
    }) {
      return PhotoAnalysis(
        width: w,
        height: h,
        noiseSigma: noise.toDouble(),
        faces: count,
        largestFacePx: largest,
        detector: detector,
        boxes: [for (final b in boxes) FaceBox.fromJson(b)],
        jpegQuality: switch (j['jpeg_quality']) {
          null => 0,
          final int q when q >= 0 && q <= 100 => q,
          final other => throw FormatException('bad jpeg_quality', other),
        },
        // ADR-0025: absent from an older core: as a sharp photo.
        effScale: switch (j['eff_scale']) {
          null => 1.0,
          final num e when e > 0 && e <= 1 => e.toDouble(),
          final other => throw FormatException('bad eff_scale', other),
        },
      );
    }
    throw FormatException('not an analysis', j);
  }

  final int width, height;

  /// Estimated Gaussian noise, 8-bit levels.
  final double noiseSigma;
  final int faces, largestFacePx;

  /// The face detector ran (without it [faces] is 0 and says nothing).
  final bool detector;

  /// The faces a job restores, largest first (FR-FACE-007).
  final List<FaceBox> boxes;

  /// S9: the JPEG quality of the photo's quantization table; 0 when it is not a JPEG.
  final int jpegQuality;

  /// ADR-0025: the effective resolution, a factor in (0, 1] of the pixel size (1: sharp).
  final double effScale;

  double get megapixels => width * height / 1e6;
}

/// The models Auto may use: the denoise levels installed (ADR-0015), and the face pack.
class AutoModels {
  const AutoModels({required this.standard, this.none, this.strong, this.facePack, this.jpegPack});

  /// The built-in model (denoise 0.5); [none] is built in too (ADR-0025), [strong] a pack.
  final String standard;
  final String? none, strong, facePack;

  /// S9: the JPEG cleanup pack, when installed.
  final String? jpegPack;
}

/// Why Auto chose what it did, for the explanation (06 §3.2: «4×, лиц: 2, денойз средний»).
enum AutoReason {
  largePhoto,
  mediumPhoto,
  smallPhoto,
  faces,
  tooManyFacesForTier,
  cleanPhoto,
  noisyPhoto,
  veryNoisyPhoto,
  jpegArtifacts,

  /// ADR-0025: the photo is blurrier than its pixels: SR runs at its effective resolution.
  blurryPhoto,
}

class AutoDecision {
  const AutoDecision(this.recipe, this.reasons);
  final Recipe recipe;
  final List<AutoReason> reasons;
}

/// Auto v1 (FR-ENH-007): deterministic rules, the same input gives the same recipe.
///
/// - Scale (ADR-0014, 05 §3): >= 8 MP: fast 2x (regular 2x on T2); 4..8 MP: 2x (fast on T0);
///   below 4 MP: 4x.
/// - Faces (FR-FACE-002/004, 04 §1): when found and the face pack is installed, at 50%; on T0
///   (CPU face model) only a single face; on T0 with >= 8 MP only the faces are restored
///   (05 §3: "только лица").
/// - Denoise (ADR-0015): sigma < [cleanSigma] -> the "off" level if installed; sigma >
///   [noisySigma] -> the strong level if installed; else the built-in 0.5.
/// - JPEG artifacts (S9): a JPEG below [jpegCleanBelow] quality gets the cleanup pack on T2
///   (FBCNN is a T2 pack, 04 §1), its quality factor read from the photo.
/// - Effective resolution (ADR-0025): an eff_scale below [blurBelow] runs SR on the input
///   downscaled to it, no lower than [minPreDown] (a downscale that is too strong destroys
///   small text, so the rule errs on the sharp side), when that is below what SR runs at
///   anyway (fast 2x: 0.5; region Faces: no SR). Every recipe gets the unsharp mask at
///   [sharpen].
class AutoPolicy {
  const AutoPolicy();

  static const cleanSigma = 2.0, noisySigma = 8.0;
  static const jpegCleanBelow = 60;
  static const blurBelow = 0.9, minPreDown = 0.4, sharpen = 1.0;

  AutoDecision decide(PhotoAnalysis a, DeviceTier tier, AutoModels models) {
    final reasons = <AutoReason>[];
    final mp = a.megapixels;
    final (int scale, bool fast2) = switch (mp) {
      >= 8 => (2, tier != DeviceTier.t2),
      >= 4 => (2, tier == DeviceTier.t0),
      _ => (4, false),
    };
    reasons.add(
      mp >= 8
          ? AutoReason.largePhoto
          : mp >= 4
          ? AutoReason.mediumPhoto
          : AutoReason.smallPhoto,
    );

    var sr = models.standard;
    if (a.noiseSigma < cleanSigma && models.none != null) {
      sr = models.none!;
      reasons.add(AutoReason.cleanPhoto);
    } else if (a.noiseSigma > noisySigma) {
      reasons.add(models.strong != null ? AutoReason.veryNoisyPhoto : AutoReason.noisyPhoto);
      sr = models.strong ?? models.standard;
    } else {
      reasons.add(AutoReason.noisyPhoto);
    }

    String? face;
    var facesOnly = false;
    if (a.faces > 0 && models.facePack != null) {
      if (tier == DeviceTier.t0 && a.faces > 1) {
        reasons.add(AutoReason.tooManyFacesForTier);
      } else {
        face = models.facePack;
        facesOnly = tier == DeviceTier.t0 && mp >= 8;
        reasons.add(AutoReason.faces);
      }
    }
    // ADR-0025: set only when it lowers the size SR runs at (fast 2x already halves it, region
    // Faces runs no SR); 2 decimals, so recipes stay readable.
    final eff = (math.max(minPreDown, a.effScale) * 100).round() / 100;
    final blurry = a.effScale < blurBelow && !facesOnly && eff < (fast2 ? 0.5 : 1);
    final preDown = blurry ? eff : 1.0;
    if (blurry) reasons.add(AutoReason.blurryPhoto);
    String? jpeg;
    if (a.jpegQuality > 0 &&
        a.jpegQuality < jpegCleanBelow &&
        models.jpegPack != null &&
        tier == DeviceTier.t2) {
      jpeg = models.jpegPack;
      reasons.add(AutoReason.jpegArtifacts);
    }
    return AutoDecision(
      Recipe(
        scale: scale,
        fast2: fast2 && !facesOnly,
        preDown: preDown,
        sharpen: sharpen,
        srModel: sr,
        faceModel: face,
        facesOnly: facesOnly,
        jpegModel: jpeg,
      ),
      reasons,
    );
  }
}
