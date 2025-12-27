/// Common validation utilities for forms and data validation
class ValidationUtils {
  /// Validate if a string is not empty
  static String? required(String? value, [String? fieldName]) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }
    return null;
  }

  /// Validate email format
  static String? email(String? value) {
    if (value == null || value.isEmpty) return null;
    
    const emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    final regExp = RegExp(emailPattern);
    
    if (!regExp.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Validate minimum length
  static String? minLength(String? value, int minLength, [String? fieldName]) {
    if (value == null || value.isEmpty) return null;
    
    if (value.length < minLength) {
      return '${fieldName ?? 'This field'} must be at least $minLength characters long';
    }
    return null;
  }

  /// Validate maximum length
  static String? maxLength(String? value, int maxLength, [String? fieldName]) {
    if (value == null || value.isEmpty) return null;
    
    if (value.length > maxLength) {
      return '${fieldName ?? 'This field'} must be no more than $maxLength characters long';
    }
    return null;
  }

  /// Validate numeric input
  static String? numeric(String? value, [String? fieldName]) {
    if (value == null || value.isEmpty) return null;
    
    if (double.tryParse(value) == null) {
      return '${fieldName ?? 'This field'} must be a valid number';
    }
    return null;
  }

  /// Validate integer input
  static String? integer(String? value, [String? fieldName]) {
    if (value == null || value.isEmpty) return null;
    
    if (int.tryParse(value) == null) {
      return '${fieldName ?? 'This field'} must be a valid integer';
    }
    return null;
  }

  /// Validate positive number
  static String? positiveNumber(String? value, [String? fieldName]) {
    if (value == null || value.isEmpty) return null;
    
    final num = double.tryParse(value);
    if (num == null || num <= 0) {
      return '${fieldName ?? 'This field'} must be a positive number';
    }
    return null;
  }

  /// Validate range for numbers
  static String? numberRange(String? value, double min, double max, [String? fieldName]) {
    if (value == null || value.isEmpty) return null;
    
    final num = double.tryParse(value);
    if (num == null) {
      return '${fieldName ?? 'This field'} must be a valid number';
    }
    
    if (num < min || num > max) {
      return '${fieldName ?? 'This field'} must be between $min and $max';
    }
    return null;
  }

  /// Validate course code format (e.g., CS F111, MATH F211)
  static String? courseCode(String? value) {
    if (value == null || value.isEmpty) return null;
    
    // Pattern for course codes like "CS F111", "MATH F211", etc.
    const courseCodePattern = r'^[A-Z]{2,4}\s[A-Z]\s?\d{3}$';
    final regExp = RegExp(courseCodePattern);
    
    if (!regExp.hasMatch(value.toUpperCase())) {
      return 'Please enter a valid course code (e.g., CS F111)';
    }
    return null;
  }

  /// Validate CGPA (0.0 to 10.0)
  static String? cgpa(String? value) {
    final numericError = numeric(value, 'CGPA');
    if (numericError != null) return numericError;
    
    final cgpaValue = double.tryParse(value!);
    if (cgpaValue == null || cgpaValue < 0.0 || cgpaValue > 10.0) {
      return 'CGPA must be between 0.0 and 10.0';
    }
    return null;
  }

  /// Validate grade (A, A-, B, B+, B-, C, C+, C-, D, E, F)
  static String? grade(String? value) {
    if (value == null || value.isEmpty) return null;
    
    const validGrades = ['A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'E', 'F'];
    if (!validGrades.contains(value.toUpperCase())) {
      return 'Please enter a valid grade (A, A-, B+, B, B-, C+, C, C-, D, E, F)';
    }
    return null;
  }

  /// Validate semester (format: 2023-1, 2023-2, etc.)
  static String? semester(String? value) {
    if (value == null || value.isEmpty) return null;
    
    const semesterPattern = r'^20\d{2}-[12]$';
    final regExp = RegExp(semesterPattern);
    
    if (!regExp.hasMatch(value)) {
      return 'Please enter a valid semester (e.g., 2023-1, 2023-2)';
    }
    return null;
  }

  /// Validate branch/discipline code
  static String? branchCode(String? value) {
    if (value == null || value.isEmpty) return null;
    
    // Common branch codes: A1, A2, A3, A4, A7, A8, AA, AB, B1, B2, B3, B4, B5
    const branchPattern = r'^[AB][1-8A-Z]$';
    final regExp = RegExp(branchPattern);
    
    if (!regExp.hasMatch(value.toUpperCase())) {
      return 'Please enter a valid branch code (e.g., A1, B2, AA)';
    }
    return null;
  }

  /// Combine multiple validators
  static String? Function(String?) combine(List<String? Function(String?)> validators) {
    return (String? value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }

  /// Create a required validator with custom message
  static String? Function(String?) requiredWithMessage(String message) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  /// Create a custom validator
  static String? Function(String?) custom(bool Function(String?) test, String errorMessage) {
    return (String? value) {
      if (value != null && !test(value)) {
        return errorMessage;
      }
      return null;
    };
  }

  /// Validate timetable name
  static String? timetableName(String? value) {
    final requiredError = required(value, 'Timetable name');
    if (requiredError != null) return requiredError;
    
    final lengthError = maxLength(value, 50, 'Timetable name');
    if (lengthError != null) return lengthError;
    
    // Check for invalid characters
    const invalidChars = r'[<>:"/\\|?*]';
    final regExp = RegExp(invalidChars);
    if (regExp.hasMatch(value!)) {
      return 'Timetable name cannot contain < > : " / \\ | ? *';
    }
    
    return null;
  }

  /// Validate file name
  static String? fileName(String? value) {
    if (value == null || value.isEmpty) return null;
    
    // Check for invalid file name characters
    const invalidChars = r'[<>:"/\\|?*]';
    final regExp = RegExp(invalidChars);
    if (regExp.hasMatch(value)) {
      return 'File name cannot contain < > : " / \\ | ? *';
    }
    
    return null;
  }

  /// Validate phone number (basic format)
  static String? phoneNumber(String? value) {
    if (value == null || value.isEmpty) return null;
    
    // Remove spaces, dashes, parentheses
    final cleanNumber = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // Check if it's a valid format (10 digits for Indian numbers)
    const phonePattern = r'^\d{10}$';
    final regExp = RegExp(phonePattern);
    
    if (!regExp.hasMatch(cleanNumber)) {
      return 'Please enter a valid 10-digit phone number';
    }
    return null;
  }

  /// Validate URL format
  static String? url(String? value) {
    if (value == null || value.isEmpty) return null;
    
    try {
      final uri = Uri.parse(value);
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        return 'Please enter a valid URL (starting with http:// or https://)';
      }
      return null;
    } catch (e) {
      return 'Please enter a valid URL';
    }
  }

  /// Validate that two fields match (e.g., password confirmation)
  static String? Function(String?) matches(String? otherValue, String fieldName) {
    return (String? value) {
      if (value != otherValue) {
        return '$fieldName does not match';
      }
      return null;
    };
  }

  /// Validate password strength
  static String? passwordStrength(String? value, {
    int minLength = 8,
    bool requireUppercase = true,
    bool requireLowercase = true,
    bool requireNumbers = true,
    bool requireSpecialChars = false,
  }) {
    if (value == null || value.isEmpty) return null;
    
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters long';
    }
    
    if (requireUppercase && !value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    
    if (requireLowercase && !value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    
    if (requireNumbers && !value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    
    if (requireSpecialChars && !value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }
    
    return null;
  }
}

/// Extension on String for easy validation
extension StringValidation on String? {
  /// Check if string is not null and not empty
  bool get isNotNullOrEmpty => this != null && this!.isNotEmpty;
  
  /// Check if string is null or empty
  bool get isNullOrEmpty => this == null || this!.isEmpty;
  
  /// Check if string is a valid email
  bool get isValidEmail => ValidationUtils.email(this) == null;
  
  /// Check if string is numeric
  bool get isNumeric => ValidationUtils.numeric(this) == null;
  
  /// Check if string is a valid course code
  bool get isValidCourseCode => ValidationUtils.courseCode(this) == null;
}