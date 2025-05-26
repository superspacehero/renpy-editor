// A widget for displaying both HTML preview and Ren'Py output that can be embedded
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' show parse;

class ConversionViewer extends StatefulWidget {
  final String htmlContent;
  final String renpyContent;
  final String textPath;
  final VoidCallback? onClose;

  const ConversionViewer({
    super.key,
    required this.htmlContent,
    required this.renpyContent,
    required this.textPath,
    this.onClose,
  });

  @override
  State<ConversionViewer> createState() => _ConversionViewerState();
}

class _ConversionViewerState extends State<ConversionViewer> {
  late String _htmlFormatted;
  late String _renpyFormatted;
  late String _textFileName;

  // State for focus mode
  bool _htmlFocused = false;
  bool _renpyFocused = false;

  // Toggle between raw HTML and formatted display
  bool _showRawHtml = false;
  bool _showLineNumbers = true;

  @override
  void initState() {
    super.initState();
    _htmlFormatted = _formatHtml(widget.htmlContent);
    _renpyFormatted = widget.renpyContent;
    _textFileName = widget.textPath.split('/').last;
  }

  String _formatHtml(String html) {
    // Remove <html> and <body> tags for cleaner display
    final doc = parse(html);
    final bodyContent = doc.body?.innerHtml ?? html;

    // Simple formatting to make HTML more readable
    return bodyContent
        .replaceAll(RegExp(r'>\s+<'), '>\n<')
        .replaceAll('<p>', '\n<p>')
        .replaceAll('</p>', '</p>\n');
  }

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

      final fileName = widget.textPath.split('/').last.split('.').first;
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

  @override
  Widget build(BuildContext context) {
    // Actions row for the viewer
    final actionsRow = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Save both files
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: () async {
            try {
              final debugDir = Directory('debug');
              if (!await debugDir.exists()) {
                await debugDir.create();
              }

              final fileName = widget.textPath.split('/').last.split('.').first;
              final timestamp = DateTime.now().millisecondsSinceEpoch;

              final htmlFile = File(
                '${debugDir.path}/${fileName}_html_$timestamp.html',
              );
              final renpyFile = File(
                '${debugDir.path}/${fileName}_renpy_$timestamp.rpy',
              );

              await htmlFile.writeAsString(widget.htmlContent);
              await renpyFile.writeAsString(widget.renpyContent);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Files saved to: ${debugDir.path}'),
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
              if (context.mounted) {
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
          ),
          onPressed: () {
            setState(() {
              _showLineNumbers = !_showLineNumbers;
            });
          },
          tooltip: _showLineNumbers ? 'Hide Line Numbers' : 'Show Line Numbers',
        ),

        // Focus mode indicator/reset
        if (_htmlFocused || _renpyFocused)
          IconButton(
            icon: const Icon(Icons.fullscreen_exit),
            onPressed: () {
              setState(() {
                _htmlFocused = false;
                _renpyFocused = false;
              });
            },
            tooltip: 'Exit Focus Mode',
          ),

        // Close file button
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onClose, // Use the callback
          tooltip: 'Close File',
        ),
      ],
    );

    // Create the HTML content view
    Widget htmlView = GestureDetector(
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
                const Expanded(
                  child: Text(
                    'HTML Output',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Add individual save button for HTML
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () => _saveFile(widget.htmlContent, 'HTML'),
                  tooltip: 'Save HTML File',
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
                  onPressed: () => _copyToClipboard(
                    _showRawHtml ? widget.htmlContent : _htmlFormatted,
                    'HTML',
                  ),
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
              color: Theme.of(context).colorScheme.surface,
              child: SingleChildScrollView(
                child: SelectableText(
                  _addLineNumbers(
                    _showRawHtml ? widget.htmlContent : _htmlFormatted,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Create the RenPy content view
    Widget renpyView = GestureDetector(
      onTap: () {
        setState(() {
          // Toggle focus on RenPy view
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
                const Expanded(
                  child: Text(
                    'Ren\'Py Output',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Add individual save button for Ren'Py
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () => _saveFile(widget.renpyContent, 'Ren\'Py'),
                  tooltip: 'Save Ren\'Py File',
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyToClipboard(_renpyFormatted, 'Ren\'Py'),
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
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SingleChildScrollView(
                child: SelectableText(
                  _addLineNumbers(_renpyFormatted),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Main content based on focus state and orientation
    return Column(
      children: [
        // Information text and actions
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Viewing: $_textFileName',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              actionsRow,
            ],
          ),
        ),

        // Content area
        Expanded(
          child: Builder(
            builder: (context) {
              // Determine screen orientation and which views to show based on focus
              final isLandscape = MediaQuery.of(context).size.width >
                  MediaQuery.of(context).size.height;

              // If either view is focused, show only that view
              if (_htmlFocused) {
                return htmlView;
              } else if (_renpyFocused) {
                return renpyView;
              }

              // Otherwise, show both views based on orientation
              if (isLandscape) {
                // Side by side in landscape
                return Row(
                  children: [
                    Expanded(child: htmlView),
                    Container(
                      width: 2,
                      color: Theme.of(context).dividerColor,
                    ), // Divider
                    Expanded(child: renpyView),
                  ],
                );
              } else {
                // Stacked in portrait
                return Column(
                  children: [
                    Expanded(child: htmlView),
                    Container(
                      height: 2,
                      color: Theme.of(context).dividerColor,
                    ), // Divider
                    Expanded(child: renpyView),
                  ],
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
