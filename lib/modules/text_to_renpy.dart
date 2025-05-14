import 'dart:io';
import 'dart:async';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as html;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as file_picker;

import 'package:renpy_editor/logging.dart';

import 'package:renpy_editor/third_party/mammoth.dart';
import 'package:renpy_editor/modules/conversion_viewer.dart';

// --- constants/enums ---

const int indentationSpaces = 2;
const double defaultFontSize = 12.0;
const String defaultFontColor = '000000';
const List<String> supportedFileExtensions = ['txt', 'md', 'doc', 'docx'];

enum TextType { dialogue, narration, sound, header, none }

/// simple return for name‐stripping
class CharNameReturn {
  final bool nameFound;
  final String text;
  CharNameReturn(this.nameFound, this.text);
}

/// Holds HTML and Ren'Py content for comparison
class ConversionResult {
  final String html;
  final String renpy;

  ConversionResult(this.html, this.renpy);
}

class ConversionPage extends StatefulWidget {
  const ConversionPage({super.key, required this.title});

  final String title;

  @override
  State<ConversionPage> createState() => _ConversionPageState();
}

class _ConversionPageState extends State<ConversionPage> {
  String? _textName;
  String? _textPath;
  bool _isConverting = false;
  StreamSubscription<FileSystemEvent>? _fileSubscription; // For file monitoring

  // Variables for the embedded conversion viewer
  String? _htmlContent;
  String? _renpyContent;

  Future<void> _pickFile() async {
    file_picker.FilePickerResult? result =
        await file_picker.FilePicker.platform.pickFiles(
      type: file_picker.FileType.custom,
      allowedExtensions: supportedFileExtensions,
    );
    if (result != null && result.files.single.path != null) {
      // Close the previous file, if any
      if (_textPath != null) {
        await _closeFile();
      }

      setState(() {
        _textPath = result.files.single.path;
        _textName = result.files.single.name;
      });

      // Automatically convert the file after selection
      await _convert();

      // Start monitoring the file for changes
      _startFileMonitoring();
    }
  }

  // Method to start monitoring the selected file for changes
  void _startFileMonitoring() {
    // Cancel any existing subscription first
    _fileSubscription?.cancel();

    if (_textPath != null) {
      try {
        final file = File(_textPath!);
        _fileSubscription = file.watch().listen((event) {
          // File has changed, re-convert automatically
          _convert();
        });
      } catch (e) {
        LogError('Error monitoring file: $e');
      }
    }
  }

  Future<void> _convert() async {
    if (_textPath == null) return;
    setState(() {
      _isConverting = true;
      _htmlContent = null;
      _renpyContent = null;
    });
    try {
      final BuildContext currentContext = context;

      // Show loading indicator
      showDialog(
        context: currentContext,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Converting document...'),
              ],
            ),
          );
        },
      );

      // Convert the document and get both HTML and Ren'Py content
      final result = await convertFileForComparison(_textPath!);

      // Close the loading dialog if still mounted
      if (currentContext.mounted) {
        Navigator.of(currentContext).pop();
      }

      if (mounted) {
        setState(() {
          _htmlContent = result.html;
          _renpyContent = result.renpy;
          _isConverting = false;
        });
      }
    } catch (e) {
      // Close the loading dialog if still mounted
      if (mounted) {
        Navigator.of(context).pop();

        setState(() {
          _isConverting = false;
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error converting document: $e')),
        );
      }
    }
  }

  /// Closes the currently loaded file and resets all related state
  /// Makes sure all resources are properly released before returning
  Future<void> _closeFile() async {
    // Cancel file monitoring and wait for it to complete
    if (_fileSubscription != null) {
      await _fileSubscription!.cancel();
      _fileSubscription = null;
    }

    // Reset file-related state variables
    setState(() {
      _textPath = null;
      _textName = null;
      _htmlContent = null;
      _renpyContent = null;
    });

    // Add a small delay to ensure state updates are processed
    // and all resources are properly released
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    // Clean up resources when the widget is disposed
    _fileSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isConverting ? null : _pickFile,
                    child: Text(
                      _textName == null
                          ? 'Pick Text File'
                          : 'Selected: $_textName',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isConverting) const Center(child: CircularProgressIndicator()),

            // Content area - using Builder pattern to simplify conditional logic
            Expanded(
              child: Builder(
                builder: (context) {
                  // Show the embedded comparison view when both HTML and Ren'Py content are available
                  if (_htmlContent != null && _renpyContent != null) {
                    return ConversionViewer(
                      htmlContent: _htmlContent!,
                      renpyContent: _renpyContent!,
                      textPath: _textPath ?? 'document',
                      onClose: _closeFile,
                    );
                  }
                  // Show instructions if no file is selected yet
                  else if (_textPath == null && !_isConverting) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.upload_file,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Select a document file to convert',
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Supported formats: TXT, MD, DOC, DOCX',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return Container(); // Empty state
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Load text, then convert.
Future<void> convertTextToRenpy(String inputPath, String outputFilePath) async {
  final script = await ConvertToRenpy(inputPath).outputRenpyText();
  await File(outputFilePath).writeAsString(script);
}

/// Convert a text file to both HTML and Ren'Py for comparison
Future<ConversionResult> convertFileForComparison(String inputPath) async {
  try {
    // First check if the file exists
    final file = File(inputPath);
    if (!await file.exists()) {
      throw Exception('File not found: $inputPath');
    }

    // Check file size and warn if it's too large
    final fileSize = await file.length();
    if (fileSize > 5 * 1024 * 1024) {
      // 5MB
      LogError(
          'Warning: File size is large (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB), conversion may take longer.');
    }

    // Perform the conversion
    return await ConvertToRenpy(inputPath).outputHtmlAndRenpy();
  } catch (e) {
    LogError('Error in convertFileForComparison: $e');
    rethrow;
  }
}

class TextChunk {
  final List<html.Element> paragraphs = [];
  TextType textType = TextType.none;
  String character = '';
}

class ConvertToRenpy {
  final String filePath;
  late final FontStandards fontStandards;
  late final RenpyStyling renpyStyler;
  bool defaultLabelAdded = false;

  ConvertToRenpy(this.filePath);

  /// Outputs just the RenPy text from a conversion
  Future<String> outputRenpyText() async {
    final result = await outputHtmlAndRenpy(writeDebugFiles: true);
    return result.renpy;
  }

  /// Generates both HTML and Ren'Py outputs for comparison
  Future<ConversionResult> outputHtmlAndRenpy(
      {bool writeDebugFiles = false}) async {
    // Read file and convert to HTML using the Dart mammoth implementation
    final fileBytes = await File(filePath).readAsBytes();
    final result = convertToHtml(fileBytes);

    if (result.value == null) {
      throw Exception('Failed to convert DOCX: ${result.messages.join(', ')}');
    }

    final htmlContent = result.value!;

    // Write debug files if requested
    if (writeDebugFiles) {
      final debugDir = Directory('debug');
      if (!await debugDir.exists()) {
        await debugDir.create();
      }
      await File('${debugDir.path}/debug_html_output.html')
          .writeAsString(htmlContent);
    }

    // Process the HTML to generate Ren'Py content
    final htmlDoc = parse(htmlContent);
    // Query for both paragraph and header tags
    final elements = htmlDoc.querySelectorAll('p, h1, h2, h3, h4, h5, h6');

    // Write debug paragraph content if requested
    if (writeDebugFiles) {
      final debugDir = Directory('debug');
      final debugParasContent = elements.map((p) => p.outerHtml).join('\n');
      await File('${debugDir.path}/debug_paragraphs.txt')
          .writeAsString(debugParasContent);
    }

    final chunks = _buildChunksFromHtml(elements);

    fontStandards = FontStandards(elements, chunks);
    renpyStyler = RenpyStyling(fontStandards);

    final buf = StringBuffer();

    // Add the label at the beginning of the script
    buf.writeln('label start:');
    buf.writeln();
    defaultLabelAdded = true;

    // Process each chunk into RenPy format
    for (var chunk in chunks) {
      var text = handleStyling(chunk);
      text = handleEscapeCharacters(text);
      text = formatIndentation(chunk, text);
      buf.write(text);
    }

    final renpyContent = buf.toString();

    // Write debug RenPy output if requested
    if (writeDebugFiles) {
      final debugDir = Directory('debug');
      await File('${debugDir.path}/debug_renpy_output.rpy')
          .writeAsString(renpyContent);
    }

    return ConversionResult(htmlContent, renpyContent);
  }

  static List<TextChunk> _buildChunksFromHtml(List<html.Element> elements) {
    final chunks = <TextChunk>[];

    // Process each paragraph or header as its own chunk
    for (var element in elements) {
      final tagName = element.localName;
      final t = element.text.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('#') && !_isHeaderTag(tagName)) {
        continue; // Skip comments, but allow # in actual headers
      }

      final c = TextChunk();
      c.paragraphs.add(element); // keep original element for styling

      // Determine if this is a header by tag or styling
      if (_isHeaderTag(tagName) || _isHeaderByStyle(element, t)) {
        c.textType = TextType.header;
      } else {
        c.textType = _getTextType(t);
      }

      c.character = _getCharacter(t, c.textType);
      chunks.add(c);
    }
    return chunks;
  }

  // Helper method to check if the tag is a header tag
  static bool _isHeaderTag(String? tagName) {
    return tagName != null &&
        tagName.startsWith('h') &&
        tagName.length == 2 &&
        RegExp(r'h[1-6]').hasMatch(tagName);
  }

  // Helper method to check if element has header-like styling
  static bool _isHeaderByStyle(html.Element element, String text) {
    // Look for Markdown-style headers
    if (text.startsWith('#')) return true;

    // Check for header styling
    final style = element.attributes['style'];
    if (style != null) {
      // Headers are often larger text
      final fontSizeMatch =
          RegExp(r'font-size:\s*([\d.]+)pt').firstMatch(style);
      if (fontSizeMatch != null) {
        final size = double.tryParse(fontSizeMatch.group(1)!);
        if (size != null && size > 14.0) {
          // Assume headers are larger than 14pt
          return true;
        }
      }

      // Headers often have bold styling and are standalone paragraphs
      if ((style.contains('font-weight: bold') ||
              style.contains('font-weight:bold')) &&
          text.length < 100) {
        // Assume headers are relatively short
        return true;
      }
    }

    return false;
  }

  static TextType _getTextType(String t) {
    // Headers already handled in _buildChunksFromHtml
    if (t.contains(':')) return TextType.dialogue;
    if (t.contains('*')) return TextType.sound;
    if (t.trim().isNotEmpty) return TextType.narration;
    return TextType.none;
  }

  static String _getCharacter(String t, TextType textType) {
    if (textType != TextType.dialogue) return '';

    if (t.contains(':')) {
      final parts = t.split(':');
      if (parts.isNotEmpty) {
        return parts[0]
            .trim(); // Return the part before the colon as the character name
      }
    }
    return '';
  }

  String handleStyling(TextChunk chunk) {
    final buf = StringBuffer();

    // Skip label generation in normal paragraph processing
    // It will be handled separately at the beginning of the conversion
    if (!defaultLabelAdded && buf.isEmpty) {
      defaultLabelAdded = true;
    }

    // render each node recursively
    String renderNode(html.Node node) {
      if (node is html.Text) return node.data;
      if (node is html.Element) {
        final children = node.nodes.map(renderNode).join();
        switch (node.localName) {
          case 'strong':
          case 'b':
            return '{b}$children{/b}';
          case 'em':
          case 'i':
            return '{i}$children{/i}';
          case 'u':
            return '{u}$children{/u}';
          case 's':
          case 'strike':
            return '{s}$children{/s}';
          case 'span':
            String styled = children;
            final style = node.attributes['style'];
            if (style != null) {
              // Handle font-weight for bold
              if (style.contains('font-weight: bold') ||
                  style.contains('font-weight:bold')) {
                styled = '{b}$styled{/b}';
              }

              // Handle font-style for italic
              if (style.contains('font-style: italic') ||
                  style.contains('font-style:italic')) {
                styled = '{i}$styled{/i}';
              }

              // Handle text-decoration for underline
              if (style.contains('text-decoration: underline') ||
                  style.contains('text-decoration:underline')) {
                styled = '{u}$styled{/u}';
              }

              // Handle text-decoration for strikethrough
              if (style.contains('text-decoration: line-through') ||
                  style.contains('text-decoration:line-through')) {
                styled = '{s}$styled{/s}';
              }

              // Handle font size
              final mSize =
                  RegExp(r'font-size:\s*([\d.]+)pt').firstMatch(style);
              if (mSize != null) {
                final diff =
                    ((double.parse(mSize.group(1)!) - fontStandards.size)
                        .toInt());
                if (diff != 0) {
                  styled = '{size=+$diff}$styled{/size}';
                }
              }

              // Handle text color
              final mColor =
                  RegExp(r'color:\s*#?([0-9A-Fa-f]{6})').firstMatch(style);
              if (mColor != null && mColor.group(1)! != fontStandards.color) {
                styled = '{color=#${mColor.group(1)!}}$styled{/color}';
              }

              // Handle background/highlight color
              final mBgColor = RegExp(r'background-color:\s*#?([0-9A-Fa-f]{6})')
                  .firstMatch(style);
              if (mBgColor != null) {
                // RenPy doesn't directly support highlight colors, but we can use {alpha} or custom tags if needed
                // For now, we'll leave this commented out as Ren'Py doesn't have a direct equivalent
                // styled = '{bgcolor=#${mBgColor.group(1)!}}$styled{/bgcolor}';
              }
            }
            return styled;
          default:
            return children;
        }
      }
      return '';
    }

    for (var i = 0; i < chunk.paragraphs.length; i++) {
      final para = chunk.paragraphs[i];

      // Process the nodes
      if (chunk.textType == TextType.dialogue) {
        // For dialogue, we need to handle character names specially
        bool firstNode = true;
        for (var node in para.nodes) {
          if (firstNode && node is html.Text) {
            final cr = removeCharacterNameInText(node.data);
            if (cr.nameFound) {
              // Replace the text with just the dialogue part (without the character name)
              node.data = cr.text;
              firstNode = false;
            }
          }
          buf.write(renderNode(node));
        }
      } else {
        // For narration or other text, just process the nodes normally
        for (var node in para.nodes) {
          buf.write(renderNode(node));
        }
      }

      if (i < chunk.paragraphs.length - 1) buf.writeln();
    }
    return buf.toString();
  }

  String handleEscapeCharacters(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', r'\"')
        .replaceAll("'", r"\'")
        .replaceAll('%', r'\%');
  }

  String formatIndentation(TextChunk chunk, String text) {
    if (chunk.textType == TextType.header) {
      return formatHeader(text);
    }
    return chunk.textType == TextType.dialogue
        ? formatDialogue(chunk, text)
        : formatNonDialogue(text);
  }

  String formatHeader(String text) {
    // Clean the text for a valid label name
    String labelText = text.trim();

    // Remove Markdown-style header markers if present
    if (labelText.startsWith('#')) {
      int hashCount = 0;
      while (hashCount < labelText.length && labelText[hashCount] == '#') {
        hashCount++;
      }
      labelText = labelText.substring(hashCount).trim();
    }

    // Convert to valid label name
    final labelName = labelText
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_') // Replace spaces with underscores
        .replaceAll(RegExp(r'[^\w]'), ''); // Remove non-alphanumeric chars

    if (labelName.isEmpty) return '';

    return 'label $labelName:\n\n';
  }

  String formatDialogue(TextChunk chunk, String text) {
    if (chunk.character.isEmpty) {
      return formatNonDialogue(text);
    }

    // Format the character name and dialogue text according to Ren'Py syntax
    final tx = text.trim(); // Ensure no leading/trailing whitespaces
    return '  ${chunk.character} "$tx"\n\n';
  }

  String formatNonDialogue(String text) {
    if (text.trim().isEmpty) return '';
    return '  "$text"\n\n';
  }

  CharNameReturn removeCharacterNameInText(String? text) {
    final t = text ?? '';
    if (t.contains(':')) {
      final parts = t.split(':');
      if (parts.length > 1) {
        // Only return the part after the colon
        return CharNameReturn(true, parts.sublist(1).join(':').trim());
      }
    }
    return CharNameReturn(false, t);
  }
}

class RenpyStyling {
  final FontStandards fontStds;
  RenpyStyling(this.fontStds);

  String processNodeForStyling(html.Node node) {
    String txt;
    if (node is html.Text) {
      txt = node.data;
    } else if (node is html.Element) {
      txt = node.text;
    } else {
      txt = '';
    }

    // cast node to Element so the conditional stays Map<String,String>
    final Map<String, String> attrs = node is html.Element
        ? Map<String, String>.from(node.attributes)
        : <String, String>{};

    if (attrs['bold'] == 'true') txt = convertBold(txt);
    if (attrs['italic'] == 'true') txt = convertItalics(txt);
    if (attrs['underline'] == 'true') txt = convertUnderline(txt);
    if (attrs['fontSize'] != null) {
      txt = convertFontSize(txt, double.parse(attrs['fontSize']!));
    }
    if (attrs['colorHex'] != null) {
      txt = convertFontColor(txt, attrs['colorHex']!);
    }
    if (attrs['strikethrough'] == 'true') txt = convertStrike(txt);
    return txt;
  }

  String convertBold(String t) => '{b}$t{/b}';
  String convertItalics(String t) => '{i}$t{/i}';
  String convertUnderline(String t) => '{u}$t{/u}';
  String convertFontSize(String t, double sz) {
    final diff = (sz - fontStds.size).toInt();
    return diff == 0 ? t : '{size=+$diff}$t{/size}';
  }

  String convertFontColor(String t, String hex) =>
      identical(hex, fontStds.color) ? t : '{color=#$hex}$t{/color}';

  String convertStrike(String t) => '{s}$t{/s}';
}

class FontStandards {
  final dynamic document;
  final List<TextChunk> chunks;
  final double size;
  final String color;

  FontStandards(this.document, this.chunks)
      : size = _determineFontSize(document, chunks),
        color = defaultFontColor {
    // debug: size/color standards
  }

  static double _determineFontSize(dynamic doc, List<TextChunk> chunks) {
    final htmlParas = doc as List<html.Element>;
    final sizes = <double>[];
    for (var p in htmlParas) {
      final style = p.attributes['style'];
      if (style != null && style.contains('font-size')) {
        final match = RegExp(r'font-size:\s*(\d+)').firstMatch(style);
        if (match != null) {
          final size = double.tryParse(match.group(1) ?? '');
          if (size != null) {
            sizes.add(size);
          }
        }
      }
    }
    if (sizes.isEmpty) {
      return defaultFontSize;
    }
    // compute mode (most frequent font size)
    final freq = <double, int>{};
    for (var size in sizes) {
      freq[size] = (freq[size] ?? 0) + 1;
    }
    double modeSize = sizes.first;
    int maxCount = 0;
    freq.forEach((size, count) {
      if (count > maxCount) {
        maxCount = count;
        modeSize = size;
      }
    });
    return modeSize;
  }
}

/// A widget for displaying various document types (TXT, DOC/DOCX).
class DocumentViewer extends StatefulWidget {
  const DocumentViewer({super.key, required this.filePath});

  final String filePath;
  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  String content = '';

  String? get extension {
    final idx = widget.filePath.lastIndexOf('.');
    if (idx < 0) return null;
    return widget.filePath.substring(idx).toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _readTxt();

    // Automatically open comparison view after a short delay
    // Use a delay to allow the UI to render first
    if (extension != null &&
        supportedFileExtensions.contains(extension!.substring(1))) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _viewHtmlAndRenpy(context);
        }
      });
    }
  }

  Future<void> _readTxt() async {
    try {
      content = await File(widget.filePath).readAsString();
    } catch (e) {
      content = 'Error: $e';
    }
    setState(() {});
  }

  Future<void> _viewHtmlAndRenpy(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Converting document...'),
              ],
            ),
          );
        },
      );

      // Convert the document and get both HTML and Ren'Py content
      final result = await convertFileForComparison(widget.filePath);

      if (context.mounted) {
        // Close the loading dialog
        Navigator.of(context).pop();

        // Navigate to the comparison viewer
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ConversionViewer(
              htmlContent: result.html,
              renpyContent: result.renpy,
              textPath: widget.filePath,
            ),
          ),
        );
      }
    } catch (e) {
      // Close the loading dialog if open
      if (context.mounted) {
        Navigator.of(context).pop();

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error converting document: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (extension != null &&
        supportedFileExtensions.contains(extension!.substring(1))) {
      return Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(content),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: () => _viewHtmlAndRenpy(context),
              icon: const Icon(Icons.compare_arrows),
              label: const Text('View HTML & Ren\'Py'),
              tooltip: 'Compare HTML and Ren\'Py outputs',
            ),
          ),
        ],
      );
    }
    return Center(child: Text('Unsupported format: $extension'));
  }
}
