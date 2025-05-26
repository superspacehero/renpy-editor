// Helper file to debug conversion process
import 'dart:io';

import 'package:renpy_editor/utils/logging.dart';

// Function to write debug output to a file
Future<void> writeDebugOutput(String content, String filename) async {
  final debugDir = Directory('debug');
  if (!await debugDir.exists()) {
    await debugDir.create();
  }

  final file = File('${debugDir.path}/$filename');
  await file.writeAsString(content);
  Log('Debug output written to ${file.path}');
}
