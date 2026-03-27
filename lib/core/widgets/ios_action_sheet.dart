import 'package:flutter/cupertino.dart';

/// Model for a single action in a Cupertino action sheet.
class IosSheetAction {
  const IosSheetAction({
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final IconData? icon;
}

/// Shows a native iOS-style [CupertinoActionSheet].
Future<void> showIosActionSheet({
  required BuildContext context,
  String? title,
  String? message,
  required List<IosSheetAction> actions,
  String cancelLabel = 'Отмена',
}) async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title != null ? Text(title) : null,
      message: message != null ? Text(message) : null,
      actions: actions
          .map(
            (a) => CupertinoActionSheetAction(
              isDestructiveAction: a.isDestructive,
              onPressed: () {
                Navigator.of(ctx).pop();
                a.onTap();
              },
              child: Text(a.label),
            ),
          )
          .toList(),
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(cancelLabel),
      ),
    ),
  );
}

/// Shows a native iOS-style [CupertinoAlertDialog].
Future<T?> showIosAlert<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<CupertinoDialogAction> actions,
}) {
  return showCupertinoDialog<T>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: message != null ? Text(message) : null,
      actions: actions,
    ),
  );
}
