import 'package:flutter/foundation.dart';

class WeightEntry {
  final String label;
  final double value;
  final double defaultValue;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  WeightEntry(this.label, this.value, this.defaultValue, this.min, this.max, this.onChanged);
}
