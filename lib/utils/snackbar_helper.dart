import 'package:flutter/material.dart';

void showSnackBar({
  required BuildContext context,
  required String message,
  Duration duration = const Duration(seconds: 2),
}) {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  scaffoldMessenger.showSnackBar(
    SnackBar(content: Text(message), duration: duration),
  );
}
