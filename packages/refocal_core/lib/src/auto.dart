import 'recipe.dart';
import 'tiers.dart';

/// What enh_analyze reports about a photo (FR-ENH-007).
class PhotoAnalysis {
  const PhotoAnalysis({
    required this.width,
    required this.height,
    required this.noiseSigma,
    required this.faces,
    required this.largestFacePx,
    required this.detector,
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
      },
    }) {
      return PhotoAnalysis(
        width: w,
        height: h,
        noiseSigma: noise.toDouble(),
        faces: count,
        largestFacePx: largest,
        detector: detector,
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

  double get megapixels => width * height / 1e6;
}

/// The models Auto may use: the denoise levels installed (ADR-0015), and the face pack.
class AutoModels {
  const AutoModels({required this.standard, this.none, this.strong, this.facePack});

  /// The built-in model (denoise 0.5).
  final String standard;
  final String? none, strong, facePack;
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
class AutoPolicy {
  const AutoPolicy();

  static const cleanSigma = 2.0, noisySigma = 8.0;

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
    return AutoDecision(
      Recipe(
        scale: scale,
        fast2: fast2 && !facesOnly,
        srModel: sr,
        faceModel: face,
        facesOnly: facesOnly,
      ),
      reasons,
    );
  }
}
