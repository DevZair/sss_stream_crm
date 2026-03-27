import 'package:flutter/cupertino.dart';

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
    final isInactive = disabled || isLoading;

    Widget child = isLoading
        ? const CupertinoActivityIndicator(color: CupertinoColors.white)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: CupertinoColors.white),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          );

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: CupertinoButton(
        color: isInactive
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.primary,
        borderRadius: BorderRadius.circular(14),
        padding: EdgeInsets.zero,
        onPressed: isInactive ? null : onPressed,
        child: child,
      ),
    );
  }
}
