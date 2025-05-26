/// HTML to Ren'Py converter for rich text editing support
library html_to_renpy_converter;

import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as html;

class HtmlToRenpyConverter {
  /// Converts HTML content to Ren'Py script format
  static String convertHtmlToRenpy(String htmlContent) {
    final document = parse(htmlContent);
    final buffer = StringBuffer();

    // Process body content
    final body = document.body;
    if (body != null) {
      _processNode(body, buffer, 0);
    }

    return buffer.toString().trim();
  }

  /// Processes a single HTML node and converts it to Ren'Py format
  static void _processNode(html.Node node, StringBuffer buffer, int depth) {
    if (node is html.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        buffer.write(_processRenpyTags(text));
      }
    } else if (node is html.Element) {
      switch (node.localName?.toLowerCase()) {
        case 'p':
          _processParagraph(node, buffer, depth);
          break;
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          _processHeader(node, buffer, depth);
          break;
        case 'div':
          _processDiv(node, buffer, depth);
          break;
        case 'strong':
        case 'b':
          buffer.write('{b}');
          _processChildren(node, buffer, depth);
          buffer.write('{/b}');
          break;
        case 'em':
        case 'i':
          buffer.write('{i}');
          _processChildren(node, buffer, depth);
          buffer.write('{/i}');
          break;
        case 'u':
          buffer.write('{u}');
          _processChildren(node, buffer, depth);
          buffer.write('{/u}');
          break;
        case 's':
        case 'strike':
        case 'del':
          buffer.write('{s}');
          _processChildren(node, buffer, depth);
          buffer.write('{/s}');
          break;
        case 'span':
          _processSpan(node, buffer, depth);
          break;
        case 'br':
          buffer.write('\n');
          break;
        default:
          _processChildren(node, buffer, depth);
      }
    }
  }

  /// Processes a paragraph element
  static void _processParagraph(
      html.Element element, StringBuffer buffer, int depth) {
    final content = _getTextContent(element);

    if (content.trim().isEmpty) {
      buffer.write('\n');
      return;
    }

    // Check if this looks like dialogue
    final dialoguePattern = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s+"([^"]*)"');
    final match = dialoguePattern.firstMatch(content);

    if (match != null) {
      // This is dialogue
      final characterName = match.group(1)!;
      buffer.write('  $characterName "');
      _processChildren(element, buffer, depth + 1);
      buffer.write('"\n\n');
    } else if (content.startsWith('"') && content.endsWith('"')) {
      // This is narration
      buffer.write('  "');
      _processChildren(element, buffer, depth + 1);
      buffer.write('"\n\n');
    } else {
      // Regular content - treat as narration
      buffer.write('  "');
      _processChildren(element, buffer, depth + 1);
      buffer.write('"\n\n');
    }
  }

  /// Processes a header element
  static void _processHeader(
      html.Element element, StringBuffer buffer, int depth) {
    final content = _getTextContent(element).trim();
    if (content.isNotEmpty) {
      final labelName = _sanitizeLabelName(content);
      buffer.write('label $labelName:\n\n');
    }
  }

  /// Processes a div element
  static void _processDiv(
      html.Element element, StringBuffer buffer, int depth) {
    _processChildren(element, buffer, depth);
  }

  /// Processes a span element with style attributes
  static void _processSpan(
      html.Element element, StringBuffer buffer, int depth) {
    final style = element.attributes['style'] ?? '';
    final openTags = <String>[];
    final closeTags = <String>[];

    // Parse color
    final colorMatch = RegExp(r'color:\s*([^;]+)').firstMatch(style);
    if (colorMatch != null) {
      final color = colorMatch.group(1)!.trim();
      final hexColor = _parseColor(color);
      if (hexColor != null) {
        openTags.add('{color=#$hexColor}');
        closeTags.insert(0, '{/color}');
      }
    }

    // Parse font-size
    final sizeMatch = RegExp(r'font-size:\s*([^;]+)').firstMatch(style);
    if (sizeMatch != null) {
      final size = sizeMatch.group(1)!.trim();
      final sizeValue = _parseFontSize(size);
      if (sizeValue != null) {
        openTags.add('{size=$sizeValue}');
        closeTags.insert(0, '{/size}');
      }
    }

    // Parse font-family
    final fontMatch = RegExp(r'font-family:\s*([^;]+)').firstMatch(style);
    if (fontMatch != null) {
      final font =
          fontMatch.group(1)!.trim().replaceAll('"', '').replaceAll("'", '');
      openTags.add('{font=$font}');
      closeTags.insert(0, '{/font}');
    }

    // Parse opacity
    final opacityMatch = RegExp(r'opacity:\s*([^;]+)').firstMatch(style);
    if (opacityMatch != null) {
      final opacity = opacityMatch.group(1)!.trim();
      openTags.add('{alpha=$opacity}');
      closeTags.insert(0, '{/alpha}');
    }

    // Write opening tags
    for (final tag in openTags) {
      buffer.write(tag);
    }

    // Process children
    _processChildren(element, buffer, depth);

    // Write closing tags
    for (final tag in closeTags) {
      buffer.write(tag);
    }
  }

  /// Processes all children of an element
  static void _processChildren(
      html.Element element, StringBuffer buffer, int depth) {
    for (final child in element.nodes) {
      _processNode(child, buffer, depth);
    }
  }

  /// Gets the text content of an element
  static String _getTextContent(html.Element element) {
    final buffer = StringBuffer();
    for (final node in element.nodes) {
      if (node is html.Text) {
        buffer.write(node.text);
      } else if (node is html.Element) {
        buffer.write(_getTextContent(node));
      }
    }
    return buffer.toString();
  }

  /// Processes existing Ren'Py tags in text content
  static String _processRenpyTags(String text) {
    // If the text already contains Ren'Py tags, preserve them
    return text;
  }

  /// Sanitizes text to create a valid Ren'Py label name
  static String _sanitizeLabelName(String text) {
    // Remove markdown-style headers
    text = text.replaceAll(RegExp(r'^#+\s*'), '');

    // Convert to lowercase and replace spaces/special chars with underscores
    text = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // Ensure it starts with a letter or underscore
    if (text.isNotEmpty && RegExp(r'^[0-9]').hasMatch(text)) {
      text = 'label_$text';
    }

    return text.isEmpty ? 'unnamed_label' : text;
  }

  /// Parses a color value and returns hex format
  static String? _parseColor(String color) {
    color = color.trim();

    // Already hex format
    if (color.startsWith('#')) {
      return color.substring(1);
    }

    // RGB format
    final rgbMatch =
        RegExp(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)').firstMatch(color);
    if (rgbMatch != null) {
      final r = int.parse(rgbMatch.group(1)!);
      final g = int.parse(rgbMatch.group(2)!);
      final b = int.parse(rgbMatch.group(3)!);
      return '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }

    // Named colors
    final namedColors = {
      'red': 'FF0000',
      'green': '00FF00',
      'blue': '0000FF',
      'black': '000000',
      'white': 'FFFFFF',
      'yellow': 'FFFF00',
      'cyan': '00FFFF',
      'magenta': 'FF00FF',
      'gray': '808080',
      'grey': '808080',
    };

    return namedColors[color.toLowerCase()];
  }

  /// Parses font size and returns appropriate Ren'Py format
  static String? _parseFontSize(String size) {
    size = size.trim();

    // Remove 'px' suffix
    if (size.endsWith('px')) {
      size = size.substring(0, size.length - 2);
    }

    final sizeValue = int.tryParse(size);
    if (sizeValue != null) {
      // Convert to relative size based on default of 16px
      final diff = sizeValue - 16;
      if (diff > 0) {
        return '+$diff';
      } else if (diff < 0) {
        return '$diff';
      } else {
        return null; // Default size, no tag needed
      }
    }

    return null;
  }
}
