import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final labelColor = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final fillColor = isDark
        ? AppColors.surfaceSecondary
        : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: labelColor,
              letterSpacing: -0.1,
            ),
          ),
        ),
        CupertinoTextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          autofocus: autofocus,
          placeholder: hint,
          placeholderStyle: TextStyle(
            color: labelColor.withValues(alpha: 0.7),
            fontSize: 16,
          ),
          style: TextStyle(
            fontSize: 16,
            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefix: prefix != null
              ? Padding(padding: const EdgeInsets.only(left: 10), child: prefix)
              : null,
          suffix: suffix != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: suffix,
                )
              : null,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 0.5),
          ),
        ),
      ],
    );
  }
}
