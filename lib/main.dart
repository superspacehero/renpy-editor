import 'package:flutter/material.dart';

import 'package:flutter_gruvbox_theme/flutter_gruvbox_theme.dart';

import 'package:renpy_editor/constants.dart';
import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/project_manager.dart';
import 'package:renpy_editor/screens/base_editor.dart';
import 'package:renpy_editor/screens/renpy_script_editor.dart';
import 'package:renpy_editor/screens/settings_editor.dart';
import 'package:renpy_editor/screens/character_editor.dart';
import 'package:renpy_editor/screens/package_manager.dart';

// Store command line arguments globally
List<String> commandLineArgs = [];

void main(List<String> args) {
  // Handle command line arguments
  handleCommandLineArgs(args);

  runApp(const Editor());
}

/// Handle command line arguments
/// Formats supported:
/// 1. Direct path: /path/to/project
/// 2. Named parameter: --project=/path/to/project
void handleCommandLineArgs(List<String> args) async {
  try {
    String? projectPath;

    // Check for project path argument
    for (final arg in args) {
      // Check for --project= format
      if (arg.startsWith('--project=')) {
        projectPath = arg.substring('--project='.length);
        break;
      }
      // Otherwise, treat the argument as a direct path
      else if (arg.isNotEmpty && !arg.startsWith('--')) {
        projectPath = arg;
        break;
      }
    }

    if (projectPath != null && projectPath.isNotEmpty) {
      LogError('Opening project from command line: $projectPath');
      // Try to open the project
      final projectManager = ProjectManager();
      await projectManager.openProject(
        initialDirectory: projectPath,
        onError: (errorMessage) {
          LogError('Failed to open project: $errorMessage');
        },
      );
    }
  } catch (e) {
    LogError('Error handling command line arguments: $e');
  }
}

class Editor extends StatelessWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appDisplayName,
      theme: GruvboxTheme.light(),
      darkTheme: GruvboxTheme.dark(),
      themeMode: ThemeMode.system,
      home: const MainNavigator(),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;

  // Create editors with keys to preserve state
  late final List<Widget> _pages = [
    const ScriptEditor(key: ValueKey('script_editor')),
    const CharacterEditor(key: ValueKey('character_editor')),
    const SettingsEditor(key: ValueKey('settings_editor')),
    const PackageManager(key: ValueKey('package_manager')),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _pages.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabBarView(
        controller: _tabController,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: _pages.map((page) {
          final editorPage = page as RenpyEditorBase;
          return BottomNavigationBarItem(
            icon: Icon(editorPage.icon),
            label: editorPage.label,
          );
        }).toList(),
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
