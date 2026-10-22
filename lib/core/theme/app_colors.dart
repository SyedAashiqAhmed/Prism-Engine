import 'package:flutter/material.dart';

/// Centralized design tokens and color palette for Prism Engine.
/// Designed with a dark background and vivid green financial accents.
abstract class AppColors {
  // --- Surface & Backgrounds ---
  static const Color background = Color(0xFF080B0A);
  static const Color surface = Color(0xFF111614);
  static const Color surfaceElevated = Color(0xFF1A211E);
  static const Color surfaceHighlight = Color(0xFF26302B);

  // --- Financial Accents ---
  /// Neon Emerald for credits, savings, and income
  static const Color credit = Color(0xFF00E599);
  static const Color creditLight = Color(0xFF34D399);
  static const Color creditContainer = Color(0x1F00E599);

  /// Coral Crimson for debits, expenses, and alerts
  static const Color debit = Color(0xFFFF4D4D);
  static const Color debitLight = Color(0xFFF87171);
  static const Color debitContainer = Color(0x1FFF4D4D);

  // --- Intelligence & Brand Accents ---
  /// Neon green for the Prism brand and smart features
  static const Color aiViolet = Color(0xFF00E599);
  static const Color aiVioletLight = Color(0xFF49F2B0);
  static const Color aiContainer = Color(0x2E00E599);

  /// Electric Cyan for placement alerts and links
  static const Color cyanAccent = Color(0xFF06B6D4);
  static const Color cyanContainer = Color(0x1F06B6D4);

  /// Amber for pending or warning states
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0x1FF59E0B);

  // --- Typography & Neutral Colors ---
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF475569);

  // --- Glassmorphic Borders & Overlays ---
  static const Color glassBorder = Color(0x1AFFFFFF); // 10% white
  static const Color glassBorderStrong = Color(0x33FFFFFF); // 20% white
  static const Color glassFill = Color(0x0DFFFFFF); // 5% white
  static const Color shimmerHighlight = Color(0x15FFFFFF);
}
