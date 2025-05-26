/// Ren'Py to HTML converter for preview generation and rich text editing
library renpy_to_html_converter;

class RenpyToHtmlConverter {
  /// Converts Ren'Py script content to HTML for preview
  static String convertRenpyToHtml(String renpyContent) {
    final lines = renpyContent.split('\n');
    final buffer = StringBuffer();

    buffer.write(
        '<div style="font-family: serif; line-height: 1.6; padding: 16px;">');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        buffer.write('<br>');
        continue;
      }

      if (trimmed.startsWith('label ')) {
        _processLabel(trimmed, buffer);
      } else if (_isDialogue(trimmed)) {
        _processDialogue(trimmed, buffer, line);
      } else if (trimmed.startsWith('#')) {
        _processComment(trimmed, buffer);
      } else if (trimmed.startsWith('menu:')) {
        _processMenu(trimmed, buffer);
      } else if (_isControlFlow(trimmed)) {
        _processControlFlow(trimmed, buffer);
      } else if (_isRenpyCommand(trimmed)) {
        _processRenpyCommand(trimmed, buffer);
      } else if (trimmed.startsWith(r'$')) {
        _processPythonCode(trimmed, buffer);
      } else {
        _processOtherContent(trimmed, buffer);
      }
    }

    buffer.write('</div>');
    return buffer.toString();
  }

  /// Processes a label line
  static void _processLabel(String line, StringBuffer buffer) {
    final labelMatch = RegExp(r'label\s+([^:]+):').firstMatch(line);
    if (labelMatch != null) {
      final labelName = labelMatch.group(1)!.trim();
      buffer.write(
          '<h2 style="color: #2196F3; margin-top: 24px;">Label: $labelName</h2>');
    } else {
      buffer.write(
          '<h2 style="color: #2196F3; margin-top: 24px;">${_escapeHtml(line)}</h2>');
    }
  }

  /// Checks if a line is dialogue (character speech or narration)
  static bool _isDialogue(String line) {
    // Character dialogue: character "text"
    if (RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*\s+"').hasMatch(line)) {
      return true;
    }
    // Narration: "text"
    if (line.startsWith('"') && line.endsWith('"')) {
      return true;
    }
    return false;
  }

  /// Processes dialogue (character speech or narration)
  static void _processDialogue(
      String line, StringBuffer buffer, String originalLine) {
    final characterMatch =
        RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s+"(.*)"\s*$').firstMatch(line);

    if (characterMatch != null) {
      // Character dialogue
      final characterName = characterMatch.group(1)!;
      final dialogue = characterMatch.group(2)!;
      final processedDialogue = _processRenpyTags(dialogue);

      final isIndented = originalLine.trim() != originalLine;
      final marginLeft = isIndented ? '20px' : '0px';

      buffer.write('<p style="margin-left: $marginLeft;">');
      buffer.write('<strong style="color: #4CAF50;">$characterName:</strong> ');
      buffer.write('"$processedDialogue"');
      buffer.write('</p>');
    } else if (line.startsWith('"') && line.endsWith('"')) {
      // Narration
      final narration = line.substring(1, line.length - 1);
      final processedNarration = _processRenpyTags(narration);

      final isIndented = originalLine.trim() != originalLine;
      final marginLeft = isIndented ? '20px' : '0px';

      buffer.write('<p style="margin-left: $marginLeft; font-style: italic;">');
      buffer.write('"$processedNarration"');
      buffer.write('</p>');
    } else {
      // Fallback
      final processed = _processRenpyTags(line);
      buffer.write('<p>$processed</p>');
    }
  }

  /// Processes a comment line
  static void _processComment(String line, StringBuffer buffer) {
    buffer.write(
        '<p style="color: #666; font-style: italic;">${_escapeHtml(line)}</p>');
  }

  /// Processes a menu line
  static void _processMenu(String line, StringBuffer buffer) {
    buffer.write(
        '<p style="color: #FF9800; font-weight: bold;">${_escapeHtml(line)}</p>');
  }

  /// Checks if a line is control flow (if, while, etc.)
  static bool _isControlFlow(String line) {
    return line.startsWith('if ') ||
        line.startsWith('elif ') ||
        line.startsWith('else:') ||
        line.startsWith('while ') ||
        line.startsWith('for ') ||
        line.startsWith('pass') ||
        line.startsWith('return') ||
        line.startsWith('break') ||
        line.startsWith('continue');
  }

  /// Processes control flow statements
  static void _processControlFlow(String line, StringBuffer buffer) {
    buffer.write(
        '<p style="color: #9C27B0; font-family: monospace;">${_escapeHtml(line)}</p>');
  }

  /// Checks if a line is a Ren'Py command
  static bool _isRenpyCommand(String line) {
    return line.startsWith('jump ') ||
        line.startsWith('call ') ||
        line.startsWith('scene ') ||
        line.startsWith('show ') ||
        line.startsWith('hide ') ||
        line.startsWith('play ') ||
        line.startsWith('stop ') ||
        line.startsWith('pause ') ||
        line.startsWith('with ') ||
        line.startsWith('define ') ||
        line.startsWith('default ');
  }

  /// Processes Ren'Py commands
  static void _processRenpyCommand(String line, StringBuffer buffer) {
    buffer.write(
        '<p style="color: #3F51B5; font-family: monospace;">${_escapeHtml(line)}</p>');
  }

  /// Processes Python code lines
  static void _processPythonCode(String line, StringBuffer buffer) {
    buffer.write(
        '<p style="color: #795548; font-family: monospace; background-color: #F5F5F5; padding: 4px;">${_escapeHtml(line)}</p>');
  }

  /// Processes other content
  static void _processOtherContent(String line, StringBuffer buffer) {
    final processed = _processRenpyTags(line);
    buffer.write('<p>$processed</p>');
  }

  /// Processes Ren'Py formatting tags and converts them to HTML
  static String _processRenpyTags(String text) {
    String result = _escapeHtml(text);

    // Bold tags: {b}text{/b} -> <strong>text</strong>
    result = result.replaceAllMapped(
      RegExp(r'\{b\}(.*?)\{/b\}', dotAll: true),
      (match) => '<strong>${match.group(1)}</strong>',
    );

    // Italic tags: {i}text{/i} -> <em>text</em>
    result = result.replaceAllMapped(
      RegExp(r'\{i\}(.*?)\{/i\}', dotAll: true),
      (match) => '<em>${match.group(1)}</em>',
    );

    // Underline tags: {u}text{/u} -> <u>text</u>
    result = result.replaceAllMapped(
      RegExp(r'\{u\}(.*?)\{/u\}', dotAll: true),
      (match) => '<u>${match.group(1)}</u>',
    );

    // Strikethrough tags: {s}text{/s} -> <s>text</s>
    result = result.replaceAllMapped(
      RegExp(r'\{s\}(.*?)\{/s\}', dotAll: true),
      (match) => '<s>${match.group(1)}</s>',
    );

    // Color tags: {color=#FF0000}text{/color} -> <span style="color: #FF0000">text</span>
    result = result.replaceAllMapped(
      RegExp(r'\{color=([^}]+)\}(.*?)\{/color\}', dotAll: true),
      (match) =>
          '<span style="color: ${match.group(1)}">${match.group(2)}</span>',
    );

    // Size tags: {size=+4}text{/size} or {size=20}text{/size} -> <span style="font-size: ...">text</span>
    result = result.replaceAllMapped(
      RegExp(r'\{size=([^}]+)\}(.*?)\{/size\}', dotAll: true),
      (match) {
        final sizeValue = match.group(1)!;
        String fontSize;

        if (sizeValue.startsWith('+')) {
          // Relative size increase
          final increase = int.tryParse(sizeValue.substring(1)) ?? 0;
          fontSize = '${16 + increase}px';
        } else if (sizeValue.startsWith('-')) {
          // Relative size decrease
          final decrease = int.tryParse(sizeValue.substring(1)) ?? 0;
          fontSize = '${16 - decrease}px';
        } else {
          // Absolute size
          fontSize = '${sizeValue}px';
        }

        return '<span style="font-size: $fontSize">${match.group(2)}</span>';
      },
    );

    // Font tags: {font=Arial}text{/font} -> <span style="font-family: Arial">text</span>
    result = result.replaceAllMapped(
      RegExp(r'\{font=([^}]+)\}(.*?)\{/font\}', dotAll: true),
      (match) =>
          '<span style="font-family: ${match.group(1)}">${match.group(2)}</span>',
    );

    // Alpha/opacity tags: {alpha=0.5}text{/alpha} -> <span style="opacity: 0.5">text</span>
    result = result.replaceAllMapped(
      RegExp(r'\{alpha=([^}]+)\}(.*?)\{/alpha\}', dotAll: true),
      (match) =>
          '<span style="opacity: ${match.group(1)}">${match.group(2)}</span>',
    );

    // Special character handling
    result = _handleSpecialCharacters(result);

    return result;
  }

  /// Handles special Ren'Py characters and escape sequences
  static String _handleSpecialCharacters(String text) {
    // Handle common Ren'Py special characters
    text = text.replaceAll(r'\n', '<br>');
    text = text.replaceAll(r'\"', '"');
    text = text.replaceAll(r"\'", "'");
    text = text.replaceAll(r'\\', r'\');

    return text;
  }

  /// Escapes HTML special characters
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// Extracts character name from dialogue line
  static String? extractCharacterName(String line) {
    final match =
        RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s+"').firstMatch(line.trim());
    return match?.group(1);
  }

  /// Extracts dialogue text from dialogue line
  static String? extractDialogueText(String line) {
    final characterMatch =
        RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*\s+"(.*)"\s*$').firstMatch(line.trim());
    if (characterMatch != null) {
      return characterMatch.group(1);
    }

    // Check for narration
    final narrationMatch = RegExp(r'^"(.*)"\s*$').firstMatch(line.trim());
    if (narrationMatch != null) {
      return narrationMatch.group(1);
    }

    return null;
  }

  /// Checks if the line is indented (belongs to a label or control structure)
  static bool isIndented(String line) {
    return line.length > line.trimLeft().length;
  }

  /// Gets the indentation level of a line
  static int getIndentationLevel(String line) {
    int level = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        level++;
      } else if (line[i] == '\t') {
        level += 4; // Treat tab as 4 spaces
      } else {
        break;
      }
    }
    return level;
  }
}
