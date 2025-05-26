// mammoth.dart - Dart port of specific mammoth.js functionality
// This file contains Dart implementations of mammoth.js functions needed for the project

import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/third_party/mammoth_helpers.dart';

/// Class to represent a result with both value and error information
class Result<T> {
  final T? value;
  final List<String> messages;

  Result(this.value, this.messages);
}

/// Represents an XML element in the document
class Element {
  final String name;
  final Map<String, String> attributes;
  final List<Element> children;
  final String? textContent;

  Element(this.name, this.attributes, this.children, {this.textContent});

  /// Find the first child element with the given name
  Element? first(String name) {
    for (var child in children) {
      if (child.name == name) {
        return child;
      }
    }
    return null;
  }

  /// Find the first child element with the given name or return an empty element
  Element firstOrEmpty(String name) {
    return first(name) ?? Element(name, {}, []);
  }

  /// Get the text content of this element
  String text() {
    final buffer = StringBuffer();
    _collectText(this, buffer);
    return buffer.toString();
  }

  /// Helper method to collect text from child elements
  void _collectText(Element element, StringBuffer buffer) {
    // Add direct text content if present
    if (element.textContent != null && element.textContent!.isNotEmpty) {
      buffer.write(element.textContent);
    }

    // Add text from children
    for (var child in element.children) {
      _collectText(child, buffer);
    }
  }

  /// Get all elements with the given tag name
  List<Element> getElementsByTagName(String name) {
    final result = <Element>[];
    _collectElementsByTagName(this, name, result);
    return result;
  }

  /// Helper method to collect elements with the given tag name
  void _collectElementsByTagName(
      Element element, String name, List<Element> result) {
    if (element.name == name) {
      result.add(element);
    }
    for (var child in element.children) {
      _collectElementsByTagName(child, name, result);
    }
  }

  /// Create an Element from an XmlElement
  static Element fromXmlElement(XmlElement xmlElement) {
    // Convert attributes to Map
    final attributes = <String, String>{};
    for (var attribute in xmlElement.attributes) {
      attributes[attribute.name.qualified] = attribute.value;
    }

    // Process children
    final children = <Element>[];
    String? textContent;

    for (var node in xmlElement.nodes) {
      if (node is XmlElement) {
        children.add(fromXmlElement(node));
      } else if (node is XmlText) {
        if (textContent == null) {
          textContent = node.value;
        } else {
          textContent += node.value;
        }
      }
    }

    return Element(xmlElement.name.qualified, attributes, children,
        textContent: textContent);
  }
}

/// Read a boolean value from an element
bool readBooleanElement(Element? element) {
  if (element != null) {
    String? value = element.attributes["w:val"];
    return value != "false" && value != "0";
  } else {
    return false;
  }
}

/// Read a run's properties from its XML element
Map<String, dynamic> readRunProperties(Element element) {
  var properties = <String, dynamic>{
    "type": "runProperties",
  };

  var verticalAlignmentElement = element.first("w:vertAlign");
  if (verticalAlignmentElement != null) {
    properties["verticalAlignment"] =
        verticalAlignmentElement.attributes["w:val"];
  }

  // Read color information
  var colorElement = element.first("w:color");
  if (colorElement != null && colorElement.attributes.containsKey("w:val")) {
    properties["color"] = colorElement.attributes["w:val"];
  }

  // Read highlight/background color
  var highlightElement = element.first("w:highlight");
  if (highlightElement != null &&
      highlightElement.attributes.containsKey("w:val")) {
    properties["highlight"] = highlightElement.attributes["w:val"];
  }

  // Read font size information
  var szElement = element.first("w:sz");
  if (szElement != null && szElement.attributes.containsKey("w:val")) {
    // Font size is stored in half-points, divide by 2 to get points
    int halfPoints = int.tryParse(szElement.attributes["w:val"] ?? "0") ?? 0;
    properties["fontSize"] = halfPoints / 2;
  }

  properties["isBold"] = readBooleanElement(element.first("w:b"));
  properties["isUnderline"] = readBooleanElement(element.first("w:u"));
  properties["isItalic"] = readBooleanElement(element.first("w:i"));
  properties["isStrikethrough"] = readBooleanElement(element.first("w:strike"));

  return properties;
}

/// Opens a DOCX file from bytes and extracts its contents
Archive openDocx(Uint8List fileBytes) {
  try {
    // Decode the ZIP archive from the bytes
    return ZipDecoder().decodeBytes(fileBytes);
  } catch (e) {
    throw Exception('Failed to open DOCX file: $e');
  }
}

/// Extract document XML from DOCX archive
Element extractDocumentXml(Archive archive) {
  // Find the document.xml file in the archive
  final documentEntry = archive.findFile('word/document.xml');
  if (documentEntry == null) {
    throw Exception('Could not find word/document.xml in DOCX file');
  }

  // Decompress the file
  final content = documentEntry.content as List<int>;
  final stringContent = utf8.decode(content);

  // Parse the XML
  final document = XmlDocument.parse(stringContent);
  final documentElement = document.rootElement;

  // Convert to our Element format
  return Element.fromXmlElement(documentElement);
}

/// Extract the main document content
Element extractBodyContent(Element documentElement) {
  // Navigate to the document body
  final bodyElement = documentElement.first('w:body');
  if (bodyElement == null) {
    throw Exception('Could not find document body');
  }
  return bodyElement;
}

/// Convert a run's properties to HTML style attributes
String runPropertiesToHtmlStyle(Map<String, dynamic> properties) {
  final styles = <String>[];

  if (properties["isBold"] == true) {
    styles.add('font-weight: bold');
  }

  if (properties["isItalic"] == true) {
    styles.add('font-style: italic');
  }

  if (properties["isUnderline"] == true) {
    styles.add('text-decoration: underline');
  }

  if (properties["isStrikethrough"] == true) {
    styles.add('text-decoration: line-through');
  }

  // Add text color
  if (properties.containsKey("color")) {
    styles.add('color: #${properties["color"]}');
  }

  // Add highlight/background color
  if (properties.containsKey("highlight")) {
    // Convert Word's highlight values to CSS colors
    final highlightColor =
        convertHighlightToHex(properties["highlight"] as String);
    styles.add('background-color: #$highlightColor');
  }

  // Add font size
  if (properties.containsKey("fontSize")) {
    styles.add('font-size: ${properties["fontSize"]}pt');
  }

  return styles.join('; ');
}

/// Read a paragraph's properties from its XML element
Map<String, dynamic> readParagraphProperties(Element paragraph) {
  var properties = <String, dynamic>{
    "type": "paragraphProperties",
  };

  // Find paragraph properties element
  var pPrElement = paragraph.first("w:pPr");
  if (pPrElement == null) {
    return properties;
  }

  // Find paragraph style
  var styleElement = pPrElement.first("w:pStyle");
  if (styleElement != null && styleElement.attributes.containsKey("w:val")) {
    properties["style"] = styleElement.attributes["w:val"];
  }

  return properties;
}

/// Determine HTML element type based on paragraph style
String getHtmlElementForParagraph(Map<String, dynamic> properties) {
  // Check for heading styles
  if (properties.containsKey("style")) {
    String style = properties["style"];
    if (style.startsWith("Heading")) {
      // Extract heading level number
      final headingMatch = RegExp(r'Heading(\d+)').firstMatch(style);
      if (headingMatch != null) {
        int level = int.tryParse(headingMatch.group(1) ?? "") ?? 0;
        // Only handle h1-h6
        if (level >= 1 && level <= 6) {
          return 'h$level';
        }
      }
    } else if (style == "Title") {
      return 'h1';
    } else if (style == "Subtitle") {
      return 'h2';
    }
  }

  // Default to paragraph
  return 'p';
}

/// Process a paragraph element and convert it to HTML
String paragraphToHtml(Element paragraph) {
  // Read paragraph properties to check for styles
  final paragraphProperties = readParagraphProperties(paragraph);
  final htmlElement = getHtmlElementForParagraph(paragraphProperties);

  final buffer = StringBuffer('<$htmlElement>');

  // Process runs within the paragraph
  final runs = paragraph.getElementsByTagName('w:r');
  for (var run in runs) {
    final runProperties = run.first('w:rPr');
    String style = '';

    if (runProperties != null) {
      final props = readRunProperties(runProperties);
      style = runPropertiesToHtmlStyle(props);
    }

    // Get text content from the run
    final textElements = run.getElementsByTagName('w:t');
    for (var textElement in textElements) {
      final text = convertSmartQuotesToStandard(textElement.text());
      if (style.isNotEmpty) {
        buffer.write('<span style="$style">$text</span>');
      } else {
        buffer.write(text);
      }
    }
  }

  buffer.write('</$htmlElement>');
  return buffer.toString();
}

/// Convert a DOCX file to HTML
String convertDocxToHtml(Uint8List fileBytes) {
  String output = '';
  try {
    final archive = openDocx(fileBytes);
    final documentElement = extractDocumentXml(archive);
    final bodyContent = extractBodyContent(documentElement);

    // Process paragraphs
    final paragraphs = bodyContent.getElementsByTagName('w:p');
    final htmlBuffer = StringBuffer('<html><body>');

    for (var paragraph in paragraphs) {
      htmlBuffer.write(paragraphToHtml(paragraph));
    }

    htmlBuffer.write('</body></html>');
    output = htmlBuffer.toString();
  } catch (e) {
    // replace print with a logging call
    LogError('Error converting DOCX to HTML: $e');
    output = '<html><body><p>Error converting document: $e</p></body></html>';
  }

  output = cleanUpHTML(output);
  return output;
}

/// Identify file type based on content and optional file extension
enum FileType { docx, text, html, unknown }

/// Detect the file type from content and optional extension
FileType detectFileType(Uint8List fileBytes) {
  // Check for DOCX signature (ZIP file format)
  if (fileBytes.length > 4 &&
      fileBytes[0] == 0x50 &&
      fileBytes[1] == 0x4B &&
      fileBytes[2] == 0x03 &&
      fileBytes[3] == 0x04) {
    return FileType.docx;
  }

  // Try to parse as UTF8 string for content-based detection
  try {
    String content =
        utf8.decode(fileBytes.take(1000).toList()); // Check first 1000 bytes

    // Check for HTML indicators
    if (content.contains('<html') || content.contains('<body')) {
      return FileType.html;
    }

    // Check for markdown indicators
    if (content.contains('# ') ||
        content.contains('## ') ||
        content.contains('**') ||
        content.contains('- [ ]') ||
        (content.contains('*') && content.contains('_'))) {
      return FileType.text;
    }

    // Default to text for text content
    return FileType.text;
  } catch (e) {
    LogWarning('Failed to detect file type: $e');
    return FileType.unknown;
  }
}

String convertSmartQuotesToStandard(String text) {
  return text
      .replaceAllMapped(RegExp(r'([“”])'), (match) => '"')
      .replaceAllMapped(RegExp(r'([‘’])'), (match) => "'");
}

/// Convert text to HTML
String convertTextToHtml(String text) {
  // Split content into lines for processing
  final lines = text.split('\n');
  final htmlBuffer = StringBuffer('<html><body>\n');

  // Track whether we're in a list
  bool inList = false;
  bool inOrderedList = false;

  for (int i = 0; i < lines.length; i++) {
    String line = lines[i];
    String trimmed = line.trim();

    // Skip empty lines
    if (trimmed.isEmpty) {
      if (inList) {
        // Close list if we were in one
        htmlBuffer.write(inOrderedList ? '</ol>\n' : '</ul>\n');
        inList = false;
      }
      continue;
    }

    // Headers
    if (trimmed.startsWith('# ')) {
      if (inList) {
        htmlBuffer.write(inOrderedList ? '</ol>\n' : '</ul>\n');
        inList = false;
      }
      final headerText = trimmed.substring(2);
      htmlBuffer.write('<h1>${_processInlineMarkdown(headerText)}</h1>\n');
    } else if (trimmed.startsWith('## ')) {
      if (inList) {
        htmlBuffer.write(inOrderedList ? '</ol>\n' : '</ul>\n');
        inList = false;
      }
      final headerText = trimmed.substring(3);
      htmlBuffer.write('<h2>${_processInlineMarkdown(headerText)}</h2>\n');
    } else if (trimmed.startsWith('### ')) {
      if (inList) {
        htmlBuffer.write(inOrderedList ? '</ol>\n' : '</ul>\n');
        inList = false;
      }
      final headerText = trimmed.substring(4);
      htmlBuffer.write('<h3>${_processInlineMarkdown(headerText)}</h3>\n');
    }
    // Unordered lists
    else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      if (!inList) {
        htmlBuffer.write('<ul>\n');
        inList = true;
        inOrderedList = false;
      } else if (inOrderedList) {
        // Switch from ordered to unordered
        htmlBuffer.write('</ol>\n<ul>\n');
        inOrderedList = false;
      }

      final listItemText = trimmed.substring(2);
      htmlBuffer.write('<li>${_processInlineMarkdown(listItemText)}</li>\n');
    }
    // Ordered lists
    else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
      if (!inList) {
        htmlBuffer.write('<ol>\n');
        inList = true;
        inOrderedList = true;
      } else if (!inOrderedList) {
        // Switch from unordered to ordered
        htmlBuffer.write('</ul>\n<ol>\n');
        inOrderedList = true;
      }

      final listItemText = trimmed.replaceFirst(RegExp(r'^\d+\.\s'), '');
      htmlBuffer.write('<li>${_processInlineMarkdown(listItemText)}</li>\n');
    }
    // Regular paragraph
    else {
      if (inList) {
        htmlBuffer.write(inOrderedList ? '</ol>\n' : '</ul>\n');
        inList = false;
      }
      htmlBuffer.write('<p>${_processInlineMarkdown(trimmed)}</p>\n');
    }
  }

  // Close any open list
  if (inList) {
    htmlBuffer.write(inOrderedList ? '</ol>\n' : '</ul>\n');
  }

  htmlBuffer.write('</body></html>');
  return htmlBuffer.toString();
}

/// Process inline markdown elements (bold, italic, code)
String _processInlineMarkdown(String text) {
  // Convert smart quotes to standard quotes first
  String normalized = convertSmartQuotesToStandard(text);

  // Escape HTML special characters first
  String result = normalized
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  // Bold: **text** or __text__
  result = result.replaceAllMapped(RegExp(r'\b(?:\*\*(.*?)\*\*|__(.*?)__)\b'),
      (match) => '<strong>${match.group(1) ?? match.group(2)}</strong>');

  // Italic: *text* or _text_
  result = result.replaceAllMapped(RegExp(r'\b(?:\*(.*?)\*|_(.*?)_)\b'),
      (match) => '<em>${match.group(1) ?? match.group(2)}</em>');

  // Inline code: `code`
  result = result.replaceAllMapped(
      RegExp(r'`(.*?)`'), (match) => '<code>${match.group(1)}</code>');

  // Links: [text](url)
  result = result.replaceAllMapped(RegExp(r'\[(.*?)\]\((.*?)\)'),
      (match) => '<a href="${match.group(2)}">${match.group(1)}</a>');

  return result;
}

/// Clean up HTML by combining adjacent tags with identical attributes
String cleanUpHTML(String html) {
  // Use regex to find adjacent spans with identical style attributes
  // Pattern looks for: <span style="X">content1</span><span style="X">content2</span>
  final pattern = RegExp(
    r'<span style="([^"]*)">([^<]*)<\/span><span style="\1">([^<]*)<\/span>',
    multiLine: true,
  );

  // Keep applying the pattern until no more matches are found
  String result = html;
  String previousResult;

  do {
    previousResult = result;
    result = result.replaceAllMapped(pattern, (match) {
      final style = match.group(1)!;
      final content1 = match.group(2)!;
      final content2 = match.group(3)!;
      return '<span style="$style">$content1$content2</span>';
    });
  } while (previousResult != result);

  return result;
}

/// Convert a file's bytes to HTML based on detected type
String convertToHtmlByType(Uint8List fileBytes) {
  final fileType = detectFileType(fileBytes);

  switch (fileType) {
    case FileType.html:
      final content = cleanUpHTML(utf8.decode(fileBytes));
      return content; // Already HTML, just return it
    case FileType.docx:
      return convertDocxToHtml(fileBytes);
    case FileType.text:
      final content = cleanUpHTML(utf8.decode(fileBytes));
      return convertTextToHtml(content);
    case FileType.unknown:
      LogWarning('Unknown file type, trying plaintext conversion');
      try {
        final content = cleanUpHTML(utf8.decode(fileBytes));
        return convertTextToHtml(content);
      } catch (e) {
        return '<html><body><p>Error: Unsupported file format</p></body></html>';
      }
  }
}

/// Main entry point for document conversion
Result<String> convertToHtml(Uint8List fileBytes) {
  try {
    final html = convertToHtmlByType(fileBytes);
    return Result(html, []);
  } catch (e) {
    LogError('Error converting to HTML: $e');
    return Result(null, ['Error converting document: $e']);
  }
}
