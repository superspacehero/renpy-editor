import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/models/renpy_package.dart';

/// Represents a Ren'Py template that can be downloaded and used
class RenPyTemplate {
  final String name;
  final String description;
  final String url;
  final String author;
  final String thumbnailUrl;
  final bool isZip;

  RenPyTemplate({
    required this.name,
    required this.description,
    required this.url,
    required this.author,
    this.thumbnailUrl = '',
    this.isZip = true,
  });
}

/// Represents a Ren'Py project
class RenPyProject {
  String projectPath;
  late String gameDirPath;
  List<String> gameFiles = [];
  List<RenPyPackage> installedPackages = [];
  bool isValid = false;

  RenPyProject({required this.projectPath}) {
    gameDirPath = path.join(projectPath, 'game');
  }

  /// Check if the project is a valid Ren'Py project
  Future<bool> validate() async {
    try {
      final gameDir = Directory(gameDirPath);

      // Check if game directory exists
      if (!await gameDir.exists()) {
        return false;
      }

      // Check if essential Ren'Py files exist
      final optionsFile = File(path.join(gameDirPath, 'options.rpy'));
      if (!await optionsFile.exists()) {
        return false;
      }

      // Project is valid
      isValid = true;
      return true;
    } catch (e) {
      LogError('Error validating Ren\'Py project: $e');
      return false;
    }
  }

  /// Load the project files
  Future<void> loadProjectFiles() async {
    if (!isValid) {
      await validate();
    }

    if (!isValid) {
      throw Exception('Cannot load files for an invalid project');
    }

    try {
      final gameDir = Directory(gameDirPath);
      gameFiles = [];

      await for (final entity in gameDir.list(recursive: true)) {
        if (entity is File) {
          gameFiles.add(path.relative(entity.path, from: gameDirPath));
        }
      }

      // Load installed packages information if it exists
      await loadInstalledPackages();
    } catch (e) {
      LogError('Error loading project files: $e');
    }
  }

  /// Load the installed packages information
  Future<void> loadInstalledPackages() async {
    try {
      final packagesFile = File(path.join(gameDirPath, 'packages.json'));
      if (await packagesFile.exists()) {
        final content = await packagesFile.readAsString();
        final List<dynamic> packagesJson = await json.decode(content);
        installedPackages = packagesJson
            .map((packageJson) => RenPyPackage.fromJson(packageJson))
            .toList();
      } else {
        installedPackages = [];
      }
    } catch (e) {
      LogError('Error loading installed packages: $e');
      installedPackages = [];
    }
  }
}

/// Global project manager for the application
class ProjectManager {
  static final ProjectManager _instance = ProjectManager._internal();
  RenPyProject? currentProject;

  // Store a list of recent projects (paths)
  final List<String> _recentProjects = [];

  // Maximum number of recent projects to remember
  static const int maxRecentProjects = 10;

  // File to store recent projects
  late final String _recentProjectsFilePath;

  // Stream controller for project changes
  final StreamController<RenPyProject?> _projectChangeController =
      StreamController<RenPyProject?>.broadcast();

  // Stream for listening to project changes
  Stream<RenPyProject?> get projectChanges => _projectChangeController.stream;

  factory ProjectManager() {
    return _instance;
  }

  ProjectManager._internal() {
    // Initialize the path for storing recent projects
    _recentProjectsFilePath = _getRecentProjectsFilePath();
    _loadRecentProjects();
  }

  /// Dispose resources (call this when app is closing)
  void dispose() {
    _projectChangeController.close();
  }

  /// Get the path to the recent projects file
  String _getRecentProjectsFilePath() {
    final homeDir =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (homeDir == null) {
      LogError('Could not determine home directory');
      return '';
    }

    // On Linux/Mac, use ~/.config/renpy-editor
    // On Windows, use %APPDATA%\renpy_editor
    final configDir = Platform.isWindows
        ? path.join(homeDir, 'AppData', 'Roaming', 'renpy_editor')
        : path.join(homeDir, '.config', 'renpy_editor');

    // Create directory if it doesn't exist
    Directory(configDir).createSync(recursive: true);

    return path.join(configDir, 'recent_projects.json');
  }

  /// Load the list of recent projects from file
  Future<void> _loadRecentProjects() async {
    try {
      final file = File(_recentProjectsFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> projects = json.decode(content);
        _recentProjects.clear();
        _recentProjects.addAll(projects.cast<String>());
      }
    } catch (e) {
      LogError('Error loading recent projects: $e');
    }
  }

  /// Save the list of recent projects to file
  Future<void> _saveRecentProjects() async {
    try {
      final file = File(_recentProjectsFilePath);
      await file.writeAsString(json.encode(_recentProjects));
    } catch (e) {
      LogError('Error saving recent projects: $e');
    }
  }

  /// Add a project to the recent projects list
  void _addToRecentProjects(String projectPath) {
    // Remove if already exists (to move it to the top)
    _recentProjects.remove(projectPath);

    // Add to the beginning of the list
    _recentProjects.insert(0, projectPath);

    // Trim list if needed
    if (_recentProjects.length > maxRecentProjects) {
      _recentProjects.removeRange(maxRecentProjects, _recentProjects.length);
    }

    // Save the updated list
    _saveRecentProjects();
  }

  /// Get the list of recent projects
  List<String> get recentProjects => List.unmodifiable(_recentProjects);

  /// Open a Ren'Py project
  Future<RenPyProject?> openProject({
    String? initialDirectory,
    String dialogTitle = 'Select Ren\'Py Project Directory',
    Function(String errorMessage)? onError,
  }) async {
    String? selectedDirectory = initialDirectory;

    selectedDirectory ??=
        await file_picker.FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
    );

    if (selectedDirectory != null) {
      final project = RenPyProject(projectPath: selectedDirectory);
      final isValid = await project.validate();

      if (!isValid) {
        if (onError != null) {
          onError(
              'Invalid Ren\'Py project. Make sure the "game" directory exists.');
        }
        return null;
      }

      await project.loadProjectFiles();
      currentProject = project;

      // Notify listeners about project change
      _projectChangeController.add(project);

      // Add to recent projects
      _addToRecentProjects(selectedDirectory);

      return project;
    }

    return null;
  }

  /// Open a recent project by its path
  Future<RenPyProject?> openRecentProject(
    String projectPath, {
    Function(String errorMessage)? onError,
  }) async {
    // Check if the directory still exists
    if (!await Directory(projectPath).exists()) {
      // Remove from recent projects if it doesn't exist
      _recentProjects.remove(projectPath);
      _saveRecentProjects();

      if (onError != null) {
        onError('Project directory no longer exists: $projectPath');
      }
      return null;
    }

    // Use the existing openProject method with the path
    return openProject(
      initialDirectory: projectPath,
      onError: onError,
    );
  }

  /// Close the current project
  void closeProject() {
    currentProject = null;
    // Notify listeners about project closure
    _projectChangeController.add(null);
  }

  /// Get the current project
  RenPyProject? getCurrentProject() {
    return currentProject;
  }

  /// Check if a project is currently open
  bool hasOpenProject() {
    return currentProject != null;
  }

  /// Select a directory using a file picker dialog
  Future<String?> selectDirectory(
      {required BuildContext context, String? title}) async {
    // Implementation using a file picker package
    // For example with file_picker package:
    // final result = await FilePicker.platform.getDirectoryPath(
    //   dialogTitle: title,
    // );
    // return result;

    // Temporary implementation - you'll need to add a file picker package
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title ?? 'Select Directory'),
        content: const Text(
            'Directory selection dialog would appear here.\nImplement with a file picker package.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, '/home/user/new_project'),
            child: const Text('Mock Select'),
          ),
        ],
      ),
    );
  }

  /// Get the list of available Ren'Py templates
  static List<RenPyTemplate> getAvailableTemplates() {
    return [
      RenPyTemplate(
        name: 'Default',
        description: 'The basic Ren\'Py template with minimal styling',
        url: 'default',
        author: 'Ren\'Py',
        isZip: false,
      ),
      RenPyTemplate(
        name: 'Tofu Rocks GUI Template',
        description: 'A modern and stylish GUI template for Ren\'Py games',
        url: 'https://tofurocks.itch.io/renpy-gui-template/download',
        author: 'Tofu Rocks',
        thumbnailUrl:
            'https://img.itch.zone/aW1nLzM0NTExNzgucG5n/original/DmGHLX.png',
      ),
      RenPyTemplate(
        name: 'Material Design Template',
        description: 'A template with Material Design-inspired UI elements',
        url: 'https://example.com/material-template.zip',
        author: 'RenPy Community',
      ),
      RenPyTemplate(
        name: 'Visual Novel Template',
        description: 'A complete template for traditional visual novels',
        url: 'https://example.com/vn-template.zip',
        author: 'RenPy Community',
      ),
    ];
  }

  /// Create a project from a template
  Future<bool> createProjectFromTemplate({
    required String projectPath,
    required String templateName,
    String? templateUrl,
  }) async {
    try {
      // Create the project directory
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        await projectDir.create(recursive: true);
      }

      // If template URL is provided, download and extract it
      if (templateUrl != null && templateUrl != 'default') {
        final success =
            await downloadAndExtractTemplate(templateUrl, projectPath);
        if (success) {
          Log('Successfully created project from template: $templateName');
          return true;
        }
      }

      // If no template URL or download failed, create basic project structure
      final gameDir = Directory('$projectPath/game');
      if (!await gameDir.exists()) {
        await gameDir.create();
      }

      // Create a basic script.rpy file
      final scriptFile = File('$projectPath/game/script.rpy');
      await scriptFile
          .writeAsString("# The script of the game goes in this file.");
      Log('Created basic Ren\'Py project at: $projectPath');
      return true;
    } catch (e) {
      LogError('Error creating project from template: $e');
      return false;
    }
  }

  /// Download and extract a template from a URL
  Future<bool> downloadAndExtractTemplate(
      String url, String projectPath) async {
    try {
      Log('Downloading template from: $url');

      // Create a temporary file to store the downloaded zip
      final tempDir = await Directory.systemTemp.createTemp('renpy_template_');
      final zipFilePath = path.join(tempDir.path, 'template.zip');
      final zipFile = File(zipFilePath);

      // Download the file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        LogError('Failed to download template: HTTP ${response.statusCode}');
        return false;
      }

      // Save the downloaded content to the temp file
      await zipFile.writeAsBytes(response.bodyBytes);

      // Read the zip file
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Extract the contents to the project directory
      for (final file in archive) {
        final filename = file.name;

        // Skip directories in the archive
        if (file.isFile) {
          final outFile = File(path.join(projectPath, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(path.join(projectPath, filename))
              .create(recursive: true);
        }
      }

      // Clean up the temporary directory
      await tempDir.delete(recursive: true);

      Log('Template extracted successfully');
      return true;
    } catch (e) {
      LogError('Error downloading or extracting template: $e');
      return false;
    }
  }
}
