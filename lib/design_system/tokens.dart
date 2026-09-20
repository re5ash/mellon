import 'package:flutter/material.dart';

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppLayout {
  // Breakpoints and maximum readable width, never fixed screen sizes.
  static const railBreakpoint = 720.0;
  static const extendedRailBreakpoint = 1120.0;
  static const contentMaxWidth = 1080.0;
  static const formMaxWidth = 480.0;
  static const radius = 20.0;
}

abstract final class AppPalette {
  static const seed = Color(0xFF397FC0);
  static const lightSurface = Color(0xFFF3F8FC);
  static const darkSurface = Color(0xFF111B25);
}

abstract final class AppType {
  static const headingFamily = 'PTSerif';
}
