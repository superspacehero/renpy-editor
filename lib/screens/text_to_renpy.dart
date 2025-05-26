import 'dart:io';
import 'dart:async';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as html;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/project_manager.dart';
import 'package:renpy_editor/screens/base_editor.dart';
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

class ConversionPage extends RenpyEditorBase {
  const ConversionPage(
      {super.key,
      super.title = 'Ren\'Py Converter',
      super.filePath,
      super.onSave})
      : super(
          icon: Icons.text_fields,
          label: 'Text Converter',
        );

  @override
  State<ConversionPage> createState() => _ConversionPageState();
}

class _ConversionPageState extends RenpyEditorBaseState<ConversionPage> {
  String? _textName;
  StreamSubscription<FileSystemEvent>? _fileSubscription; // For file monitoring

  // Variables for the embedded conversion viewer
  String? _htmlContent;
  String? _renpyContent;
  bool _isConverting = false;

  @override
  void initState() {
    // Set this to false to allow the editor to work without a project
    requireProject = false;
    super.initState();
  }

  @override
  void dispose() {
    // Clean up resources when the widget is disposed
    _fileSubscription?.cancel();
    super.dispose();
  }

  @override
  void parseContent(String content) {
    // In this editor, we don't need to parse any content initially
    // The conversion happens on demand
  }

  @override
  String generateContent() {
    // Return the Ren'Py content if available, otherwise empty string
    return _renpyContent ?? '';
  }

  @override
  String generateDefaultFilePath() {
    // Generate a default path for saving Ren'Py script
    if (_textName != null) {
      final baseName = _textName!.replaceAll(RegExp(r'\.\w+$'), '');
      return '${projectManager.currentProject?.projectPath ?? Directory.current.path}/$baseName.rpy';
    }
    return '${projectManager.currentProject?.projectPath ?? Directory.current.path}/script.rpy';
  }

  @override
  void configureForProject(RenPyProject project) {
    // Nothing specific to configure for this editor when a project is opened
  }

  @override
  Future<void> loadProjectSettings() async {
    // No project-specific settings to load for this editor
    return;
  }

  @override
  void applyChange(Map<String, dynamic> change, bool isUndo) {
    final type = change['type'];
    final value = isUndo ? change['oldValue'] : change['newValue'];

    switch (type) {
      case 'file_path':
        // No need to update the file path directly as it's handled by the base class
        // Just re-initialize content if needed
        if (value != null && currentFilePath != value) {
          // If the path changed and it's not null, we might need to re-convert
          _convert();
        }
        break;
      case 'convert':
        setState(() {
          _renpyContent = value;
        });
        break;
    }
  }

  Future<void> _pickFile() async {
    file_picker.FilePickerResult? result =
        await file_picker.FilePicker.platform.pickFiles(
      type: file_picker.FileType.custom,
      allowedExtensions: supportedFileExtensions,
    );
    if (result != null && result.files.single.path != null) {
      // Close the previous file, if any
      if (currentFilePath != null) {
        await _closeFile();
      }

      // Store file info
      final filePath = result.files.single.path;

      setState(() {
        _textName = result.files.single.name;
      });

      // Set the current file path by recording a change
      // This will handle updating the base class property
      recordChange('file_path', currentFilePath, filePath);

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

    if (currentFilePath != null) {
      try {
        final file = File(currentFilePath!);
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
    if (currentFilePath == null) return;
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
      final result = await convertFileForComparison(currentFilePath!);

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

        // Mark as dirty so the save button becomes enabled
        recordChange('convert', null, _renpyContent);
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
      _textName = null;
      _htmlContent = null;
      _renpyContent = null;
      // Record the change to update current file path to null
      recordChange('file_path', currentFilePath, null);
    });

    // Add a small delay to ensure state updates are processed
    // and all resources are properly released
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Widget buildEditorBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Text to Ren\'Py Conversion',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    'Convert text documents (TXT, Markdown, DOC, DOCX) to Ren\'Py script format.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Select Document'),
                      ),
                      const SizedBox(width: 16.0),
                      if (currentFilePath != null)
                        ElevatedButton.icon(
                          onPressed: _convert,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Convert Again'),
                        ),
                    ],
                  ),
                  if (currentFilePath != null) ...[
                    const SizedBox(height: 16.0),
                    Text(
                      'Current file: ${path.basename(currentFilePath!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          if (_isConverting)
            const Center(child: CircularProgressIndicator())
          else if (_htmlContent != null && _renpyContent != null)
            Expanded(
              child: ConversionViewer(
                htmlContent: _htmlContent!,
                renpyContent: _renpyContent!,
                textPath: currentFilePath!,
              ),
            ),
        ],
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
