import 'package:flutter/material.dart';

Color getGradeColor(String grade) {
  switch (grade) {
    case 'A':
      return const Color(0xFF0D9488);
    case 'A-':
      return const Color(0xFF14B8A6);
    case 'B':
      return const Color(0xFF3B82F6);
    case 'B-':
      return const Color(0xFF60A5FA);
    case 'C':
      return const Color(0xFFF59E0B);
    case 'C-':
      return const Color(0xFFFBBF24);
    case 'D':
      return const Color(0xFFEF4444);
    case 'D-':
      return const Color(0xFFF87171);
    case 'E':
      return const Color(0xFFDC2626);
    case 'GD':
      return const Color(0xFF06B6D4);
    case 'PR':
      return const Color(0xFFA855F7);
    case 'NC':
      return const Color(0xFF6B7280);
    default:
      return const Color(0xFF6B7280);
  }
}
