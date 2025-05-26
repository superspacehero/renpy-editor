/// Syntax converter for handling common dialogue formatting patterns
/// Converts patterns like "Name: dialogue" to proper Ren'Py format
library syntax_converter;

import 'package:flutter/material.dart';

class SyntaxConverter {
  /// Converts "Name: dialogue" format to proper Ren'Py dialogue format
  /// Returns the converted text and the new cursor position
  static SyntaxConversionResult convertDialoguePattern(
    String text,
    int cursorPosition,
  ) {
    // Find pattern like "Name: " followed by text
    final dialoguePattern = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*)$');
    final match = dialoguePattern.firstMatch(text.trim());

    if (match != null) {
      final characterName = match.group(1)!.trim();
      final dialogue = match.group(2)!.trim();

      // Convert to Ren'Py format: character "dialogue"
      final convertedText = '$characterName "$dialogue"';

      // Calculate new cursor position
      // If cursor was after the colon, place it between the quotes
      final colonPosition = text.indexOf(':');
      int newCursorPosition;

      if (cursorPosition > colonPosition) {
        // Place cursor between quotes
        newCursorPosition = characterName.length + 2; // After 'name "'
      } else {
        // Keep cursor in character name area
        newCursorPosition = cursorPosition;
      }

      return SyntaxConversionResult(
        convertedText: convertedText,
        newCursorPosition: newCursorPosition,
        wasConverted: true,
        characterName: characterName,
        dialogue: dialogue,
      );
    }

    return SyntaxConversionResult(
      convertedText: text,
      newCursorPosition: cursorPosition,
      wasConverted: false,
    );
  }

  /// Converts "Name: " shorthand by adding quotes and positioning cursor
  /// This is for when user types "Name: " and we want to auto-complete to "Name: ""
  static SyntaxConversionResult convertDialogueShorthand(
    String text,
    int cursorPosition,
  ) {
    // Check if text ends with "Name: " pattern
    final shorthandPattern = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*$');
    final match = shorthandPattern.firstMatch(text);

    if (match != null) {
      final characterName = match.group(1)!.trim();
      final convertedText = '$characterName ""';

      // Place cursor between the quotes
      final newCursorPosition = characterName.length + 2;

      return SyntaxConversionResult(
        convertedText: convertedText,
        newCursorPosition: newCursorPosition,
        wasConverted: true,
        characterName: characterName,
        dialogue: '',
      );
    }

    return SyntaxConversionResult(
      convertedText: text,
      newCursorPosition: cursorPosition,
      wasConverted: false,
    );
  }

  /// Extracts character name and dialogue from various formats
  static DialogueComponents parseDialogue(String text) {
    text = text.trim();

    // Pattern 1: character "dialogue"
    final renpyPattern = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s+"([^"]*)"$');
    final renpyMatch = renpyPattern.firstMatch(text);

    if (renpyMatch != null) {
      return DialogueComponents(
        characterName: renpyMatch.group(1)!.trim(),
        dialogue: renpyMatch.group(2)!,
        format: DialogueFormat.renpy,
      );
    }

    // Pattern 2: Name: dialogue
    final colonPattern = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*)$');
    final colonMatch = colonPattern.firstMatch(text);

    if (colonMatch != null) {
      return DialogueComponents(
        characterName: colonMatch.group(1)!.trim(),
        dialogue: colonMatch.group(2)!.trim(),
        format: DialogueFormat.colon,
      );
    }

    // Pattern 3: Just dialogue (narration)
    if (text.startsWith('"') && text.endsWith('"')) {
      return DialogueComponents(
        characterName: '',
        dialogue: text.substring(1, text.length - 1),
        format: DialogueFormat.narration,
      );
    }

    // Pattern 4: Plain text
    return DialogueComponents(
      characterName: '',
      dialogue: text,
      format: DialogueFormat.plain,
    );
  }

  /// Converts dialogue to Ren'Py format
  static String toRenpyFormat(DialogueComponents components) {
    if (components.characterName.isEmpty) {
      return '"${components.dialogue}"';
    } else {
      return '${components.characterName} "${components.dialogue}"';
    }
  }

  /// Converts dialogue to colon format
  static String toColonFormat(DialogueComponents components) {
    if (components.characterName.isEmpty) {
      return components.dialogue;
    } else {
      return '${components.characterName}: ${components.dialogue}';
    }
  }
}

class SyntaxConversionResult {
  final String convertedText;
  final int newCursorPosition;
  final bool wasConverted;
  final String? characterName;
  final String? dialogue;

  SyntaxConversionResult({
    required this.convertedText,
    required this.newCursorPosition,
    required this.wasConverted,
    this.characterName,
    this.dialogue,
  });
}

class DialogueComponents {
  final String characterName;
  final String dialogue;
  final DialogueFormat format;

  DialogueComponents({
    required this.characterName,
    required this.dialogue,
    required this.format,
  });
}

enum DialogueFormat {
  renpy, // character "dialogue"
  colon, // Name: dialogue
  narration, // "dialogue"
  plain, // dialogue
}

/// Text editing controller that automatically converts dialogue patterns
class SyntaxAwareTextEditingController extends TextEditingController {
  bool enableAutoConversion = true;

  @override
  set text(String newText) {
    if (enableAutoConversion) {
      final lines = newText.split('\n');
      final convertedLines = <String>[];

      for (final line in lines) {
        final result = SyntaxConverter.convertDialoguePattern(line, 0);
        convertedLines.add(result.convertedText);
      }

      super.text = convertedLines.join('\n');
    } else {
      super.text = newText;
    }
  }

  /// Manually trigger conversion on current line
  void convertCurrentLine() {
    final currentText = text;
    final selection = this.selection;

    if (!selection.isValid) return;

    // Find the current line
    final lines = currentText.split('\n');
    int lineStart = 0;
    int currentLineIndex = 0;

    for (int i = 0; i < lines.length; i++) {
      final lineEnd = lineStart + lines[i].length;
      if (selection.start >= lineStart && selection.start <= lineEnd) {
        currentLineIndex = i;
        break;
      }
      lineStart = lineEnd + 1; // +1 for the newline character
    }

    if (currentLineIndex < lines.length) {
      final currentLine = lines[currentLineIndex];
      final cursorInLine = selection.start - lineStart;

      final result = SyntaxConverter.convertDialogueShorthand(
        currentLine,
        cursorInLine,
      );

      if (result.wasConverted) {
        lines[currentLineIndex] = result.convertedText;
        final newText = lines.join('\n');
        final newCursorPosition = lineStart + result.newCursorPosition;

        text = newText;
        this.selection = TextSelection.collapsed(offset: newCursorPosition);
      }
    }
  }
}
