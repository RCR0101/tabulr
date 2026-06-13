enum CourseType {
  normal,
  atc;

  String toJson() {
    switch (this) {
      case CourseType.normal:
        return 'Normal';
      case CourseType.atc:
        return 'ATC';
    }
  }

  static CourseType fromJson(String value) {
    switch (value) {
      case 'ATC':
        return CourseType.atc;
      default:
        return CourseType.normal;
    }
  }
}
