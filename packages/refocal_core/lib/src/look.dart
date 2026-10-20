/// A look (FR-LOOK-001..004, ADR-0012 amendment 0.8): a global colour filter at an [amount]
/// (one so far, pastel), and optional light [leaks], applied at export after the strength
/// blend. Global only: nothing follows a face or reshapes anything (15 §3).
class Look {
  Look(this.id, {this.amount = 1, this.leaks = false}) {
    if (!(amount >= 0 && amount <= 1)) throw ArgumentError('look amount must be 0..1, got $amount');
  }

  final LookId id;

  /// 0 the photo as processed .. 1 the full filter.
  final double amount;
  final bool leaks;

  /// Changes the pixels: a preset at a non-zero amount, or the leaks.
  bool get active => (id != LookId.none && amount > 0) || leaks;

  /// `look` of enh_export.
  Map<String, Object?> toJson() => {'id': id.name, 'amount': amount, 'leaks': leaks};

  /// Throws [FormatException] for an unknown id or a value out of range.
  factory Look.fromJson(Object? j) {
    if (j case {'id': final String name, 'amount': final num amount, 'leaks': final bool leaks}
        when amount >= 0 && amount <= 1) {
      final id = LookId.values.asNameMap()[name];
      if (id != null) return Look(id, amount: amount.toDouble(), leaks: leaks);
    }
    throw FormatException('bad look', j);
  }

  Look copyWith({LookId? id, double? amount, bool? leaks}) =>
      Look(id ?? this.id, amount: amount ?? this.amount, leaks: leaks ?? this.leaks);

  @override
  bool operator ==(Object other) =>
      other is Look && other.id == id && other.amount == amount && other.leaks == leaks;

  @override
  int get hashCode => Object.hash(id, amount, leaks);
}

/// The filters of the core (native/core/src/pipeline/look.cpp).
enum LookId { none, pastel }
