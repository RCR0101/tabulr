import 'package:flutter/material.dart';

Color getGradeColor(String grade, {Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  switch (grade) {
    case 'A':
      return isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
    case 'A-':
      return isDark ? const Color(0xFF5EEAD4) : const Color(0xFF14B8A6);
    case 'B':
      return isDark ? const Color(0xFF60A5FA) : const Color(0xFF3B82F6);
    case 'B-':
      return isDark ? const Color(0xFF93C5FD) : const Color(0xFF60A5FA);
    case 'C':
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
    case 'C-':
      return isDark ? const Color(0xFFFCD34D) : const Color(0xFFFBBF24);
    case 'D':
      return isDark ? const Color(0xFFF87171) : const Color(0xFFEF4444);
    case 'D-':
      return isDark ? const Color(0xFFFCA5A5) : const Color(0xFFF87171);
    case 'E':
      return isDark ? const Color(0xFFFB7185) : const Color(0xFFDC2626);
    case 'GD':
      return isDark ? const Color(0xFF22D3EE) : const Color(0xFF06B6D4);
    case 'PR':
      return isDark ? const Color(0xFFC084FC) : const Color(0xFFA855F7);
    case 'NC':
      return isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    default:
      return isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  }
}
