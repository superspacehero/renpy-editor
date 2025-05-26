import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/project_manager.dart';

/// Represents a Ren'Py project template
class RenPyTemplate {
  final String name;
  final String description;
  final String? imagePath;
  final String templatePath;

  RenPyTemplate({
    required this.name,
    required this.description,
    this.imagePath,
    required this.templatePath,
  });
}

/// A service class to manage Ren'Py project templates
class TemplateManagerService {
  static final TemplateManagerService _instance =
      TemplateManagerService._internal();

  // Built-in templates included with the editor
  final List<RenPyTemplate> _builtInTemplates = [];

  // Path to the templates directory
  late final String _templatesPath;

  factory TemplateManagerService() {
    return _instance;
  }

  TemplateManagerService._internal() {
    _initializeTemplatesPath();
    _loadBuiltInTemplates();
  }

  /// Initialize the path to the templates directory
  void _initializeTemplatesPath() {
    final homeDir =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir == null) {
      LogError('Could not determine home directory');
      _templatesPath = '';
      return;
    }

    // Use a templates directory inside the app's config directory
    final configDir = Platform.isWindows
        ? path.join(homeDir, 'AppData', 'Roaming', 'renpy_editor')
        : path.join(homeDir, '.config', 'renpy_editor');

    _templatesPath = path.join(configDir, 'templates');

    // Create the templates directory if it doesn't exist
    try {
      Directory(_templatesPath).createSync(recursive: true);
    } catch (e) {
      LogError('Error creating templates directory: $e');
    }
  }

  /// Load built-in templates
  void _loadBuiltInTemplates() {
    // Add basic templates
    _builtInTemplates.add(
      RenPyTemplate(
        name: 'Empty Project',
        description: 'A basic empty Ren\'Py project with minimal files.',
        templatePath: 'basic',
      ),
    );

    _builtInTemplates.add(
      RenPyTemplate(
        name: 'Visual Novel',
        description:
            'A standard visual novel template with sample characters and scenes.',
        templatePath: 'visual_novel',
      ),
    );

    _builtInTemplates.add(
      RenPyTemplate(
        name: 'Dating Sim',
        description:
            'A dating sim template with relationship tracking and multiple endings.',
        templatePath: 'dating_sim',
      ),
    );
  }

  /// Get the list of available templates
  List<RenPyTemplate> getAvailableTemplates() {
    return _builtInTemplates;
  }

  /// Create a new project from a template
  Future<RenPyProject?> createProjectFromTemplate({
    required String templateName,
    required String projectPath,
    required String projectName,
    Function(String errorMessage)? onError,
  }) async {
    try {
      // Find the template
      _builtInTemplates.firstWhere(
        (t) => t.name == templateName,
        orElse: () => throw Exception('Template not found: $templateName'),
      );

      // Create the project directory
      final projectDir = Directory(projectPath);
      if (await projectDir.exists()) {
        if (onError != null) {
          onError('Project directory already exists: $projectPath');
        }
        return null;
      }

      await projectDir.create(recursive: true);

      // For now, just create a basic Ren'Py project structure
      // In a real implementation, you would copy template files from a template directory

      // Create the game directory
      final gameDir = Directory(path.join(projectPath, 'game'));
      await gameDir.create();

      // Create options.rpy
      final optionsFile = File(path.join(gameDir.path, 'options.rpy'));
      await optionsFile.writeAsString('''
## This file contains options that can be changed to customize your game.

define config.name = "$projectName"
define config.version = "1.0.0"
define gui.about = _("")
define build.name = "${projectName.toLowerCase().replaceAll(' ', '_')}"
define config.has_sound = True
define config.has_music = True
define config.has_voice = True
define config.main_menu_music = "main_menu_theme.ogg"
define config.window_icon = "gui/window_icon.png"
''');

      // Create script.rpy
      final scriptFile = File(path.join(gameDir.path, 'script.rpy'));
      await scriptFile.writeAsString('''
## The script of the game.

# Declare characters used by this game.
define e = Character("Eileen")

# The game starts here.
label start:
    e "You've created a new Ren'Py game."
    e "Once you add a story, pictures, and music, you can release it to the world!"
    return
''');

      // Create screens.rpy (simplified version)
      final screensFile = File(path.join(gameDir.path, 'screens.rpy'));
      await screensFile.writeAsString('''
## Screens and menus for your game.

## Game menu screen
screen game_menu(title, scroll=None, yinitial=0.0):
    style_prefix "game_menu"
    
    frame:
        style "game_menu_outer_frame"
        
        hbox:
            frame:
                style "game_menu_navigation_frame"
            
            frame:
                style "game_menu_content_frame"
                
                if scroll == "viewport":
                    viewport:
                        scrollbars "vertical"
                        mousewheel True
                        draggable True
                        yinitial yinitial
                        
                        vbox:
                            transclude
                
                else:
                    transclude
''');

      // Create gui.rpy (simplified version)
      final guiFile = File(path.join(gameDir.path, 'gui.rpy'));
      await guiFile.writeAsString('''
## GUI configuration variables.

## Colors
define gui.accent_color = '#0099ff'
define gui.idle_color = '#888888'
define gui.idle_small_color = '#aaaaaa'
define gui.hover_color = '#0066ff'
define gui.selected_color = '#ffffff'
define gui.insensitive_color = '#8888887f'
define gui.text_color = '#ffffff'
define gui.interface_text_color = '#ffffff'
''');

      // Create a gui directory for images
      final guiDir = Directory(path.join(gameDir.path, 'gui'));
      await guiDir.create();

      // Open the newly created project
      final projectManager = ProjectManager();
      return await projectManager.openProject(
        initialDirectory: projectPath,
        onError: onError,
      );
    } catch (e) {
      LogError('Error creating project from template: $e');
      if (onError != null) {
        onError('Error creating project: $e');
      }
      return null;
    }
  }
}
