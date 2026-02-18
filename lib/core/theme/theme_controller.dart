import 'package:flutter/material.dart';

class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.dark,
  );

  void toggle() {
    final next = themeMode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeMode.value = next;
  }
}
