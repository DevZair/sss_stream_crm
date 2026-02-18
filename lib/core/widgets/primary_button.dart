import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.disabled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    return ElevatedButton(
      onPressed: disabled || isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: disabled ? AppColors.border : AppColors.primary,
        foregroundColor: Colors.white,
      ),
      child: child,
    );
  }
}
