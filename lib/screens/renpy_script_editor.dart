import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter_quill/flutter_quill.dart';

import 'package:renpy_editor/screens/base_editor.dart';
import 'package:renpy_editor/project_manager.dart';
import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/screens/text_to_renpy.dart';
import 'package:renpy_editor/modules/syntax_converter.dart';
import 'package:renpy_editor/modules/renpy_to_html_converter.dart';

// Editor view modes
enum EditorMode { editor, preview, split }

/// A native Ren'Py script editor that supports formatted text editing
/// and converts to Ren'Py using existing conversion infrastructure
class ScriptEditor extends RenpyEditorBase {
  const ScriptEditor({
    super.key,
    super.title = 'Ren\'Py Script Editor',
    super.filePath,
    super.onSave,
  }) : super(
          icon: Icons.edit_document,
          label: 'Script Editor',
        );

  @override
  State<ScriptEditor> createState() => _RenpyScriptEditorState();
}

class _RenpyScriptEditorState extends RenpyEditorBaseState<ScriptEditor> {
  final SyntaxAwareTextEditingController _textController =
      SyntaxAwareTextEditingController();
  final TextEditingController _htmlController = TextEditingController();
  final QuillController _richTextController = QuillController.basic();
  final ScrollController _renpyScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();

  String _currentContent = '';
  String _htmlPreview = '';
  bool _isConvertMode = false;
  String? _sourceDocumentPath;
  EditorMode _currentMode = EditorMode.split;
  bool _isGeneratingPreview = false;
  bool _localIsLoading = false;

  // File explorer state
  bool _showSidebar = true;
  List<File> _renpyFiles = [];
  String? _currentFilePath;

  // State for focus mode (from conversion_viewer)
  bool _htmlFocused = false;
  bool _renpyFocused = false;

  // Toggle between raw HTML and formatted display
  bool _showRawHtml = false;
  bool _showLineNumbers = true;

  // HTML editing state
  bool _isEditingHtml = false;

  // Helper method to manage loading state
  void _setLoading(bool loading) {
    setState(() {
      _localIsLoading = loading;
    });
  }

  @override
  void initState() {
    super.initState();

    // Initialize text controller listener
    _textController.addListener(_onTextChanged);
    _htmlController.addListener(_onHtmlChanged);
    _richTextController.addListener(_onRichTextChanged);

    // Load initial content if file path is provided
    if (widget.filePath != null) {
      _loadFile(widget.filePath!);
    } else {
      _loadDefaultContent();
    }

    // Scan for .rpy files in the project
    _scanProjectFiles();
  }

  @override
  void dispose() {
    _textController.dispose();
    _htmlController.dispose();
    _richTextController.dispose();
    _renpyScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_textController.text != _currentContent) {
      final oldContent = _currentContent;
      _currentContent = _textController.text;
      recordChange('content_edit', oldContent, _currentContent);

      // Generate preview with debouncing
      _generatePreviewDebounced();
    }
  }

  void _onHtmlChanged() {
    if (_isEditingHtml && _htmlController.text != _htmlPreview) {
      _htmlPreview = _htmlController.text;
      // Convert HTML back to Ren'Py if possible
      // For now, we'll just update the preview
      recordChange('html_edit', null, _htmlPreview);
    }
  }

  void _onRichTextChanged() {
    if (_isEditingHtml) {
      // Convert Quill document to HTML
      final html = _quillDocumentToHtml(_richTextController.document);
      if (html != _htmlPreview) {
        _htmlPreview = html;
        _htmlController.text = html;
        recordChange('html_edit', null, _htmlPreview);
      }
    }
  }

  Timer? _previewTimer;
  void _generatePreviewDebounced() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 500), () {
      _generatePreview();
    });
  }

  /// Convert Quill document to HTML for background processing
  String _quillDocumentToHtml(Document document) {
    final buffer = StringBuffer();
    buffer.write('<div>');

    for (final operation in document.toDelta().toList()) {
      if (operation.data is String) {
        String text = operation.data as String;

        // Handle attributes if present
        if (operation.attributes != null) {
          final attributes = operation.attributes!;

          // Bold
          if (attributes['bold'] == true) {
            text = '<strong>$text</strong>';
          }

          // Italic
          if (attributes['italic'] == true) {
            text = '<em>$text</em>';
          }

          // Underline
          if (attributes['underline'] == true) {
            text = '<u>$text</u>';
          }

          // Strike-through
          if (attributes['strike'] == true) {
            text = '<s>$text</s>';
          }

          // Color
          if (attributes['color'] != null) {
            text = '<span style="color: ${attributes['color']}">$text</span>';
          }

          // Size (convert to relative sizes)
          if (attributes['size'] != null) {
            text =
                '<span style="font-size: ${attributes['size']}">$text</span>';
          }
        }

        // Handle line breaks
        text = text.replaceAll('\n', '<br>');

        buffer.write(text);
      }
    }

    buffer.write('</div>');
    return buffer.toString();
  }

  /// Convert HTML content to Quill document for rich text editing
  Document _htmlToQuillDocument(String html) {
    final document = Document();

    if (html.trim().isEmpty) {
      return document;
    }

    // Enhanced HTML to Quill conversion with proper tag parsing
    String processedText = html;

    // Remove outer div tags
    processedText = processedText
        .replaceAll(RegExp(r'^<div[^>]*>'), '')
        .replaceAll(RegExp(r'</div>$'), '');

    // Handle line breaks first
    processedText = processedText
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br />', '\n');

    // Parse HTML with formatting preservation
    final segments = _parseHtmlSegments(processedText);

    int offset = 0;
    for (final segment in segments) {
      if (segment.text.isNotEmpty) {
        document.insert(offset, segment.text);

        // Apply formatting attributes
        if (segment.attributes.isNotEmpty) {
          for (final attr in segment.attributes) {
            document.format(offset, segment.text.length, attr);
          }
        }

        offset += segment.text.length;
      }
    }

    return document;
  }

  /// Parse HTML into segments with formatting information
  List<_HtmlSegment> _parseHtmlSegments(String html) {
    final segments = <_HtmlSegment>[];
    final tagStack = <String>[];
    final attributeStack = <List<Attribute>>[];

    // Simple HTML parser for basic formatting
    final regex = RegExp(r'<(/?)(\w+)(?:\s[^>]*)?>|([^<]+)');
    final matches = regex.allMatches(html);

    var currentAttributes = <Attribute>[];

    for (final match in matches) {
      final isClosing = match.group(1) == '/';
      final tagName = match.group(2);
      final textContent = match.group(3);

      if (textContent != null) {
        // Text content
        final cleanText = textContent
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&');

        segments.add(_HtmlSegment(cleanText, List.from(currentAttributes)));
      } else if (tagName != null) {
        // HTML tag
        if (isClosing) {
          // Closing tag - remove from stack
          if (tagStack.isNotEmpty && tagStack.last == tagName) {
            tagStack.removeLast();
            if (attributeStack.isNotEmpty) {
              attributeStack.removeLast();
              currentAttributes = attributeStack.isNotEmpty
                  ? List.from(attributeStack.last)
                  : <Attribute>[];
            }
          }
        } else {
          // Opening tag - add to stack
          tagStack.add(tagName);
          final newAttributes = List<Attribute>.from(currentAttributes);

          switch (tagName.toLowerCase()) {
            case 'strong':
            case 'b':
              newAttributes.add(Attribute.bold);
              break;
            case 'em':
            case 'i':
              newAttributes.add(Attribute.italic);
              break;
            case 'u':
              newAttributes.add(Attribute.underline);
              break;
            case 's':
              newAttributes.add(Attribute.strikeThrough);
              break;
          }

          attributeStack.add(newAttributes);
          currentAttributes = newAttributes;
        }
      }
    }

    return segments;
  }

  /// Build a formatting button for the rich text editor toolbar
  Widget _buildFormatButton(
      IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 32,
      ),
    );
  }

  /// Apply rich text formatting to the current selection
  void _applyRichTextFormat(String format) {
    final selection = _richTextController.selection;
    if (!selection.isValid) return;

    switch (format) {
      case 'bold':
        _richTextController.formatSelection(Attribute.bold);
        break;
      case 'italic':
        _richTextController.formatSelection(Attribute.italic);
        break;
      case 'underline':
        _richTextController.formatSelection(Attribute.underline);
        break;
      case 'strike':
        _richTextController.formatSelection(Attribute.strikeThrough);
        break;
    }
  }

  Future<void> _generatePreview() async {
    if (_currentContent.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _htmlPreview = '<p><em>No content to preview</em></p>';
          _htmlController.text = _htmlPreview;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isGeneratingPreview = true;
      });
    }

    try {
      // Use the new Ren'Py to HTML converter
      final htmlContent =
          RenpyToHtmlConverter.convertRenpyToHtml(_currentContent);

      if (mounted) {
        setState(() {
          _htmlPreview = htmlContent;
          _htmlController.text = htmlContent;
          _isGeneratingPreview = false;
        });
      }
    } catch (e) {
      LogError('Error generating preview: $e');
      if (mounted) {
        setState(() {
          _htmlPreview =
              '<p style="color: red;">Error generating preview: $e</p>';
          _htmlController.text = _htmlPreview;
          _isGeneratingPreview = false;
        });
      }
    }
  }

  // Helper methods from conversion_viewer
  Future<void> _copyToClipboard(String content, String type) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$type content copied to clipboard')),
      );
    }
  }

  // Helper method to save individual file
  Future<void> _saveFile(String content, String fileType) async {
    try {
      final debugDir = Directory('debug');
      if (!await debugDir.exists()) {
        await debugDir.create();
      }

      final fileName =
          _currentFilePath?.split('/').last.split('.').first ?? 'script';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = fileType.toLowerCase() == 'html' ? 'html' : 'rpy';

      final file = File(
        '${debugDir.path}/${fileName}_${fileType.toLowerCase()}_$timestamp.$extension',
      );

      await file.writeAsString(content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileType file saved to: ${file.path}'),
            action: SnackBarAction(
              label: 'DISMISS',
              onPressed: () {
                // Just dismiss the snackbar
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving $fileType file: $e')),
        );
      }
    }
  }

  String _addLineNumbers(String text) {
    if (!_showLineNumbers) return text;

    final lines = text.split('\n');
    final result = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final lineNum = (i + 1).toString().padLeft(3);
      result.add('$lineNum: ${lines[i]}');
    }

    return result.join('\n');
  }

  Future<void> _scanProjectFiles() async {
    if (projectManager.currentProject?.projectPath == null) return;

    try {
      final projectDir = Directory(projectManager.currentProject!.projectPath);
      if (!await projectDir.exists()) return;

      final renpyFiles = <File>[];
      await for (final entity in projectDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.rpy')) {
          renpyFiles.add(entity);
        }
      }

      // Sort files by name
      renpyFiles.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      setState(() {
        _renpyFiles = renpyFiles;
      });

      // Auto-load script.rpy if it exists and no file is currently loaded
      if (widget.filePath == null && _currentFilePath == null) {
        final scriptFile = renpyFiles.firstWhere(
          (file) => path.basename(file.path) == 'script.rpy',
          orElse: () => File(''),
        );

        if (scriptFile.path.isNotEmpty) {
          await _loadFile(scriptFile.path);
        }
      }
    } catch (e) {
      LogError('Error scanning project files: $e');
    }
  }

  Future<void> _loadFile(String filePath) async {
    _setLoading(true);

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final extension = path.extension(filePath).toLowerCase();

      if (extension == '.rpy') {
        // Load Ren'Py script directly
        _currentContent = await file.readAsString();
        _textController.text = _currentContent;
        _isConvertMode = false;
        _sourceDocumentPath = null;
        _currentFilePath = filePath;
      } else if (['.docx', '.doc', '.txt', '.md'].contains(extension)) {
        // Convert document to Ren'Py and HTML
        await _convertDocument(filePath);
        _isConvertMode = true;
        _sourceDocumentPath = filePath;
        _currentFilePath = null;
      } else {
        throw Exception('Unsupported file format: $extension');
      }

      recordChange('file_load', null, _currentContent);
      _generatePreview();
    } catch (e) {
      LogError('Error loading file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _convertDocument(String documentPath) async {
    try {
      final result = await convertFileForComparison(documentPath);
      _currentContent = result.renpy;
      _textController.text = _currentContent;
      _htmlPreview = result.html;
    } catch (e) {
      LogError('Error converting document: $e');
      rethrow;
    }
  }

  void _loadDefaultContent() {
    _currentContent = '''# Ren'Py Script Editor

label start:
    "Welcome to the Ren'Py Script Editor!"
    "You can edit your scripts here and see a live preview."
    
    return
''';
    _textController.text = _currentContent;
    _isConvertMode = false;
    _sourceDocumentPath = null;
    _generatePreview();
  }

  Future<void> _reconvertFromSource() async {
    if (_sourceDocumentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No source document available for reconversion')),
        );
      }
      return;
    }

    try {
      // Show confirmation dialog
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reconvert Document'),
          content: const Text(
            'This will replace your current edits with a fresh conversion from the source document. '
            'Any changes made in the editor will be lost. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reconvert'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        _setLoading(true);

        await _convertDocument(_sourceDocumentPath!);
        recordChange('reconvert', null, _currentContent);
        _generatePreview();

        _setLoading(false);
      }
    } catch (e) {
      LogError('Error during reconversion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during reconversion: $e')),
        );
      }
      _setLoading(false);
    }
  }

  Future<void> _importDocument() async {
    final result = await file_picker.FilePicker.platform.pickFiles(
      type: file_picker.FileType.custom,
      allowedExtensions: ['txt', 'md', 'doc', 'docx', 'rpy'],
    );

    if (result != null && result.files.single.path != null) {
      await _loadFile(result.files.single.path!);
    }
  }

  // Missing abstract methods from base class
  @override
  void parseContent(String content) {
    _currentContent = content;
    _textController.text = content;
    _generatePreview();
  }

  @override
  String generateContent() {
    return _currentContent;
  }

  @override
  String generateDefaultFilePath() {
    final baseName = _sourceDocumentPath != null
        ? path.basenameWithoutExtension(_sourceDocumentPath!)
        : 'script';
    return '${projectManager.currentProject?.projectPath ?? Directory.current.path}/$baseName.rpy';
  }

  @override
  void configureForProject(RenPyProject project) {
    // Scan for .rpy files when project is configured
    _scanProjectFiles();
  }

  @override
  Future<void> loadProjectSettings() async {
    // Load any project-specific editor settings
  }

  @override
  void applyChange(Map<String, dynamic> change, bool isUndo) {
    final type = change['type'];
    final value = isUndo ? change['oldValue'] : change['newValue'];

    switch (type) {
      case 'content_edit':
        _currentContent = value ?? '';
        _textController.text = _currentContent;
        _generatePreview();
        break;
      case 'html_edit':
        _htmlPreview = value ?? '';
        _htmlController.text = _htmlPreview;
        break;
      case 'file_load':
        _currentContent = value ?? '';
        _textController.text = _currentContent;
        _generatePreview();
        break;
      case 'reconvert':
        _currentContent = value ?? '';
        _textController.text = _currentContent;
        _generatePreview();
        break;
    }
  }

  // Rich text editing helpers
  void _insertFormatting(String openTag, String closeTag) {
    final controller = _textController;
    final text = controller.text;
    final selection = controller.selection;

    if (selection.start == selection.end) {
      // No selection, insert tags at cursor
      final newText = text.substring(0, selection.start) +
          openTag +
          closeTag +
          text.substring(selection.start);
      controller.text = newText;
      controller.selection =
          TextSelection.collapsed(offset: selection.start + openTag.length);
    } else {
      // Selection exists, wrap selected text
      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.substring(0, selection.start) +
          openTag +
          selectedText +
          closeTag +
          text.substring(selection.end);
      controller.text = newText;
      controller.selection = TextSelection.collapsed(
          offset: selection.start +
              openTag.length +
              selectedText.length +
              closeTag.length);
    }
  }

  void _insertCharacterDialogue() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        String characterName = '';
        String dialogue = '';

        return AlertDialog(
          title: const Text('Insert Character Dialogue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Character Name',
                  hintText: 'e.g., alice, narrator, etc.',
                ),
                onChanged: (value) => characterName = value,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Dialogue',
                  hintText: 'What the character says...',
                ),
                maxLines: 3,
                onChanged: (value) => dialogue = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (characterName.isNotEmpty || dialogue.isNotEmpty) {
                  final insertText = characterName.isEmpty
                      ? '"$dialogue"'
                      : '$characterName "$dialogue"';
                  _insertTextAtCursor(insertText);
                }
              },
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );
  }

  void _insertLabel() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        String labelName = '';

        return AlertDialog(
          title: const Text('Insert Label'),
          content: TextField(
            decoration: const InputDecoration(
              labelText: 'Label Name',
              hintText: 'e.g., start, chapter1, ending, etc.',
            ),
            onChanged: (value) => labelName = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (labelName.isNotEmpty) {
                  _insertTextAtCursor('label $labelName:\n    ');
                }
              },
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );
  }

  void _insertTextAtCursor(String text) {
    final controller = _textController;
    final currentText = controller.text;
    final selection = controller.selection;

    final newText = currentText.substring(0, selection.start) +
        text +
        currentText.substring(selection.end);

    controller.text = newText;
    controller.selection =
        TextSelection.collapsed(offset: selection.start + text.length);

    _onTextChanged();
  }

  Widget _buildFileExplorer() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 16,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Project Files',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: _scanProjectFiles,
                  tooltip: 'Refresh',
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),
          Expanded(
            child: _renpyFiles.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No .rpy files found in project',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _renpyFiles.length,
                    itemBuilder: (context, index) {
                      final file = _renpyFiles[index];
                      final fileName = path.basename(file.path);
                      final isSelected = _currentFilePath == file.path;

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.description,
                          size: 16,
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Theme.of(context)
                                  .iconTheme
                                  .color
                                  ?.withValues(alpha: 0.7),
                        ),
                        title: Text(
                          fileName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          path.relative(file.path,
                              from:
                                  projectManager.currentProject?.projectPath ??
                                      ''),
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: isSelected,
                        selectedTileColor: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.1),
                        onTap: () => _loadFile(file.path),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormattingToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.format_bold, size: 20),
            onPressed: () => _insertFormatting('{b}', '{/b}'),
            tooltip: 'Bold',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.format_italic, size: 20),
            onPressed: () => _insertFormatting('{i}', '{/i}'),
            tooltip: 'Italic',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.format_underlined, size: 20),
            onPressed: () => _insertFormatting('{u}', '{/u}'),
            tooltip: 'Underline',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.strikethrough_s, size: 20),
            onPressed: () => _insertFormatting('{s}', '{/s}'),
            tooltip: 'Strikethrough',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.format_color_text, size: 20),
            onPressed: () => _insertFormatting('{color=#FF0000}', '{/color}'),
            tooltip: 'Text Color',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.text_increase, size: 20),
            onPressed: () => _insertFormatting('{size=+4}', '{/size}'),
            tooltip: 'Increase Size',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.text_decrease, size: 20),
            onPressed: () => _insertFormatting('{size=-4}', '{/size}'),
            tooltip: 'Decrease Size',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.person_add, size: 20),
            onPressed: _insertCharacterDialogue,
            tooltip: 'Insert Character Dialogue',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.label, size: 20),
            onPressed: _insertLabel,
            tooltip: 'Insert Label',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Project info
            if (_currentFilePath != null)
              Expanded(
                child: Text(
                  'Viewing: ${path.basename(_currentFilePath!)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Expanded(
                child: Text(
                  'New Script',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // Sidebar toggle
            IconButton(
              icon: Icon(
                _showSidebar ? Icons.menu_open : Icons.menu,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _showSidebar = !_showSidebar;
                });
              },
              tooltip: _showSidebar ? 'Hide Sidebar' : 'Show Sidebar',
            ),

            // Save both files
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: () async {
                try {
                  final debugDir = Directory('debug');
                  if (!await debugDir.exists()) {
                    await debugDir.create();
                  }

                  final fileName =
                      _currentFilePath?.split('/').last.split('.').first ??
                          'script';
                  final timestamp = DateTime.now().millisecondsSinceEpoch;

                  final htmlFile = File(
                    '${debugDir.path}/${fileName}_html_$timestamp.html',
                  );
                  final renpyFile = File(
                    '${debugDir.path}/${fileName}_renpy_$timestamp.rpy',
                  );

                  await htmlFile.writeAsString(_htmlPreview);
                  await renpyFile.writeAsString(_currentContent);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Files saved to: ${debugDir.path}'),
                        action: SnackBarAction(
                          label: 'DISMISS',
                          onPressed: () {},
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving files: $e')),
                    );
                  }
                }
              },
              tooltip: 'Save Both Files',
            ),

            // Line numbers toggle
            IconButton(
              icon: Icon(
                _showLineNumbers ? Icons.format_list_numbered : Icons.list,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _showLineNumbers = !_showLineNumbers;
                });
              },
              tooltip:
                  _showLineNumbers ? 'Hide Line Numbers' : 'Show Line Numbers',
            ),

            // Focus mode indicator/reset
            if (_htmlFocused || _renpyFocused)
              IconButton(
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _htmlFocused = false;
                    _renpyFocused = false;
                  });
                },
                tooltip: 'Exit Focus Mode',
              ),

            // Import document button
            IconButton(
              icon: const Icon(Icons.upload_file, color: Colors.white),
              onPressed: _importDocument,
              tooltip: 'Import Document',
            ),

            // Reconvert button (only show in convert mode)
            if (_isConvertMode)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _reconvertFromSource,
                tooltip: 'Reconvert from Source',
              ),

            // View mode selector
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ToggleButtons(
                isSelected: [
                  _currentMode == EditorMode.editor,
                  _currentMode == EditorMode.split,
                  _currentMode == EditorMode.preview,
                ],
                onPressed: (int index) {
                  setState(() {
                    _currentMode = EditorMode.values[index];
                  });
                },
                borderRadius: BorderRadius.circular(20),
                selectedColor: Theme.of(context).primaryColor,
                fillColor: Colors.white,
                color: Colors.white,
                constraints: const BoxConstraints(
                  minHeight: 32,
                  minWidth: 60,
                ),
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Split', style: TextStyle(fontSize: 12)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Preview', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return GestureDetector(
      onTap: () {
        setState(() {
          // Toggle focus on Ren'Py view
          _renpyFocused = !_renpyFocused;
          if (_renpyFocused) _htmlFocused = false;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Icon(Icons.edit,
                    size: 16, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ren\'Py Script Editor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Add individual save button for Ren'Py
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () => _saveFile(_currentContent, 'Ren\'Py'),
                  tooltip: 'Save Ren\'Py File',
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyToClipboard(_currentContent, 'Ren\'Py'),
                  tooltip: 'Copy Ren\'Py',
                ),
                IconButton(
                  icon: Icon(
                    _renpyFocused ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                  onPressed: () {
                    setState(() {
                      _renpyFocused = !_renpyFocused;
                      if (_renpyFocused) _htmlFocused = false;
                    });
                  },
                  tooltip:
                      _renpyFocused ? 'Exit Focus Mode' : 'Focus on Ren\'Py',
                ),
                if (_isGeneratingPreview)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          _buildFormattingToolbar(),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              color: Theme.of(context).colorScheme.surface,
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter your Ren\'Py script here...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                scrollController: _renpyScrollController,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return GestureDetector(
      onTap: () {
        setState(() {
          // Toggle focus on HTML view
          _htmlFocused = !_htmlFocused;
          if (_htmlFocused) _renpyFocused = false;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Icon(Icons.preview,
                    size: 16, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'HTML Preview/Editor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Add individual save button for HTML
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () => _saveFile(_htmlPreview, 'HTML'),
                  tooltip: 'Save HTML File',
                ),
                IconButton(
                  icon: Icon(_isEditingHtml ? Icons.preview : Icons.edit),
                  onPressed: () {
                    setState(() {
                      _isEditingHtml = !_isEditingHtml;
                      if (_isEditingHtml) {
                        // Convert HTML to Quill document when entering edit mode
                        _richTextController.document =
                            _htmlToQuillDocument(_htmlPreview);
                      }
                    });
                  },
                  tooltip: _isEditingHtml
                      ? 'Switch to Preview'
                      : 'Edit as Rich Text',
                ),
                IconButton(
                  icon:
                      Icon(_showRawHtml ? Icons.format_align_left : Icons.code),
                  onPressed: () {
                    setState(() {
                      _showRawHtml = !_showRawHtml;
                    });
                  },
                  tooltip:
                      _showRawHtml ? 'Show Formatted HTML' : 'Show Raw HTML',
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyToClipboard(_htmlPreview, 'HTML'),
                  tooltip: 'Copy HTML',
                ),
                IconButton(
                  icon: Icon(
                    _htmlFocused ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                  onPressed: () {
                    setState(() {
                      _htmlFocused = !_htmlFocused;
                      if (_htmlFocused) _renpyFocused = false;
                    });
                  },
                  tooltip: _htmlFocused ? 'Exit Focus Mode' : 'Focus on HTML',
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: _isEditingHtml
                  ? Column(
                      children: [
                        // Custom rich text toolbar
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          child: Wrap(
                            spacing: 4.0,
                            children: [
                              _buildFormatButton(
                                Icons.format_bold,
                                'Bold',
                                () => _applyRichTextFormat('bold'),
                              ),
                              _buildFormatButton(
                                Icons.format_italic,
                                'Italic',
                                () => _applyRichTextFormat('italic'),
                              ),
                              _buildFormatButton(
                                Icons.format_underlined,
                                'Underline',
                                () => _applyRichTextFormat('underline'),
                              ),
                              _buildFormatButton(
                                Icons.strikethrough_s,
                                'Strikethrough',
                                () => _applyRichTextFormat('strike'),
                              ),
                              const VerticalDivider(),
                              _buildFormatButton(
                                Icons.undo,
                                'Undo',
                                () => _richTextController.undo(),
                              ),
                              _buildFormatButton(
                                Icons.redo,
                                'Redo',
                                () => _richTextController.redo(),
                              ),
                            ],
                          ),
                        ),
                        // Rich text editor
                        Expanded(
                          child: QuillEditor.basic(
                            controller: _richTextController,
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      controller: _previewScrollController,
                      child: SelectableText(
                        _addLineNumbers(
                          _showRawHtml
                              ? _htmlPreview
                              : _formatHtml(_htmlPreview),
                        ),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatHtml(String html) {
    // Simple formatting to make HTML more readable
    return html
        .replaceAll(RegExp(r'>\s+<'), '>\n<')
        .replaceAll('<p>', '\n<p>')
        .replaceAll('</p>', '</p>\n');
  }

  @override
  Widget buildEditorBody() {
    return Column(
      children: [
        if (_localIsLoading) const LinearProgressIndicator(),
        if (_isConvertMode)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This script was converted from a document. You can edit it here or reconvert from the source.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _buildToolbar(),
        Expanded(
          child: Row(
            children: [
              // Sidebar
              if (_showSidebar) _buildFileExplorer(),

              // Main editor area
              Expanded(
                child: Builder(
                  builder: (context) {
                    // If either view is focused, show only that view
                    if (_htmlFocused) {
                      return _buildPreview();
                    } else if (_renpyFocused) {
                      return _buildEditor();
                    }

                    // Otherwise, show views based on selected mode
                    switch (_currentMode) {
                      case EditorMode.editor:
                        return _buildEditor();
                      case EditorMode.preview:
                        return _buildPreview();
                      case EditorMode.split:
                        // Determine screen orientation for layout
                        final isLandscape = MediaQuery.of(context).size.width >
                            MediaQuery.of(context).size.height;

                        if (isLandscape) {
                          // Side by side in landscape
                          return Row(
                            children: [
                              Expanded(child: _buildEditor()),
                              Container(
                                width: 2,
                                color: Theme.of(context).dividerColor,
                              ), // Divider
                              Expanded(child: _buildPreview()),
                            ],
                          );
                        } else {
                          // Stacked in portrait
                          return Column(
                            children: [
                              Expanded(child: _buildEditor()),
                              Container(
                                height: 2,
                                color: Theme.of(context).dividerColor,
                              ), // Divider
                              Expanded(child: _buildPreview()),
                            ],
                          );
                        }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Helper class for HTML segment parsing
class _HtmlSegment {
  final String text;
  final List<Attribute> attributes;

  _HtmlSegment(this.text, this.attributes);
}
