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
  }) : id = id ?? 'job-${newId()}' {
    if (!_id.hasMatch(this.id)) throw ArgumentError.value(this.id, 'id', 'not a job id');
    recipe(); // the same parameter rules as a recipe
  }

  /// The processing parameters of [recipe] for [input].
  factory JobRequest.of(Recipe recipe, String input, {String? id}) => JobRequest(
    id: id,
    input: input,
    scale: recipe.scale,
    fast2: recipe.fast2,
    srModel: recipe.srModel,
  );

  /// The job directory name under AppSupport/jobs (`[A-Za-z0-9_-]{1,64}` in the core).
  final String id;

  /// Absolute path of the inbox copy (ADR-0010).
  final String input;
  final int scale;
  final bool fast2;
  final String srModel;

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// The recipe this request runs, at [strength] (not stored in the request).
  Recipe recipe({double strength = 1}) =>
      Recipe(scale: scale, fast2: fast2, srModel: srModel, strength: strength);

  static const schemaVersion = 1;

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'job_id': id,
    'input': input,
    'sr_model': srModel,
    'scale': scale,
    'fast2': fast2,
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
      try {
        return JobRequest(id: id, input: input, scale: scale, fast2: fast2, srModel: srModel);
      } on ArgumentError catch (e) {
        throw FormatException('${e.message}', j);
      }
    }
    throw FormatException('not a job request', j);
  }
}
