import 'auto.dart' show FaceBox;
import 'db/database.dart' show newId;
import 'recipe.dart';

/// The request of one native job (schema 1, native/core/src/job/job.hpp `JobRequest`): what the
/// app passes to `enh_job_start` and what the core keeps in `jobs/<id>/request.json`. The
/// strength of [Recipe] is not part of it: it is applied at export (ADR-0012 amendment).
class JobRequest {
  JobRequest({
    String? id,
    required this.input,
    required this.scale,
    this.fast2 = false,
    required this.srModel,
    this.faceModel,
    this.faceStrength = Recipe.defaultFaceStrength,
    this.faceFidelity = Recipe.defaultFaceFidelity,
    this.facesOnly = false,
    this.facesOff = const [],
    this.crop,
  }) : id = id ?? 'job-${newId()}' {
    if (crop case (final x, final y, final w, final h)
        when x < 0 || y < 0 || w < 16 || h < 16 || w > 2048 || h > 2048) {
      throw ArgumentError.value(crop, 'crop', 'outside 16..2048');
    }
    if (!_id.hasMatch(this.id)) throw ArgumentError.value(this.id, 'id', 'not a job id');
    recipe(); // the same parameter rules as a recipe
  }

  /// The processing parameters of [recipe] for [input].
  /// [facesOff]: faces of this photo the user turned off (FR-FACE-007); not part of a recipe.
  factory JobRequest.of(
    Recipe recipe,
    String input, {
    String? id,
    List<FaceBox> facesOff = const [],
    ({int x, int y, int w, int h})? crop,
  }) => JobRequest(
    id: id,
    input: input,
    scale: recipe.scale,
    fast2: recipe.fast2,
    srModel: recipe.srModel,
    faceModel: recipe.faceModel,
    faceStrength: recipe.faceStrength,
    faceFidelity: recipe.faceFidelity,
    facesOnly: recipe.facesOnly,
    facesOff: facesOff,
    crop: crop == null ? null : (crop.x, crop.y, crop.w, crop.h),
  );

  /// The job directory name under AppSupport/jobs (`[A-Za-z0-9_-]{1,64}` in the core).
  final String id;

  /// Absolute path of the inbox copy (ADR-0010).
  final String input;
  final int scale;
  final bool fast2;
  final String srModel;

  /// The face pack (FR-FACE-002), null without face restoration; the detector is the core's
  /// default (bundled YuNet).
  final String? faceModel;
  final double faceStrength;

  /// FR-FACE-005: CodeFormer's fidelity w (`face_fidelity` in the core).
  final double faceFidelity;

  /// Region "Faces" (FR-FACE-006): `background: lanczos` in the core.
  final bool facesOnly;

  /// FR-FACE-007: faces left as the SR model makes them (boxes from enh_analyze).
  final List<FaceBox> facesOff;

  /// FR-ENH-015 fragment preview: only this part (x, y, w, h) of the oriented input.
  final (int, int, int, int)? crop;

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// The recipe this request runs, at [strength] (not stored in the request).
  Recipe recipe({double strength = 1}) => Recipe(
    scale: scale,
    fast2: fast2,
    srModel: srModel,
    strength: strength,
    faceModel: faceModel,
    faceStrength: faceStrength,
    faceFidelity: faceFidelity,
    facesOnly: facesOnly,
  );

  static const schemaVersion = 1;

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'job_id': id,
    'input': input,
    'sr_model': srModel,
    'scale': scale,
    'fast2': fast2,
    if (faceModel case final f?) ...{
      'face_model': f,
      'face_strength': faceStrength,
      'face_fidelity': faceFidelity,
      if (facesOnly) 'background': 'lanczos',
      if (facesOff.isNotEmpty) 'faces_off': [for (final b in facesOff) b.toJson()],
    },
    if (crop case (final x, final y, final w, final h)) 'crop': [x, y, w, h],
  };

  /// Reads request.json as the core rewrote it (it adds its own fields, e.g. `tile`, and may
  /// lower the scale after a NEEDS_USER answer). Throws [FormatException] for anything else.
  factory JobRequest.fromJson(Map<String, Object?> j) {
    if (j case {
      'schema': schemaVersion,
      'job_id': final String id,
      'input': final String input,
      'sr_model': final String srModel,
      'scale': final int scale,
      'fast2': final bool fast2,
    }) {
      final face = j['face_model'];
      final faceStrength = j['face_strength'] ?? Recipe.defaultFaceStrength;
      final faceFidelity = j['face_fidelity'] ?? Recipe.defaultFaceFidelity;
      if ((face != null && face is! String) || faceStrength is! num || faceFidelity is! num) {
        throw FormatException('bad face fields', j);
      }
      try {
        return JobRequest(
          id: id,
          input: input,
          scale: scale,
          fast2: fast2,
          srModel: srModel,
          // The core writes "" for no face restoration.
          faceModel: face == null || face == '' ? null : face as String,
          faceStrength: faceStrength.toDouble(),
          faceFidelity: faceFidelity.toDouble(),
          facesOnly: j['background'] == 'lanczos',
          facesOff: switch (j['faces_off']) {
            null => const [],
            final List<Object?> l => [for (final b in l) FaceBox.fromJson(b)],
            final other => throw FormatException('bad faces_off', other),
          },
          crop: switch (j['crop']) {
            null => null,
            [final int x, final int y, final int w, final int h] => (x, y, w, h),
            final other => throw FormatException('bad crop', other),
          },
        );
      } on ArgumentError catch (e) {
        throw FormatException('${e.message}', j);
      }
    }
    throw FormatException('not a job request', j);
  }
}
