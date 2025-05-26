import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:renpy_editor/project_manager.dart';

/// Base class for Ren'Py editors
abstract class RenpyEditorBase extends StatefulWidget {
  final String? filePath;
  final Function(String)? onSave;
  final String title;
  final IconData icon;
  final String label;

  const RenpyEditorBase({
    super.key,
    this.filePath,
    this.onSave,
    required this.title,
    required this.icon,
    required this.label,
  });
}

/// Base state class for Ren'Py editors
abstract class RenpyEditorBaseState<T extends RenpyEditorBase> extends State<T>
    with AutomaticKeepAliveClientMixin {
  String? _currentFilePath;
  bool _isDirty = false;
  bool _isLoading = false;

  // Use the shared singleton ProjectManager instance
  ProjectManager get projectManager => ProjectManager();

  // Stream subscription for project changes
  StreamSubscription<RenPyProject?>? _projectChangeSubscription;

  // Whether the editor requires a project to be opened
  bool requireProject = true;

  // History stacks for undo/redo
  final List<Map<String, dynamic>> _undoStack = [];
  final List<Map<String, dynamic>> _redoStack = [];

  // Keep this widget alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  // Getters for protected access from subclasses
  String? get currentFilePath => _currentFilePath;
  bool get isDirty => _isDirty;
  bool get isLoading => _isLoading;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.filePath;
    if (_currentFilePath != null) {
      _loadFile(_currentFilePath!);
    }

    // Listen for project changes
    _projectChangeSubscription =
        projectManager.projectChanges.listen((project) {
      if (mounted) {
        setState(() {
          onProjectChanged(project);
        });
      }
    });
  }

  @override
  void dispose() {
    _projectChangeSubscription?.cancel();
    super.dispose();
  }

  /// Called when the project changes (opened/closed)
  /// Subclasses can override this to react to project changes
  void onProjectChanged(RenPyProject? project) {
    // Default implementation - subclasses can override
  }

  /// Load a file content
  Future<void> _loadFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        parseContent(content);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
      }
    }
  }

  /// Save the file
  Future<void> saveFile() async {
    if (!_isDirty) return;

    final shouldSave = await _showSaveConfirmationDialog();
    if (!shouldSave) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final content = generateContent();
      final filePath = _currentFilePath ?? generateDefaultFilePath();

      await File(filePath).writeAsString(content);

      setState(() {
        _isDirty = false;
        _currentFilePath = filePath;
      });

      if (widget.onSave != null) {
        widget.onSave!(content);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Open a Ren'Py project directory
  Future<void> openProject() async {
    await projectManager.openProject();

    if (projectManager.currentProject != null) {
      setState(() {
        configureForProject(projectManager.currentProject!);
        _isLoading = true;
      });

      await loadProjectSettings();

      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Open a recent Ren'Py project from the path
  Future<void> openRecentProject(String projectPath) async {
    final result = await projectManager.openRecentProject(projectPath,
        onError: (errorMessage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    });

    if (result != null) {
      setState(() {
        configureForProject(result);
        _isLoading = true;
      });

      await loadProjectSettings();

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Project opened: ${result.projectPath}'),
          ),
        );
      }
    }
  }

  /// Show a confirmation dialog before saving changes
  Future<bool> _showSaveConfirmationDialog() async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Changes'),
        content: const Text(
            'Are you sure you want to save changes to the Ren\'Py file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Show an error dialog with the specified message
  void showErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Record a change for undo/redo
  void recordChange(String type, dynamic oldValue, dynamic newValue,
      {String? id}) {
    // Add to undo stack
    _undoStack.add({
      'type': type,
      'oldValue': oldValue,
      'newValue': newValue,
      'id': id,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });

    // Clear redo stack when a new change is made
    _redoStack.clear();

    // Mark as dirty
    setState(() {
      _isDirty = true;
    });
  }

  /// Undo the last change
  void undo() {
    if (_undoStack.isEmpty) return;

    final change = _undoStack.removeLast();
    _redoStack.add(change);

    applyChange(change, true);
  }

  /// Redo the last undone change
  void redo() {
    if (_redoStack.isEmpty) return;

    final change = _redoStack.removeLast();
    _undoStack.add(change);

    applyChange(change, false);
  }

  // Abstract methods that subclasses must implement

  /// Parse content from the loaded file
  void parseContent(String content);

  /// Generate content to be saved to file
  String generateContent();

  /// Generate a default file path when saving a new file
  String generateDefaultFilePath();

  /// Configure the editor for a specific project
  void configureForProject(RenPyProject project);

  /// Load settings from project files
  Future<void> loadProjectSettings();

  /// Apply a change for undo/redo
  void applyChange(Map<String, dynamic> change, bool isUndo);

  /// Build a common settings card for a group of related settings
  Widget buildSettingsCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16.0),
            ...children,
          ],
        ),
      ),
    );
  }

  /// A project menu that can be reused across the UI
  Widget projectMenu({String? buttonText}) {
    // When buttonText is provided, create a button with text and icon
    return PopupMenuButton<String>(
      tooltip: 'Project Options',
      onSelected: _handleProjectMenuSelection,
      itemBuilder: _buildProjectMenuItems,
      child: buttonText != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder,
                      color: Theme.of(context).colorScheme.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    buttonText,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ],
              ),
            )
          : const Icon(Icons.folder),
    );
  }

  /// Handle selection from the project menu
  Future<void> _handleProjectMenuSelection(String value) async {
    if (value == 'open') {
      await openProject();
    } else if (value == 'new') {
      await _createNewProjectFromTemplate();
    } else if (value == 'close') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project closed')),
      );
      setState(() {
        projectManager.closeProject();
      });
    } else if (value.startsWith('recent:')) {
      final path = value.substring('recent:'.length);
      await openRecentProject(path);
    }
  }

  /// Create a new project from template
  Future<void> _createNewProjectFromTemplate() async {
    if (!mounted) return;

    final templates = ['Default', 'Visual Novel', 'Dating Sim', 'RPG'];
    final selectedTemplate = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project from Template'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose a template:'),
              const SizedBox(height: 16),
              ...templates.map(
                (template) => ListTile(
                  title: Text(template),
                  leading: const Icon(Icons.description),
                  onTap: () => Navigator.pop(context, template),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedTemplate == null || !mounted) return;

    // Show directory picker dialog
    final projectPath = await projectManager.selectDirectory(
      title: 'Select Project Location',
      context: context,
    );

    if (projectPath == null || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Create project directory structure and files based on template
      final success = await projectManager.createProjectFromTemplate(
        projectPath: projectPath,
        templateName: selectedTemplate,
      );

      if (!mounted) return;

      if (success) {
        // Open the newly created project
        await openRecentProject(projectPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Project created from $selectedTemplate template'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create project'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating project: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Build the menu items for the project menu
  List<PopupMenuEntry<String>> _buildProjectMenuItems(BuildContext context) {
    final List<PopupMenuEntry<String>> items = [
      const PopupMenuItem(
        value: 'new',
        child: Row(
          children: [
            Icon(Icons.create_new_folder),
            SizedBox(width: 8),
            Text('New Project...'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'open',
        child: Row(
          children: [
            Icon(Icons.folder_open),
            SizedBox(width: 8),
            Text('Open Project...'),
          ],
        ),
      ),
    ];

    // Add recent projects submenu if there are any
    if (projectManager.recentProjects.isNotEmpty) {
      items.add(
        const PopupMenuDivider(),
      );
      items.add(
        const PopupMenuItem(
          enabled: false,
          child: Text('Recent Projects',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );

      // Add recent projects (limited to 5 for menu brevity)
      for (final path in projectManager.recentProjects.take(5)) {
        items.add(
          PopupMenuItem(
            value: 'recent:$path',
            child: Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    path.split(Platform.pathSeparator).last,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Add close project if one is open
    if (projectManager.hasOpenProject()) {
      items.add(
        const PopupMenuDivider(),
      );
      items.add(
        const PopupMenuItem(
          value: 'close',
          child: Row(
            children: [
              Icon(Icons.close),
              SizedBox(width: 8),
              Text('Close Project'),
            ],
          ),
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final projectName = projectManager.currentProject != null
        ? path.basename(projectManager.currentProject!.projectPath)
        : 'No project open';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                projectName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            // Project menu
            projectMenu(),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          ...buildAppBarActions(),
        ],
        flexibleSpace: SafeArea(
          child: Align(
            alignment: Alignment.center,
            child: Text(
              _currentFilePath != null
                  ? 'Edit ${path.basename(_currentFilePath!)}'
                  : widget.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main content
                Expanded(
                  child: (currentFilePath == null &&
                          requireProject &&
                          projectManager.currentProject == null)
                      ? noProjectBody()
                      : buildEditorBody(),
                ),
              ],
            ),
    );
  }

  /// Build actions for the app bar
  List<Widget> buildAppBarActions() {
    return [
      if (_currentFilePath != null) ...[
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
          onPressed: _undoStack.isEmpty ? null : undo,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: 'Redo',
          onPressed: _redoStack.isEmpty ? null : redo,
        ),
      ],
      IconButton(
        icon: const Icon(Icons.save),
        onPressed: _isDirty ? saveFile : null,
        tooltip: 'Save File',
      ),
    ];
  }

  /// Build the editor body
  Widget buildEditorBody();

  /// A widget to display when no project is opened
  Widget noProjectBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('No Ren\'Py project loaded.'),
          const SizedBox(height: 16.0),
          projectMenu(buttonText: "Projects"), // Use the same project menu here
        ],
      ),
    );
  }
}
