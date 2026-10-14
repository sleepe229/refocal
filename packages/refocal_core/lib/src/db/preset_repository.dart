import 'dart:convert';

import 'package:drift/drift.dart';

import '../recipe.dart';
import 'database.dart';

/// A user preset (FR-PRE-002): processing parameters under a name. The output format is not
/// part of it; it is chosen when saving (06 §3.4).
class Preset {
  const Preset({required this.id, required this.name, required this.recipe});

  final String id, name;
  final Recipe recipe;

  static const maxNameLength = 40;

  /// 1..[maxNameLength] UTF-16 code units after trimming.
  static bool isValidName(String name) {
    final n = name.trim();
    return n.isNotEmpty && n.length <= maxNameLength;
  }

  /// The trimmed name, or [ArgumentError] when it is not [isValidName].
  static String validName(String name) {
    if (!isValidName(name)) {
      throw ArgumentError.value(name, 'name', 'must be 1..$maxNameLength characters');
    }
    return name.trim();
  }
}

/// User presets over `presets` (07 §3).
class PresetRepository {
  PresetRepository(this._db);

  final RefocalDatabase _db;

  /// In the order they were created.
  Stream<List<Preset>> watchAll() =>
      (_db.select(_db.presets)..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).watch().map(
        (rows) => [for (final r in rows) _preset(r)],
      );

  /// A recipe this version cannot read throws [FormatException].
  Preset _preset(PresetRow r) => Preset(
    id: r.id,
    name: r.name,
    recipe: Recipe.fromJson((jsonDecode(r.recipeJson) as Map).cast()),
  );

  Future<Preset> add(String name, Recipe recipe, {DateTime? now}) async {
    if (recipe.output != null) throw ArgumentError('a preset has no output format');
    final p = Preset(id: newId(), name: Preset.validName(name), recipe: recipe);
    await _db
        .into(_db.presets)
        .insert(
          PresetsCompanion.insert(
            id: p.id,
            name: p.name,
            recipeJson: jsonEncode(recipe.toJson()),
            createdAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
          ),
        );
    return p;
  }

  Future<void> rename(String id, String name) async {
    final n = Preset.validName(name);
    await (_db.update(
      _db.presets,
    )..where((p) => p.id.equals(id))).write(PresetsCompanion(name: Value(n)));
  }

  Future<void> remove(String id) => (_db.delete(_db.presets)..where((p) => p.id.equals(id))).go();
}
