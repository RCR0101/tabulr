/// One CDC requirement: normally a single course, sometimes a choice between
/// alternatives of which the student takes exactly one.
///
/// Stored inside the existing `cdcs` string arrays as `CS F211|CS F213`.
/// Firestore cannot nest an array inside an array, so the alternative was
/// reshaping every branch document into maps — a migration every reader would
/// have to learn. A plain course code parses as a one-option slot, so documents
/// written before choices existed keep working untouched.
class CdcSlot {
  const CdcSlot(this.options);

  /// The courses this slot can be satisfied by, in the order the admin listed
  /// them. Never empty.
  final List<String> options;

  static const String separator = '|';

  /// Parses one stored entry. Returns null for an entry that holds no usable
  /// code at all (an empty string, a stray separator), which callers drop.
  static CdcSlot? tryParse(String raw) {
    final options = raw
        .split(separator)
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    return options.isEmpty ? null : CdcSlot(options);
  }

  static List<CdcSlot> parseAll(Iterable<String> raw) {
    final slots = <CdcSlot>[];
    for (final entry in raw) {
      final slot = tryParse(entry);
      if (slot != null) slots.add(slot);
    }
    return slots;
  }

  /// Every course named by [raw], choices flattened.
  ///
  /// This is what the "is this course a core course?" callers want — an
  /// elective pool must not offer either half of a choice, and a clash filter
  /// has no way to know which half the student will take.
  static List<String> expandAll(Iterable<String> raw) =>
      [for (final slot in parseAll(raw)) ...slot.options];

  /// The courses the student actually takes, given the picks they made for the
  /// choice slots. A choice nobody picked is left out rather than guessed at.
  ///
  /// A pick is consumed once it has answered a slot, so two choices that share
  /// an alternative each get the course the student picked for them instead of
  /// the shared one answering both.
  static List<String> resolveAll(Iterable<String> raw, Set<String> chosen) =>
      resolveSlots(parseAll(raw), chosen);

  /// [resolveAll] for callers that already hold parsed slots.
  static List<String> resolveSlots(
    Iterable<CdcSlot> slots,
    Set<String> chosen,
  ) {
    final unused = {...chosen};
    final codes = <String>[];
    for (final slot in slots) {
      if (!slot.isChoice) {
        codes.add(slot.options.first);
        continue;
      }
      for (final option in slot.options) {
        if (unused.remove(option)) {
          codes.add(option);
          break;
        }
      }
    }
    return codes;
  }

  bool get isChoice => options.length > 1;

  /// The single course this slot means, or null when it is an unanswered
  /// choice.
  String? resolve(Set<String> chosen) {
    if (!isChoice) return options.first;
    for (final option in options) {
      if (chosen.contains(option)) return option;
    }
    return null;
  }

  String encode() => options.join(separator);

  @override
  String toString() => encode();

  @override
  bool operator ==(Object other) =>
      other is CdcSlot &&
      other.options.length == options.length &&
      _sameOrder(other.options);

  bool _sameOrder(List<String> other) {
    for (var i = 0; i < options.length; i++) {
      if (options[i] != other[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(options);
}
