enum Campus {
  hyderabad('Hyderabad'),
  pilani('Pilani'),
  goa('Goa');

  final String displayName;
  const Campus(this.displayName);

  String get code => name;

  static Campus fromCode(String code) {
    return Campus.values.firstWhere(
      (c) => c.code == code,
      orElse: () => Campus.hyderabad,
    );
  }
}
