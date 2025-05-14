import 'package:flutter/material.dart';

import 'package:renpy_editor/theme.dart';
import 'package:renpy_editor/modules/text_to_renpy.dart';

void main() {
  runApp(const Editor());
}

class Editor extends StatelessWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenPy Editor',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const ConversionPage(title: 'Ren\'Py Converter'),
    );
  }
}
