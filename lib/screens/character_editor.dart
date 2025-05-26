import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/screens/base_editor.dart';
import 'package:renpy_editor/project_manager.dart';

/// Represents a Ren'Py character definition
class RenpyCharacter {
  String id;
  String name;
  String nameVariable;
  String nameValue;
  String callback;
  String image;
  String whatFont;
  String whatColor;
  String whatSize;
  String kind;
  String sideImage;

  RenpyCharacter({
    required this.id,
    this.name = '',
    this.nameVariable = '',
    this.nameValue = '',
    this.callback = '',
    this.image = '',
    this.whatFont = '',
    this.whatColor = '',
    this.whatSize = '',
    this.kind = '',
    this.sideImage = '',
  });

  String get displayName {
    if (nameValue.isNotEmpty) {
      return nameValue;
    } else if (name.isNotEmpty) {
      return name.replaceAll('"', '').replaceAll('[', '').replaceAll(']', '');
    } else {
      return id;
    }
  }
}

/// A widget for creating and editing Ren'Py characters
class CharacterEditor extends RenpyEditorBase {
  const CharacterEditor({
    super.key,
    super.filePath,
    super.onSave,
    super.title = 'Character Editor',
  }) : super(
          icon: Icons.person,
          label: 'Characters',
        );

  @override
  State<CharacterEditor> createState() => _CharacterEditorState();
}

class _CharacterEditorState extends RenpyEditorBaseState<CharacterEditor> {
  final List<RenpyCharacter> _characters = [];
  RenpyCharacter? _selectedCharacter;
  RenPyProject? _currentProject;

  // Controllers
  final TextEditingController _fileNameController = TextEditingController();
  final TextEditingController _characterIdController = TextEditingController();
  final TextEditingController _characterNameController =
      TextEditingController();
  final TextEditingController _callbackController = TextEditingController();
  final TextEditingController _imageController = TextEditingController();
  final TextEditingController _whatFontController = TextEditingController();
  final TextEditingController _whatColorController = TextEditingController();
  final TextEditingController _whatSizeController = TextEditingController();
  final TextEditingController _kindController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fileNameController.text =
        path.basename(widget.filePath ?? 'characters.rpy');
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _characterIdController.dispose();
    _characterNameController.dispose();
    _callbackController.dispose();
    _imageController.dispose();
    _whatFontController.dispose();
    _whatColorController.dispose();
    _whatSizeController.dispose();
    _kindController.dispose();
    super.dispose();
  }

  @override
  void parseContent(String content) {
    setState(() {
      _characters.clear();
      _characters.addAll(_parseCharacters(content));
      Log('Parsed ${_characters.length} characters: ${_characters.map((c) => c.id).join(', ')}');
      if (_characters.isNotEmpty) {
        _selectCharacter(_characters.first);
      }
    });
  }

  @override
  String generateContent() {
    return _generateRenpyCode();
  }

  @override
  String generateDefaultFilePath() {
    // Use project directory if configured, otherwise use parent directory of any current file
    if (_currentProject != null && _currentProject!.gameDirPath.isNotEmpty) {
      return path.join(
          _currentProject!.gameDirPath, 'characters', _fileNameController.text);
    } else if (widget.filePath != null) {
      return path.join(
          path.dirname(widget.filePath!), _fileNameController.text);
    }
    // Default to just the filename if no context is available
    return _fileNameController.text;
  }

  @override
  void configureForProject(RenPyProject project) {
    // Store the project reference
    _currentProject = project;
  }

  @override
  Future<void> loadProjectSettings() async {
    // No specific project settings to load for character editor
  }

  @override
  void applyChange(Map<String, dynamic> change, bool isUndo) {
    // Implement undo/redo for character editor
    final value = isUndo ? change['oldValue'] : change['newValue'];

    switch (change['type']) {
      case 'addCharacter':
        if (isUndo) {
          // Remove the added character
          setState(() {
            _characters.removeWhere((c) => c.id == value['id']);
            if (_characters.isNotEmpty) {
              _selectCharacter(_characters.first);
            } else {
              _selectedCharacter = null;
            }
          });
        } else {
          // Add the character back
          final character = RenpyCharacter(
            id: value['id'],
            name: value['name'],
            nameVariable: value['nameVariable'],
            nameValue: value['nameValue'],
          );
          setState(() {
            _characters.add(character);
            _selectCharacter(character);
          });
        }
        break;

      case 'deleteCharacter':
        if (isUndo) {
          // Add the deleted character back
          final character = RenpyCharacter(
            id: value['id'],
            name: value['name'],
            nameVariable: value['nameVariable'],
            nameValue: value['nameValue'],
            callback: value['callback'],
            image: value['image'],
            whatFont: value['whatFont'],
            whatColor: value['whatColor'],
            whatSize: value['whatSize'],
            kind: value['kind'],
            sideImage: value['sideImage'],
          );
          setState(() {
            _characters.add(character);
            _selectCharacter(character);
          });
        } else {
          // Remove the character
          setState(() {
            _characters.removeWhere((c) => c.id == value['id']);
            if (_characters.isNotEmpty) {
              _selectCharacter(_characters.first);
            } else {
              _selectedCharacter = null;
            }
          });
        }
        break;

      case 'updateCharacter':
        final charIndex = _characters.indexWhere((c) => c.id == change['id']);
        if (charIndex >= 0) {
          setState(() {
            _characters[charIndex].id = value['id'];
            _characters[charIndex].name = value['name'];
            _characters[charIndex].nameVariable = value['nameVariable'];
            _characters[charIndex].nameValue = value['nameValue'];
            _characters[charIndex].callback = value['callback'];
            _characters[charIndex].image = value['image'];
            _characters[charIndex].whatFont = value['whatFont'];
            _characters[charIndex].whatColor = value['whatColor'];
            _characters[charIndex].whatSize = value['whatSize'];
            _characters[charIndex].kind = value['kind'];
            _characters[charIndex].sideImage = value['sideImage'];

            // If this is the selected character, update the UI
            if (_selectedCharacter == _characters[charIndex]) {
              _selectCharacter(_characters[charIndex]);
            }
          });
        }
        break;
    }
  }

  List<RenpyCharacter> _parseCharacters(String content) {
    // Parse Ren'Py character definitions
    final List<RenpyCharacter> characters = [];
    final Map<String, String> defaultVariables = {};
    final lines = content.split('\n');

    // First pass: collect all default variables
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip comments and empty lines
      if (line.isEmpty || line.startsWith('#')) continue;

      // Skip init python blocks (look for lines that are just "init python:" or start with indentation after it)
      if (line == 'init python:') {
        // Skip until we find a line that doesn't start with whitespace (end of init block)
        i++;
        while (i < lines.length) {
          final nextLine = lines[i];
          if (nextLine.trim().isEmpty ||
              nextLine.startsWith('    ') ||
              nextLine.startsWith('\t')) {
            i++;
            continue;
          }
          break;
        }
        i--; // Step back one since the for loop will increment
        continue;
      }

      // Parse default variable declarations
      if (line.startsWith('default ')) {
        final equalIndex = line.indexOf('=');
        if (equalIndex > 0) {
          final varName = line.substring('default '.length, equalIndex).trim();
          String varValue = line.substring(equalIndex + 1).trim();

          // Remove quotes and handle string formatting
          if (varValue.startsWith('"') && varValue.endsWith('"')) {
            varValue = varValue.substring(1, varValue.length - 1);
          } else if (varValue.startsWith("'") && varValue.endsWith("'")) {
            varValue = varValue.substring(1, varValue.length - 1);
          } else if (varValue.startsWith('f"') && varValue.endsWith('"')) {
            // Handle f-strings by removing the f prefix
            varValue = varValue.substring(2, varValue.length - 1);
            // For now, we'll keep the formatting but it won't be evaluated
          }

          defaultVariables[varName] = varValue;
        }
      }
    }

    // Second pass: parse character definitions
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip comments, empty lines, and init blocks
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line == 'init python:') {
        // Skip init python block
        i++;
        while (i < lines.length) {
          final nextLine = lines[i];
          if (nextLine.trim().isEmpty ||
              nextLine.startsWith('    ') ||
              nextLine.startsWith('\t')) {
            i++;
            continue;
          }
          break;
        }
        i--; // Step back one since the for loop will increment
        continue;
      }

      // Parse character definitions
      if (line.startsWith('define ')) {
        String fullDefinition = line;

        // Handle multi-line definitions
        int j = i + 1;
        while (j < lines.length) {
          final nextLine = lines[j].trim();
          if (nextLine.isEmpty || nextLine.startsWith('#')) {
            j++;
            continue;
          }
          // If the next line starts with whitespace or doesn't look like a new statement, it's part of this definition
          if (lines[j].startsWith('    ') ||
              lines[j].startsWith('\t') ||
              (!nextLine.startsWith('define ') &&
                  !nextLine.startsWith('default ') &&
                  !nextLine.startsWith('image ') &&
                  !nextLine.startsWith('init '))) {
            fullDefinition += ' $nextLine';
            j++;
          } else {
            break;
          }
        }
        i = j - 1; // Update the main loop counter

        final equalIndex = fullDefinition.indexOf('=', 'define '.length);
        if (equalIndex > 0) {
          final id =
              fullDefinition.substring('define '.length, equalIndex).trim();
          final definition = fullDefinition.substring(equalIndex + 1).trim();

          // Create character
          final character = RenpyCharacter(id: id);

          // Parse the character definition
          if (definition.startsWith('Character(')) {
            _parseCharacterDefinition(character, definition);
          } else if (definition.startsWith('DialogueCharacter(')) {
            _parseDialogueCharacterDefinition(character, definition);
          }

          // Look for matching default variables
          for (var entry in defaultVariables.entries) {
            final varName = entry.key;
            final varValue = entry.value;

            // Check if this character uses this variable in its name
            if (character.name.contains('[$varName]') ||
                character.name.contains(varName)) {
              character.nameVariable = varName;
              character.nameValue = varValue;
              break;
            }
          }

          characters.add(character);
        }
      }

      // Also parse image side definitions
      if (line.startsWith('image side ')) {
        final parts = line.substring('image side '.length).split('=');
        if (parts.length == 2) {
          final charId = parts[0].trim();
          String imagePath = parts[1].trim();
          if (imagePath.startsWith('"') && imagePath.endsWith('"')) {
            imagePath = imagePath.substring(1, imagePath.length - 1);
          }

          // Find the character and update its side image
          for (var char in characters) {
            if (char.id == charId) {
              char.sideImage = imagePath;
              break;
            }
          }
        }
      }
    }

    return characters;
  }

  void _parseCharacterDefinition(RenpyCharacter character, String definition) {
    // Remove the Character( and trailing )
    final paramsStr =
        definition.substring('Character('.length, definition.length - 1);
    _parseParams(character, paramsStr);
  }

  void _parseDialogueCharacterDefinition(
      RenpyCharacter character, String definition) {
    // Remove the DialogueCharacter( and trailing )
    final paramsStr = definition.substring(
        'DialogueCharacter('.length, definition.length - 1);
    _parseParams(character, paramsStr);
  }

  void _parseParams(RenpyCharacter character, String paramsStr) {
    // Split by comma but respect quotes and parentheses
    final params = _splitParams(paramsStr);

    for (var param in params) {
      param = param.trim();

      final keyValue = param.split('=');
      if (keyValue.length == 2) {
        final key = keyValue[0].trim();
        String value = keyValue[1].trim();

        switch (key) {
          case 'name':
            character.name = value;
            break;
          case 'callback':
            character.callback = value;
            break;
          case 'image':
            character.image = value.replaceAll('"', '').replaceAll("'", '');
            break;
          case 'what_font':
            character.whatFont = value.replaceAll('"', '').replaceAll("'", '');
            break;
          case 'what_color':
            character.whatColor = value.replaceAll('"', '').replaceAll("'", '');
            break;
          case 'what_size':
            character.whatSize = value;
            break;
          case 'kind':
            character.kind = value;
            break;
        }
      } else {
        // This is the positional name parameter
        character.name = param.trim();
      }
    }
  }

  List<String> _splitParams(String paramsStr) {
    final List<String> result = [];
    int depth = 0;
    bool inQuote = false;
    String? quoteChar;
    int start = 0;

    for (var i = 0; i < paramsStr.length; i++) {
      final char = paramsStr[i];

      if ((char == '"' || char == "'") &&
          (quoteChar == null || quoteChar == char)) {
        if (quoteChar == null) {
          quoteChar = char;
          inQuote = true;
        } else {
          quoteChar = null;
          inQuote = false;
        }
      } else if (char == '(' || char == '[' || char == '{') {
        if (!inQuote) depth++;
      } else if (char == ')' || char == ']' || char == '}') {
        if (!inQuote) depth--;
      } else if (char == ',' && depth == 0 && !inQuote) {
        result.add(paramsStr.substring(start, i));
        start = i + 1;
      }
    }

    // Add the last parameter
    if (start < paramsStr.length) {
      result.add(paramsStr.substring(start));
    }

    return result;
  }

  String _generateRenpyCode() {
    final buffer = StringBuffer();

    // Add header
    buffer.writeln('# This is how to declare characters used by this game.');
    buffer.writeln(
        '# The default keyword is used to set the default value of a variable.');

    // Add character declarations
    for (var character in _characters) {
      // Add default name variable if it exists
      if (character.nameVariable.isNotEmpty) {
        buffer.writeln(
            'default ${character.nameVariable} = "${character.nameValue}"');
      }

      // Add character definition
      buffer.write('define ${character.id} = ');

      // Determine if using Character or DialogueCharacter
      final useDialogueCharacter =
          character.callback.contains('dialogue_sound');

      if (useDialogueCharacter) {
        buffer.write('DialogueCharacter(');
      } else {
        buffer.write('Character(');
      }

      // Build parameters
      final List<String> params = [];

      // Add name parameter (positional or named)
      if (character.name.startsWith('[') && character.name.endsWith(']')) {
        params.add(character.name); // It's a variable reference
      } else if (character.name.contains('=')) {
        params.add('name=${character.name}'); // It's already a named parameter
      } else if (character.name.isNotEmpty) {
        params.add('"${character.name}"'); // It's a literal string
      }

      // Add callback if exists
      if (character.callback.isNotEmpty) {
        params.add('callback=${character.callback}');
      }

      // Add image if exists
      if (character.image.isNotEmpty) {
        params.add('image = "${character.image}"');
      }

      // Add what_font if exists
      if (character.whatFont.isNotEmpty) {
        params.add('what_font="${character.whatFont}"');
      }

      // Add what_color if exists
      if (character.whatColor.isNotEmpty) {
        params.add('what_color="${character.whatColor}"');
      }

      // Add what_size if exists
      if (character.whatSize.isNotEmpty) {
        params.add('what_size=${character.whatSize}');
      }

      // Add kind if exists
      if (character.kind.isNotEmpty) {
        params.add('kind=${character.kind}');
      }

      buffer.write(params.join(', '));
      buffer.writeln(')');

      // Add side image if exists
      if (character.sideImage.isNotEmpty) {
        buffer.writeln('image side ${character.id} = "${character.sideImage}"');
      }

      // Add a blank line between characters
      buffer.writeln();
    }

    return buffer.toString();
  }

  void _selectCharacter(RenpyCharacter character) {
    setState(() {
      _selectedCharacter = character;
      _characterIdController.text = character.id;
      _characterNameController.text = character.nameValue.isNotEmpty
          ? character.nameValue
          : character.name
              .replaceAll('[', '')
              .replaceAll(']', '')
              .replaceAll('"', '');
      _callbackController.text = character.callback;
      _imageController.text = character.image;
      _whatFontController.text = character.whatFont;
      _whatColorController.text = character.whatColor;
      _whatSizeController.text = character.whatSize;
      _kindController.text = character.kind;
    });
  }

  /// Helper function to add or update a character
  /// Returns the added or updated character
  RenpyCharacter _addCharacter({
    required String id,
    String name = '',
    String nameVariable = '',
    String nameValue = '',
    String callback = '',
    String image = '',
    String whatFont = '',
    String whatColor = '',
    String whatSize = '',
    String kind = '',
    String sideImage = '',
    bool selectAfterAdd = true,
    bool recordForUndo = true,
  }) {
    // Check if a character with this ID already exists
    int existingIndex = _characters.indexWhere((c) => c.id == id);

    RenpyCharacter character;
    if (existingIndex >= 0) {
      // Update existing character
      character = _characters[existingIndex];

      // Save the old state for undo if needed
      final oldState = {
        'id': character.id,
        'name': character.name,
        'nameVariable': character.nameVariable,
        'nameValue': character.nameValue,
        'callback': character.callback,
        'image': character.image,
        'whatFont': character.whatFont,
        'whatColor': character.whatColor,
        'whatSize': character.whatSize,
        'kind': character.kind,
        'sideImage': character.sideImage,
      };

      // Update properties
      character.name = name;
      character.nameVariable = nameVariable;
      character.nameValue = nameValue;
      character.callback = callback;
      character.image = image;
      character.whatFont = whatFont;
      character.whatColor = whatColor;
      character.whatSize = whatSize;
      character.kind = kind;
      character.sideImage = sideImage;

      if (recordForUndo) {
        // Record for undo/redo
        final newState = {
          'id': character.id,
          'name': character.name,
          'nameVariable': character.nameVariable,
          'nameValue': character.nameValue,
          'callback': character.callback,
          'image': character.image,
          'whatFont': character.whatFont,
          'whatColor': character.whatColor,
          'whatSize': character.whatSize,
          'kind': character.kind,
          'sideImage': character.sideImage,
        };

        recordChange(
          'updateCharacter',
          oldState,
          newState,
          id: oldState['id'],
        );
      }
    } else {
      // Create a new character
      character = RenpyCharacter(
        id: id,
        name: name,
        nameVariable: nameVariable,
        nameValue: nameValue,
        callback: callback,
        image: image,
        whatFont: whatFont,
        whatColor: whatColor,
        whatSize: whatSize,
        kind: kind,
        sideImage: sideImage,
      );

      setState(() {
        // Add to the list
        _characters.add(character);
      });

      if (recordForUndo) {
        // Record for undo/redo
        recordChange(
          'addCharacter',
          null,
          {
            'id': character.id,
            'name': character.name,
            'nameVariable': character.nameVariable,
            'nameValue': character.nameValue,
            'callback': character.callback,
            'image': character.image,
            'whatFont': character.whatFont,
            'whatColor': character.whatColor,
            'whatSize': character.whatSize,
            'kind': character.kind,
            'sideImage': character.sideImage,
          },
        );
      }
    }

    // Select the character if requested
    if (selectAfterAdd) {
      _selectCharacter(character);
    }

    return character;
  }

  void _addNewCharacter() {
    _addCharacter(
      id: 'new_character',
      nameVariable: 'new_character_name',
      nameValue: 'New Character',
    );
  }

  void _deleteCharacter() {
    if (_selectedCharacter != null) {
      final oldChar = _selectedCharacter!;

      // Record the change for undo/redo
      recordChange(
        'deleteCharacter',
        {
          'id': oldChar.id,
          'name': oldChar.name,
          'nameVariable': oldChar.nameVariable,
          'nameValue': oldChar.nameValue,
          'callback': oldChar.callback,
          'image': oldChar.image,
          'whatFont': oldChar.whatFont,
          'whatColor': oldChar.whatColor,
          'whatSize': oldChar.whatSize,
          'kind': oldChar.kind,
          'sideImage': oldChar.sideImage,
        },
        null,
      );

      setState(() {
        _characters.remove(_selectedCharacter);
        if (_characters.isNotEmpty) {
          _selectCharacter(_characters.first);
        } else {
          _selectedCharacter = null;
          _characterIdController.clear();
          _characterNameController.clear();
          _callbackController.clear();
          _imageController.clear();
          _whatFontController.clear();
          _whatColorController.clear();
          _whatSizeController.clear();
          _kindController.clear();
        }
      });
    }
  }

  void _updateCharacter() {
    if (_selectedCharacter != null) {
      // Save the old state for undo
      final oldState = {
        'id': _selectedCharacter!.id,
        'name': _selectedCharacter!.name,
        'nameVariable': _selectedCharacter!.nameVariable,
        'nameValue': _selectedCharacter!.nameValue,
        'callback': _selectedCharacter!.callback,
        'image': _selectedCharacter!.image,
        'whatFont': _selectedCharacter!.whatFont,
        'whatColor': _selectedCharacter!.whatColor,
        'whatSize': _selectedCharacter!.whatSize,
        'kind': _selectedCharacter!.kind,
        'sideImage': _selectedCharacter!.sideImage,
      };

      // Create name based on whether we're using a variable or direct string
      String name;
      if (_selectedCharacter!.nameVariable.isNotEmpty) {
        name = '[${_selectedCharacter!.nameVariable}]';
      } else {
        name = '"${_characterNameController.text}"';
      }

      // Use the helper function to update the character
      _addCharacter(
        id: _characterIdController.text,
        name: name,
        nameVariable: _selectedCharacter!.nameVariable,
        nameValue: _characterNameController.text,
        callback: _callbackController.text,
        image: _imageController.text,
        whatFont: _whatFontController.text,
        whatColor: _whatColorController.text,
        whatSize: _whatSizeController.text,
        kind: _kindController.text,
        sideImage: _selectedCharacter!.sideImage,
        recordForUndo: false, // We're handling undo recording manually
      );

      // Save the new state for redo
      final newState = {
        'id': _selectedCharacter!.id,
        'name': _selectedCharacter!.name,
        'nameVariable': _selectedCharacter!.nameVariable,
        'nameValue': _selectedCharacter!.nameValue,
        'callback': _selectedCharacter!.callback,
        'image': _selectedCharacter!.image,
        'whatFont': _selectedCharacter!.whatFont,
        'whatColor': _selectedCharacter!.whatColor,
        'whatSize': _selectedCharacter!.whatSize,
        'kind': _selectedCharacter!.kind,
        'sideImage': _selectedCharacter!.sideImage,
      };

      // Record the change for undo/redo
      recordChange(
        'updateCharacter',
        oldState,
        newState,
        id: oldState['id'],
      );
    }
  }

  String _generateCharacterCode(RenpyCharacter character) {
    final buffer = StringBuffer();

    // Add default name variable if it exists
    if (character.nameVariable.isNotEmpty) {
      buffer.writeln(
          'default ${character.nameVariable} = "${character.nameValue}"');
    }

    // Add character definition
    buffer.write('define ${character.id} = ');

    // Determine if using Character or DialogueCharacter
    final useDialogueCharacter = character.callback.contains('dialogue_sound');

    if (useDialogueCharacter) {
      buffer.write('DialogueCharacter(');
    } else {
      buffer.write('Character(');
    }

    // Build parameters
    final List<String> params = [];

    // Add name parameter (positional or named)
    if (character.name.startsWith('[') && character.name.endsWith(']')) {
      params.add(character.name); // It's a variable reference
    } else if (character.name.contains('=')) {
      params.add(character.name); // It's already a named parameter
    } else if (character.name.isNotEmpty) {
      params.add(character.name); // It's a literal string
    }

    // Add callback if exists
    if (character.callback.isNotEmpty) {
      params.add('callback=${character.callback}');
    }

    // Add image if exists
    if (character.image.isNotEmpty) {
      params.add('image = "${character.image}"');
    }

    // Add what_font if exists
    if (character.whatFont.isNotEmpty) {
      params.add('what_font="${character.whatFont}"');
    }

    // Add what_color if exists
    if (character.whatColor.isNotEmpty) {
      params.add('what_color="${character.whatColor}"');
    }

    // Add what_size if exists
    if (character.whatSize.isNotEmpty) {
      params.add('what_size=${character.whatSize}');
    }

    // Add kind if exists
    if (character.kind.isNotEmpty) {
      params.add('kind=${character.kind}');
    }

    buffer.write(params.join(', '));
    buffer.writeln(')');

    // Add side image if exists
    if (character.sideImage.isNotEmpty) {
      buffer.writeln('image side ${character.id} = "${character.sideImage}"');
    }

    return buffer.toString();
  }

  @override
  Widget buildEditorBody() {
    return Row(
      children: [
        // Character list sidebar
        SizedBox(
          width: 250,
          child: Card(
            margin: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Characters',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _addNewCharacter,
                        tooltip: 'Add New Character',
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _characters.length,
                    itemBuilder: (context, index) {
                      final character = _characters[index];
                      return ListTile(
                        title: Text(character.displayName),
                        subtitle: Text(character.id),
                        selected: _selectedCharacter == character,
                        onTap: () => _selectCharacter(character),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Character editor main area
        Expanded(
          child: _selectedCharacter == null
              ? const Center(
                  child: Text('Select a character or create a new one'),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Editing ${_selectedCharacter!.displayName}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _deleteCharacter,
                            tooltip: 'Delete Character',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Basic character info
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Basic Information',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _characterIdController,
                                      decoration: const InputDecoration(
                                        labelText: 'Character ID',
                                        hintText: 'e.g., eileen, narrator',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _characterNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Display Name',
                                        hintText: 'e.g., Eileen, Narrator',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _callbackController,
                                      decoration: const InputDecoration(
                                        labelText: 'Callback',
                                        hintText:
                                            'e.g., dialogue_sound("character")',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _kindController,
                                      decoration: const InputDecoration(
                                        labelText: 'Kind',
                                        hintText:
                                            'Base character (e.g., eileen)',
                                        border: OutlineInputBorder(),
                                        helperText:
                                            'Used for character variants',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Appearance
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Appearance',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _imageController,
                                decoration: const InputDecoration(
                                  labelText: 'Character Image',
                                  hintText: 'e.g., eileen, fragment',
                                  border: OutlineInputBorder(),
                                  helperText: 'Used for dialogue portraits',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _whatFontController,
                                      decoration: const InputDecoration(
                                        labelText: 'Text Font',
                                        hintText: 'e.g., gui/fonts/Font.ttf',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _whatColorController,
                                      decoration: const InputDecoration(
                                        labelText: 'Text Color',
                                        hintText: 'e.g., #FF0000',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _whatSizeController,
                                decoration: const InputDecoration(
                                  labelText: 'Text Size',
                                  hintText: 'e.g., 24',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Update button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _updateCharacter,
                          child: const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Update Character'),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Preview section
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preview Code',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  _generateCharacterCode(_selectedCharacter!),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
