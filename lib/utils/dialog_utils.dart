import 'package:flutter/material.dart';

/// A utility class for displaying dialogs in the application
class DialogUtils {
  /// Show a simple error dialog
  static Future<void> showErrorDialog(
    BuildContext context,
    String message, {
    String title = 'Error',
  }) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show a confirmation dialog
  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String message, {
    String title = 'Confirm',
    String cancelText = 'Cancel',
    String confirmText = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Show an input dialog for text input
  static Future<String?> showInputDialog(
    BuildContext context,
    String message, {
    String title = 'Input',
    String cancelText = 'Cancel',
    String confirmText = 'OK',
    String? initialValue,
    String? hintText,
    String? labelText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) async {
    final controller = TextEditingController(text: initialValue);

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                labelText: labelText,
                border: const OutlineInputBorder(),
              ),
              keyboardType: keyboardType,
              obscureText: obscureText,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result;
  }

  /// Show a loading dialog
  static Future<void> showLoadingDialog(
    BuildContext context, {
    String message = 'Loading...',
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        );
      },
    );
  }
}
