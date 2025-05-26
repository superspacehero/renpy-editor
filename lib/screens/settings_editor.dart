import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/screens/base_editor.dart';
import 'package:renpy_editor/project_manager.dart';

/// Enum for different setting types
enum RenPySettingType {
  string,
  number,
  boolean,
  color,
  font,
  transition,
  other
}

/// A model class to represent a Ren'Py configuration setting
class RenPyConfigSetting {
  String name;
  String value;
  String? comment;
  bool enabled;
  String originalLine;
  RenPySettingType type;

  RenPyConfigSetting({
    required this.name,
    required this.value,
    this.comment,
    this.enabled = true,
    required this.originalLine,
    required this.type,
  });

  @override
  String toString() {
    if (!enabled && originalLine.trim().startsWith('#')) {
      return originalLine;
    }

    String prefix = enabled ? 'define ' : '# define ';
    String commentStr = comment != null ? ' ## $comment' : '';

    // Handle different value types
    String formattedValue = value;
    if (type == RenPySettingType.string &&
        !value.startsWith('_("') &&
        !value.startsWith('"')) {
      formattedValue = '"$value"';
    }

    return '$prefix$name = $formattedValue$commentStr';
  }
}

/// A model class to represent a Ren'Py style property setting
class RenPyStylePropertySetting {
  String name;
  String value;
  bool enabled;
  String originalLine;
  RenPySettingType type;

  RenPyStylePropertySetting({
    required this.name,
    required this.value,
    this.enabled = true,
    required this.originalLine,
    required this.type,
  });

  @override
  String toString() {
    if (!enabled) {
      return '# $name $value';
    }
    return '$name $value';
  }
}

/// A model class to represent a Ren'Py style setting
class RenPyStyleSetting {
  String styleName;
  List<RenPyStylePropertySetting> properties;
  String originalBlock;
  bool isInherited;
  String? inheritsFrom;
  bool enabled;

  RenPyStyleSetting({
    required this.styleName,
    required this.properties,
    required this.originalBlock,
    this.isInherited = false,
    this.inheritsFrom,
    this.enabled = true,
  });

  @override
  String toString() {
    StringBuffer buffer = StringBuffer();

    if (enabled) {
      buffer.writeln('style $styleName:');
    } else {
      buffer.writeln('# style $styleName:');
    }

    if (isInherited && inheritsFrom != null) {
      buffer
          .writeln(enabled ? '    is $inheritsFrom' : '#    is $inheritsFrom');
    }

    for (var property in properties) {
      String prefix = enabled ? '    ' : '#    ';
      String line = property.toString();
      if (line.startsWith('# ') && enabled) {
        line = line.substring(2);
      } else if (!line.startsWith('# ') && !enabled) {
        line = '# $line';
      }
      buffer.writeln('$prefix${line.trim()}');
    }

    return buffer.toString();
  }
}

/// Main widget for the Ren'Py settings editor
class SettingsEditor extends RenpyEditorBase {
  const SettingsEditor({
    super.key,
    super.filePath,
    super.onSave,
    super.title = 'Settings Editor',
  }) : super(
          icon: Icons.settings,
          label: 'Settings Editor',
        );

  @override
  State<SettingsEditor> createState() => _RenPySettingsEditorState();
}

class _RenPySettingsEditorState extends RenpyEditorBaseState<SettingsEditor>
    with SingleTickerProviderStateMixin {
  String? _optionsFilePath;
  String? _stylesFilePath;

  List<RenPyConfigSetting> _configSettings = [];
  List<RenPyStyleSetting> _styleSettings = [];

  // Tab control
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Tab> _tabs = [
    const Tab(text: 'General Settings'),
    const Tab(text: 'Sound & Music'),
    const Tab(text: 'Transitions'),
    const Tab(text: 'Text & Fonts'),
    const Tab(text: 'Colors & Styles'),
    const Tab(text: 'Advanced'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void parseContent(String content) {
    if (_optionsFilePath != null) {
      _configSettings = _parseOptionsFile(content);
    } else if (_stylesFilePath != null) {
      _styleSettings = _parseStylesFile(content);
    }
  }

  @override
  String generateContent() {
    if (_optionsFilePath != null) {
      final optionsFile = File(_optionsFilePath!);
      final originalContent = optionsFile.readAsStringSync();
      return _updateOptionsFile(originalContent);
    } else if (_stylesFilePath != null) {
      final stylesFile = File(_stylesFilePath!);
      final originalContent = stylesFile.readAsStringSync();
      return _updateStylesFile(originalContent);
    }
    return "";
  }

  @override
  String generateDefaultFilePath() {
    return _optionsFilePath ?? _stylesFilePath ?? "options.rpy";
  }

  @override
  void configureForProject(RenPyProject project) {
    _optionsFilePath = path.join(project.gameDirPath, 'options.rpy');

    final stylesFilePath = path.join(project.gameDirPath, 'styles.rpy');
    final stylesFile = File(stylesFilePath);
    _stylesFilePath = stylesFile.existsSync() ? stylesFilePath : null;
  }

  @override
  Future<void> loadProjectSettings() async {
    try {
      if (_optionsFilePath != null) {
        final optionsFile = File(_optionsFilePath!);
        final optionsContent = await optionsFile.readAsString();
        _configSettings = _parseOptionsFile(optionsContent);
      }

      if (_stylesFilePath != null) {
        final stylesFile = File(_stylesFilePath!);
        final stylesContent = await stylesFile.readAsString();
        _styleSettings = _parseStylesFile(stylesContent);
      }
    } catch (e) {
      LogError('Error loading Ren\'Py settings: $e');
      showErrorDialog('Error loading settings: $e');
    }
  }

  @override
  void applyChange(Map<String, dynamic> change, bool isUndo) {
    final value = isUndo ? change['oldValue'] : change['newValue'];

    switch (change['type']) {
      case 'configValue':
        final setting =
            _configSettings.firstWhere((s) => s.name == change['id']);
        setState(() {
          setting.value = value;
        });
        break;

      case 'configToggle':
        final setting =
            _configSettings.firstWhere((s) => s.name == change['id']);
        setState(() {
          setting.enabled = value;
        });
        break;

      case 'styleToggle':
        final style =
            _styleSettings.firstWhere((s) => s.styleName == change['id']);
        setState(() {
          style.enabled = value;
        });
        break;

      case 'stylePropertyValue':
        final ids = change['id'].split('::');
        final styleName = ids[0];
        final propertyName = ids[1];
        final styleIndex =
            _styleSettings.indexWhere((s) => s.styleName == styleName);

        if (styleIndex >= 0) {
          final propertyIndex = _styleSettings[styleIndex]
              .properties
              .indexWhere((p) => p.name == propertyName);

          if (propertyIndex >= 0) {
            setState(() {
              _styleSettings[styleIndex].properties[propertyIndex].value =
                  value;
            });
          }
        }
        break;

      case 'stylePropertyToggle':
        final ids = change['id'].split('::');
        final styleName = ids[0];
        final propertyName = ids[1];
        final styleIndex =
            _styleSettings.indexWhere((s) => s.styleName == styleName);

        if (styleIndex >= 0) {
          final propertyIndex = _styleSettings[styleIndex]
              .properties
              .indexWhere((p) => p.name == propertyName);

          if (propertyIndex >= 0) {
            setState(() {
              _styleSettings[styleIndex].properties[propertyIndex].enabled =
                  value;
            });
          }
        }
        break;

      case 'addStyleProperty':
        final styleName = change['id'];
        final styleIndex =
            _styleSettings.indexWhere((s) => s.styleName == styleName);

        if (styleIndex >= 0) {
          if (isUndo) {
            setState(() {
              _styleSettings[styleIndex]
                  .properties
                  .removeWhere((p) => p.name == value['name']);
            });
          } else {
            setState(() {
              _styleSettings[styleIndex].properties.add(
                    RenPyStylePropertySetting(
                      name: value['name'],
                      value: value['value'],
                      enabled: true,
                      originalLine: '    ${value['name']} ${value['value']}',
                      type:
                          _determinePropertyType(value['name'], value['value']),
                    ),
                  );
            });
          }
        }
        break;
    }
  }

  /// Update the options.rpy file with changed settings
  String _updateOptionsFile(String originalContent) {
    final lines = originalContent.split('\n');
    final settingsMap = {for (var s in _configSettings) s.name: s};

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if ((line.startsWith('define ') || line.startsWith('# define ')) &&
          line.contains('=')) {
        // Extract the setting name
        final parts = line.split('=');
        if (parts.length >= 2) {
          String name = parts[0].replaceAll('define', '').trim();
          name = name.replaceAll('#', '').trim(); // Remove # if commented out

          if (settingsMap.containsKey(name)) {
            // Replace the line with the updated setting
            lines[i] = settingsMap[name]!.toString();
          }
        }
      }
    }

    return lines.join('\n');
  }

  /// Update the styles.rpy file with changed style settings
  String _updateStylesFile(String originalContent) {
    final result = StringBuffer();
    final lines = originalContent.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.startsWith('style ') && line.endsWith(':')) {
        // Extract style name
        final styleName = line.substring(6, line.length - 1).trim();

        // Find this style in our edited styles
        final styleIndex =
            _styleSettings.indexWhere((s) => s.styleName == styleName);

        if (styleIndex >= 0) {
          // Replace with updated style
          result.writeln(_styleSettings[styleIndex].toString());

          // Skip the original style block
          i++;
          while (i < lines.length &&
              (lines[i].startsWith('    ') || lines[i].trim().isEmpty)) {
            i++;
          }
          continue;
        }
      }

      // Keep the original line
      result.writeln(lines[i]);
      i++;
    }

    return result.toString();
  }

  /// Update a config setting
  void _updateConfigSetting(String name, String newValue) {
    final index = _configSettings.indexWhere((s) => s.name == name);
    if (index >= 0) {
      final oldValue = _configSettings[index].value;

      // Don't record if no actual change
      if (oldValue == newValue) return;

      setState(() {
        _configSettings[index].value = newValue;
      });

      // Record for undo/redo
      recordChange('configValue', oldValue, newValue, id: name);
    }
  }

  /// Toggle a config setting on/off
  void _toggleConfigSetting(String name, bool enabled) {
    final index = _configSettings.indexWhere((s) => s.name == name);
    if (index >= 0) {
      final oldValue = _configSettings[index].enabled;

      // Don't record if no actual change
      if (oldValue == enabled) return;

      setState(() {
        _configSettings[index].enabled = enabled;
      });

      // Record for undo/redo
      recordChange('configToggle', oldValue, enabled, id: name);
    }
  }

  /// Update a style property
  void _updateStyleProperty(
      String styleName, String propertyName, String newValue) {
    final styleIndex =
        _styleSettings.indexWhere((s) => s.styleName == styleName);
    if (styleIndex >= 0) {
      setState(() {
        // Check if the property already exists
        final propertyIndex = _styleSettings[styleIndex]
            .properties
            .indexWhere((p) => p.name == propertyName);

        if (propertyIndex >= 0) {
          // Update existing property
          final oldValue =
              _styleSettings[styleIndex].properties[propertyIndex].value;

          // Don't record if no actual change
          if (oldValue == newValue) return;

          _styleSettings[styleIndex].properties[propertyIndex].value = newValue;

          // Record the change for undo/redo
          recordChange('stylePropertyValue', oldValue, newValue,
              id: '$styleName::$propertyName');
        } else {
          // Add new property
          _styleSettings[styleIndex].properties.add(
                RenPyStylePropertySetting(
                  name: propertyName,
                  value: newValue,
                  enabled: true,
                  originalLine: '    $propertyName $newValue',
                  type: _determinePropertyType(propertyName, newValue),
                ),
              );

          // Record the change for undo/redo
          recordChange(
              'addStyleProperty',
              null,
              {
                'name': propertyName,
                'value': newValue,
              },
              id: styleName);
        }
      });
    }
  }

  /// Toggle a style setting on/off
  void _toggleStyleSetting(String styleName, bool enabled) {
    final index = _styleSettings.indexWhere((s) => s.styleName == styleName);
    if (index >= 0) {
      final oldValue = _styleSettings[index].enabled;

      // Don't record if no actual change
      if (oldValue == enabled) return;

      setState(() {
        _styleSettings[index].enabled = enabled;
      });

      // Record for undo/redo
      recordChange('styleToggle', oldValue, enabled, id: styleName);
    }
  }

  /// Toggle a style property on/off
  void _toggleStylePropertySetting(
      String styleName, String propertyName, bool enabled) {
    final styleIndex =
        _styleSettings.indexWhere((s) => s.styleName == styleName);
    if (styleIndex >= 0) {
      setState(() {
        final propertyIndex = _styleSettings[styleIndex]
            .properties
            .indexWhere((p) => p.name == propertyName);

        if (propertyIndex >= 0) {
          final oldValue =
              _styleSettings[styleIndex].properties[propertyIndex].enabled;

          // Don't record if no actual change
          if (oldValue == enabled) return;

          _styleSettings[styleIndex].properties[propertyIndex].enabled =
              enabled;

          // Record for undo/redo
          recordChange('stylePropertyToggle', oldValue, enabled,
              id: '$styleName::$propertyName');
        }
      });
    }
  }

  /// Parse the options.rpy file content
  List<RenPyConfigSetting> _parseOptionsFile(String content) {
    final List<RenPyConfigSetting> settings = [];
    final lines = content.split('\n');

    for (var line in lines) {
      final trimmedLine = line.trim();

      // Skip comments and empty lines
      if (trimmedLine.startsWith('##') || trimmedLine.isEmpty) continue;

      // Parse define statements
      if (trimmedLine.startsWith('define ') ||
          trimmedLine.startsWith('# define ')) {
        bool enabled = !trimmedLine.startsWith('# ');
        String defineLine =
            enabled ? trimmedLine : trimmedLine.substring(2).trim();

        // Extract comment if any
        String? comment;
        if (defineLine.contains('##')) {
          final commentParts = defineLine.split('##');
          defineLine = commentParts[0].trim();
          comment = commentParts[1].trim();
        }

        // Extract name and value
        if (defineLine.contains('=')) {
          final parts = defineLine.split('=');
          if (parts.length >= 2) {
            String name = parts[0].replaceAll('define', '').trim();
            String value = parts.sublist(1).join('=').trim();

            // Determine setting type
            RenPySettingType type = _determineSettingType(name, value);

            settings.add(RenPyConfigSetting(
              name: name,
              value: value,
              comment: comment,
              enabled: enabled,
              originalLine: line,
              type: type,
            ));
          }
        }
      }
    }

    return settings;
  }

  /// Determine the type of a Ren'Py setting
  RenPySettingType _determineSettingType(String name, String value) {
    // Check for boolean values
    if (value == 'True' || value == 'False') {
      return RenPySettingType.boolean;
    }

    // Check for numeric values
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
      return RenPySettingType.number;
    }

    // Check for color values
    if (value.startsWith('#') || value.contains('color')) {
      return RenPySettingType.color;
    }

    // Check for font settings
    if (name.contains('font') ||
        value.contains('.ttf') ||
        value.contains('.otf')) {
      return RenPySettingType.font;
    }

    // Check for transitions
    if (name.contains('transition') ||
        [
          'dissolve',
          'fade',
          'pixellate',
          'move',
          'wipeleft',
          'wiperight',
          'wipeup',
          'wipedown'
        ].any((t) => value.contains(t))) {
      return RenPySettingType.transition;
    }

    // Default to string
    return RenPySettingType.string;
  }

  /// Filter settings based on search query
  List<RenPyConfigSetting> get _filteredConfigSettings {
    if (_searchQuery.isEmpty) return _configSettings;
    return _configSettings
        .where((setting) =>
            setting.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            setting.value.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (setting.comment != null &&
                setting.comment!
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase())))
        .toList();
  }

  /// Filter styles based on search query
  List<RenPyStyleSetting> get _filteredStyleSettings {
    if (_searchQuery.isEmpty) return _styleSettings;
    return _styleSettings
        .where((style) =>
            style.styleName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            style.properties.any((prop) =>
                prop.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                prop.value.toLowerCase().contains(_searchQuery.toLowerCase())))
        .toList();
  }

  /// Determine the type of a Ren'Py style property
  RenPySettingType _determinePropertyType(String name, String value) {
    // Check for color values
    if (value.startsWith('#') || value.contains('color') || name == 'color') {
      return RenPySettingType.color;
    }

    // Check for font settings
    if (name.contains('font') ||
        value.contains('.ttf') ||
        value.contains('.otf')) {
      return RenPySettingType.font;
    }

    // Check for numeric values with units (px, em, etc.)
    if (RegExp(r'^\d+(\.\d+)?(px|em|%)?$').hasMatch(value)) {
      return RenPySettingType.number;
    }

    // Check for boolean values
    if (value == 'True' || value == 'False') {
      return RenPySettingType.boolean;
    }

    // Default to string
    return RenPySettingType.string;
  }

  /// Parse the styles.rpy file content
  List<RenPyStyleSetting> _parseStylesFile(String content) {
    final List<RenPyStyleSetting> styles = [];
    final lines = content.split('\n');

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.startsWith('style ') && line.endsWith(':') ||
          (line.startsWith('# style ') && line.endsWith(':'))) {
        // Extract style name and check if it's enabled
        bool enabled = !line.trim().startsWith('# ');
        String styleLine = enabled ? line : line.substring(2).trim();
        final styleName = styleLine.substring(6, styleLine.length - 1).trim();

        final properties = <RenPyStylePropertySetting>[];
        final originalLines = <String>[line];
        bool isInherited = false;
        String? inheritsFrom;

        i++;
        // Parse style properties until we hit a line that's not indented
        while (i < lines.length &&
            (lines[i].startsWith('    ') ||
                lines[i].startsWith('#    ') ||
                lines[i].trim().isEmpty)) {
          final rawLine = lines[i];
          originalLines.add(lines[i]);

          if (rawLine.trim().isEmpty) {
            i++;
            continue;
          }

          // Check if the property is commented out
          bool propertyEnabled = !rawLine.trim().startsWith('# ');
          // If the style is disabled, all properties should appear disabled even if not commented
          propertyEnabled = propertyEnabled && enabled;

          // Clean the line for parsing
          String propLine = rawLine.trim();
          if (propLine.startsWith('# ')) {
            propLine = propLine.substring(2).trim();
          }

          if (propLine.startsWith('is ')) {
            isInherited = true;
            inheritsFrom = propLine.substring(3).trim();
          } else if (propLine.isNotEmpty) {
            // Split property name and value
            final firstSpaceIndex = propLine.indexOf(' ');
            if (firstSpaceIndex > 0) {
              final propName = propLine.substring(0, firstSpaceIndex).trim();
              final propValue = propLine.substring(firstSpaceIndex + 1).trim();

              // Determine property type
              RenPySettingType propType =
                  _determinePropertyType(propName, propValue);

              properties.add(RenPyStylePropertySetting(
                name: propName,
                value: propValue,
                enabled: propertyEnabled,
                originalLine: rawLine,
                type: propType,
              ));
            }
          }

          i++;
        }

        if (originalLines.length > 1) {
          styles.add(RenPyStyleSetting(
            styleName: styleName,
            properties: properties,
            originalBlock: originalLines.join('\n'),
            isInherited: isInherited,
            inheritsFrom: inheritsFrom,
            enabled: enabled,
          ));
        }

        continue;
      }

      i++;
    }

    return styles;
  }

  /// Build a unified widget for editing a RenPy config setting
  Widget _buildSettingEditor(RenPyConfigSetting setting) {
    // Content displayed in the middle section depends on the setting type
    Widget contentWidget;

    switch (setting.type) {
      case RenPySettingType.boolean:
        bool value = setting.value == 'True';
        contentWidget = Row(
          children: [
            Switch(
              value: value,
              onChanged: setting.enabled
                  ? (newValue) {
                      _updateConfigSetting(
                          setting.name, newValue ? 'True' : 'False');
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            Text(value ? 'Enabled' : 'Disabled'),
            if (setting.comment != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  setting.comment!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
        break;

      case RenPySettingType.color:
        String colorValue = setting.value;
        if (colorValue.startsWith('#')) {
          colorValue = colorValue.replaceAll('"', '').replaceAll("'", '');
        }
        contentWidget = Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _parseColor(colorValue),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Enter color (e.g. #ff0000)',
                  helperText: setting.comment,
                ),
                controller: TextEditingController(text: colorValue),
                enabled: setting.enabled,
                onChanged: (value) {
                  _updateConfigSetting(setting.name, value);
                },
              ),
            ),
          ],
        );
        break;

      case RenPySettingType.font:
        contentWidget = Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Font path',
                  helperText: setting.comment,
                ),
                controller: TextEditingController(
                    text: setting.value.replaceAll('"', '')),
                enabled: setting.enabled,
                onChanged: (value) {
                  _updateConfigSetting(setting.name, value);
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: setting.enabled
                  ? () async {
                      final result =
                          await file_picker.FilePicker.platform.pickFiles(
                        type: file_picker.FileType.custom,
                        allowedExtensions: ['ttf', 'otf'],
                      );
                      if (result != null && result.files.single.path != null) {
                        final filePath = result.files.single.path!;
                        // Get relative path if the font is within the project
                        if (projectManager.currentProject?.projectPath !=
                                null &&
                            filePath.startsWith(
                                projectManager.currentProject!.projectPath)) {
                          final relativePath = filePath.substring(projectManager
                              .currentProject!.projectPath.length);
                          _updateConfigSetting(setting.name, '"$relativePath"');
                        } else {
                          _updateConfigSetting(setting.name, '"$filePath"');
                        }
                      }
                    }
                  : null,
              child: const Text('Browse'),
            ),
          ],
        );
        break;

      case RenPySettingType.string:
      case RenPySettingType.number:
      case RenPySettingType.transition:
      case RenPySettingType.other:
      default:
        // Default to a text field with file picker for string and other types
        contentWidget = Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Enter value',
                  helperText: setting.comment,
                ),
                controller: TextEditingController(
                    text: setting.value.replaceAll('"', '')),
                enabled: setting.enabled,
                onChanged: (value) {
                  _updateConfigSetting(setting.name, value);
                },
              ),
            ),
            if (setting.enabled &&
                (setting.type == RenPySettingType.string ||
                    setting.type == RenPySettingType.transition))
              IconButton(
                icon: const Icon(Icons.attach_file),
                tooltip: 'Select file',
                onPressed: () async {
                  final result =
                      await file_picker.FilePicker.platform.pickFiles();
                  if (result != null && result.files.single.path != null) {
                    final filePath = result.files.single.path!;
                    // Get relative path if the file is within the project
                    if (projectManager.currentProject?.projectPath != null &&
                        filePath.startsWith(
                            projectManager.currentProject!.projectPath)) {
                      final relativePath = filePath.substring(
                          projectManager.currentProject!.projectPath.length);
                      _updateConfigSetting(
                          setting.name,
                          relativePath.startsWith('/')
                              ? relativePath.substring(1)
                              : relativePath);
                    } else {
                      _updateConfigSetting(setting.name, filePath);
                    }
                  }
                },
              ),
          ],
        );
        break;
    }

    // Common layout for all setting types
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(setting.name),
        ),
        Expanded(
          flex: 5,
          child: contentWidget,
        ),
        const SizedBox(width: 16),
        Switch(
          value: setting.enabled,
          onChanged: (value) {
            _toggleConfigSetting(setting.name, value);
          },
        ),
      ],
    );
  }

  /// Parse a color string to a Color object
  Color _parseColor(String colorStr) {
    if (colorStr.startsWith('#')) {
      colorStr = colorStr.substring(1);
      if (colorStr.length == 6) {
        return Color(int.parse('0xFF$colorStr'));
      } else if (colorStr.length == 8) {
        return Color(int.parse('0x$colorStr'));
      }
    }
    return Colors.grey;
  }

  /// Build a widget for editing a RenPy style
  Widget _buildStyleEditor(RenPyStyleSetting style) {
    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              style.styleName,
              style: style.enabled ? null : TextStyle(color: Colors.grey),
            ),
          ),
          Switch(
            value: style.enabled,
            onChanged: (value) {
              _toggleStyleSetting(style.styleName, value);
            },
          ),
        ],
      ),
      subtitle: style.isInherited && style.inheritsFrom != null
          ? Text('Inherits from: ${style.inheritsFrom}')
          : null,
      children: [
        ...style.properties.map(
          (property) => Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child:
                _buildStylePropertyEditor(property, styleName: style.styleName),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: style.enabled
                    ? () {
                        // Add a new property to the style
                        _showAddPropertyDialog(style.styleName);
                      }
                    : null,
                child: const Text('Add Property'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build a widget for editing a style property
  Widget _buildStylePropertyEditor(RenPyStylePropertySetting property,
      {required String styleName}) {
    // Content displayed in the middle section depends on the property type
    Widget contentWidget;

    switch (property.type) {
      case RenPySettingType.boolean:
        bool value = property.value == 'True';
        contentWidget = Row(
          children: [
            Switch(
              value: value,
              onChanged: property.enabled
                  ? (newValue) {
                      _updateStyleProperty(styleName, property.name,
                          newValue ? 'True' : 'False');
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            Text(value ? 'Enabled' : 'Disabled'),
          ],
        );
        break;

      case RenPySettingType.color:
        String colorValue = property.value;
        if (colorValue.startsWith('#')) {
          colorValue = colorValue.replaceAll('"', '').replaceAll("'", '');
        }
        contentWidget = Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _parseColor(colorValue),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Enter color (e.g. #ff0000)',
                ),
                controller: TextEditingController(text: colorValue),
                enabled: property.enabled,
                onChanged: (value) {
                  _updateStyleProperty(styleName, property.name, value);
                },
              ),
            ),
          ],
        );
        break;

      case RenPySettingType.font:
        contentWidget = Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Font path',
                ),
                controller: TextEditingController(
                    text: property.value.replaceAll('"', '')),
                enabled: property.enabled,
                onChanged: (value) {
                  _updateStyleProperty(styleName, property.name, value);
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: property.enabled
                  ? () async {
                      final result =
                          await file_picker.FilePicker.platform.pickFiles(
                        type: file_picker.FileType.custom,
                        allowedExtensions: ['ttf', 'otf'],
                      );
                      if (result != null && result.files.single.path != null) {
                        final filePath = result.files.single.path!;
                        // Get relative path if the font is within the project
                        if (projectManager.currentProject?.projectPath !=
                                null &&
                            filePath.startsWith(
                                projectManager.currentProject!.projectPath)) {
                          final relativePath = filePath.substring(projectManager
                              .currentProject!.projectPath.length);
                          _updateStyleProperty(
                              styleName, property.name, '"$relativePath"');
                        } else {
                          _updateStyleProperty(
                              styleName, property.name, '"$filePath"');
                        }
                      }
                    }
                  : null,
              child: const Text('Browse'),
            ),
          ],
        );
        break;

      case RenPySettingType.string:
      case RenPySettingType.number:
      case RenPySettingType.transition:
      case RenPySettingType.other:
      default:
        // Default to a text field for other types
        contentWidget = TextField(
          decoration: const InputDecoration(
            hintText: 'Enter value',
          ),
          controller: TextEditingController(text: property.value),
          enabled: property.enabled,
          onChanged: (value) {
            _updateStyleProperty(styleName, property.name, value);
          },
        );
        break;
    }

    // Common layout for all property types
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(property.name),
        ),
        Expanded(
          flex: 5,
          child: contentWidget,
        ),
        const SizedBox(width: 16),
        Switch(
          value: property.enabled,
          onChanged: (value) {
            _toggleStylePropertySetting(styleName, property.name, value);
          },
        ),
      ],
    );
  }

  /// Add a new property to a style
  void _addStyleProperty(
      String styleName, String propertyName, String propertyValue) {
    final styleIndex =
        _styleSettings.indexWhere((s) => s.styleName == styleName);
    if (styleIndex >= 0 &&
        propertyName.isNotEmpty &&
        propertyValue.isNotEmpty) {
      setState(() {
        // Check if the property already exists
        final existingPropertyIndex = _styleSettings[styleIndex]
            .properties
            .indexWhere((p) => p.name == propertyName);

        if (existingPropertyIndex >= 0) {
          // Update existing property
          final oldValue = _styleSettings[styleIndex]
              .properties[existingPropertyIndex]
              .value;
          _styleSettings[styleIndex].properties[existingPropertyIndex].value =
              propertyValue;

          // Record the change for undo/redo
          recordChange('stylePropertyValue', oldValue, propertyValue,
              id: '$styleName::$propertyName');
        } else {
          // Add new property
          _styleSettings[styleIndex].properties.add(
                RenPyStylePropertySetting(
                  name: propertyName,
                  value: propertyValue,
                  enabled: true,
                  originalLine: '    $propertyName $propertyValue',
                  type: _determinePropertyType(propertyName, propertyValue),
                ),
              );

          // Record the change for undo/redo
          recordChange(
              'addStyleProperty',
              null,
              {
                'name': propertyName,
                'value': propertyValue,
              },
              id: styleName);
        }
      });
    }
  }

  /// Show a dialog to add a new property to a style
  void _showAddPropertyDialog(String styleName) {
    final propertyNameController = TextEditingController();
    final propertyValueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Style Property'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: propertyNameController,
              decoration: const InputDecoration(
                labelText: 'Property Name',
                hintText: 'e.g. size, color, font',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: propertyValueController,
              decoration: const InputDecoration(
                labelText: 'Property Value',
                hintText: 'e.g. 24, #ff0000, "DejaVuSans.ttf"',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = propertyNameController.text.trim();
              final value = propertyValueController.text.trim();

              if (name.isNotEmpty && value.isNotEmpty) {
                _addStyleProperty(styleName, name, value);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Build the General Settings tab
  Widget _buildGeneralSettingsTab() {
    final generalSettings = _filteredConfigSettings
        .where((s) =>
            s.name.contains('config.name') ||
            s.name.contains('build.name') ||
            s.name.contains('config.version') ||
            s.name.contains('config.save_directory'))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsCard(
            'Game Information',
            generalSettings.map((setting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildSettingEditor(setting),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Build the Sound & Music tab
  Widget _buildSoundMusicTab() {
    final soundSettings = _filteredConfigSettings
        .where((s) =>
            s.name.contains('config.has_sound') ||
            s.name.contains('config.has_music') ||
            s.name.contains('config.has_voice') ||
            s.name.contains('config.main_menu_music') ||
            s.name.contains('config.sample_sound') ||
            s.name.contains('config.sample_voice') ||
            s.name.contains('volume'))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsCard(
            'Audio Settings',
            soundSettings.map((setting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildSettingEditor(setting),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Build the Transitions tab
  Widget _buildTransitionsTab() {
    final transitionSettings = _filteredConfigSettings
        .where((s) => s.name.contains('transition'))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsCard(
            'Transition Settings',
            transitionSettings.map((setting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildSettingEditor(setting),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Build the Text & Fonts tab
  Widget _buildTextFontsTab() {
    final fontSettings = _filteredConfigSettings
        .where((s) =>
            s.name.contains('font') ||
            s.name.contains('text_size') ||
            s.name.contains('language'))
        .toList();

    final textStyles = _filteredStyleSettings
        .where((s) => s.styleName.contains('text') || s.styleName == 'default')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsCard(
            'Font Settings',
            fontSettings.map((setting) {
              if (setting.type == RenPySettingType.font) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: _buildSettingEditor(setting),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: _buildSettingEditor(setting),
                );
              }
            }).toList(),
          ),
          const SizedBox(height: 16.0),
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Text Styles',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16.0),
                  ...textStyles.map((style) => _buildStyleEditor(style)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the Colors & Styles tab
  Widget _buildColorsStylesTab() {
    final colorSettings = _filteredConfigSettings
        .where((s) => s.type == RenPySettingType.color)
        .toList();

    final otherStyles = _filteredStyleSettings
        .where((s) => !s.styleName.contains('text') && s.styleName != 'default')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsCard(
            'Color Settings',
            colorSettings.map((setting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildSettingEditor(setting),
              );
            }).toList(),
          ),
          const SizedBox(height: 16.0),
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Other Styles',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16.0),
                  ...otherStyles.map((style) => _buildStyleEditor(style)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the Advanced tab with all settings
  Widget _buildAdvancedTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsCard(
            'All Configuration Settings',
            _filteredConfigSettings.map((setting) {
              switch (setting.type) {
                case RenPySettingType.boolean:
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildSettingEditor(setting),
                  );
                case RenPySettingType.color:
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildSettingEditor(setting),
                  );
                case RenPySettingType.font:
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildSettingEditor(setting),
                  );
                default:
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildSettingEditor(setting),
                  );
              }
            }).toList(),
          ),
          const SizedBox(height: 16.0),
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Styles',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16.0),
                  ..._filteredStyleSettings
                      .map((style) => _buildStyleEditor(style)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  List<Widget> buildAppBarActions() {
    return [
      if (currentFilePath != null) ...[
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
          onPressed: canUndo ? undo : null,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: 'Redo',
          onPressed: canRedo ? redo : null,
        ),
      ],
      IconButton(
        icon: const Icon(Icons.save),
        onPressed: isDirty ? saveFile : null,
        tooltip: 'Save File',
      ),
    ];
  }

  @override
  Widget buildEditorBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search Settings',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: _tabs,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildGeneralSettingsTab(),
              _buildSoundMusicTab(),
              _buildTransitionsTab(),
              _buildTextFontsTab(),
              _buildColorsStylesTab(),
              _buildAdvancedTab(),
            ],
          ),
        ),
      ],
    );
  }
}
