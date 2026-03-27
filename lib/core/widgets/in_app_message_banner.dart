import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Краткая плашка сверху экрана (как системный баннер), без модального диалога.
class InAppMessageBanner {
  InAppMessageBanner._();

  static OverlayEntry? _entry;
  static Timer? _hideTimer;

  static void dismiss() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _entry?.remove();
    _entry = null;
  }

  /// [context] — для [MediaQuery] / темы; [overlay] — обычно [NavigatorState.overlay].
  static void show({
    required OverlayState overlay,
    required BuildContext context,
    required String title,
    required String body,
    required VoidCallback onTap,
    Duration displayDuration = const Duration(seconds: 4),
  }) {
    dismiss();

    final mediaQuery = MediaQuery.of(context);
    final topInset = mediaQuery.padding.top;
    final maxWidth = mediaQuery.size.width - 16;

    _entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          top: topInset + 8,
          left: 8,
          width: maxWidth,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, -14 * (1 - value)),
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                );
              },
              child: GestureDetector(
                onTap: () {
                  dismiss();
                  onTap();
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBackground.resolveFrom(ctx),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CupertinoTheme.of(ctx).textTheme.textStyle
                              .copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CupertinoTheme.of(ctx).textTheme.textStyle
                                .copyWith(
                                  fontSize: 14,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(ctx),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_entry!);
    _hideTimer = Timer(displayDuration, dismiss);
  }
}
