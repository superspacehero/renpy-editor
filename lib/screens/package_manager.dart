import 'package:flutter/material.dart';

import 'package:renpy_editor/screens/base_editor.dart';
import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/project_manager.dart';
import 'package:renpy_editor/services/package_manager_service.dart';
import 'package:renpy_editor/models/renpy_package.dart';

/// A widget for managing Ren'Py packages

/// A widget for managing Ren'Py packages
class PackageManager extends RenpyEditorBase {
  const PackageManager({
    super.key,
    super.filePath,
    super.onSave,
    super.title = 'Ren\'Py Package Manager',
  }) : super(
          icon: Icons.extension,
          label: 'Packages',
        );

  @override
  State<PackageManager> createState() => _PackageManagerState();
}

class _PackageManagerState extends RenpyEditorBaseState<PackageManager> {
  List<RenPyPackage> _availablePackages = [];
  List<RenPyPackage> _installedPackages = [];
  bool _packageLoading = false;
  final TextEditingController _gitUrlController = TextEditingController();
  final TextEditingController _gitBranchController = TextEditingController();
  final TextEditingController _repoUrlController = TextEditingController();
  final packageManager = PackageManagerService();

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  @override
  void dispose() {
    _gitUrlController.dispose();
    _gitBranchController.dispose();
    _repoUrlController.dispose();
    super.dispose();
  }

  @override
  String generateContent() {
    // Package manager doesn't generate content for saving
    return '';
  }

  @override
  Future<void> loadProjectSettings() async {
    // Load package-related project settings if needed
    // This is already handled by _loadPackages() called in initState and configureForProject
  }

  @override
  void parseContent(String content) {
    // Package manager doesn't need to parse file content
    // as it works with package data rather than file content
  }

  /// Load packages from the project
  Future<void> _loadPackages() async {
    if (!projectManager.hasOpenProject()) {
      return;
    }

    setState(() {
      _packageLoading = true;
    });

    try {
      // Load installed packages from the project
      _installedPackages =
          List.from(projectManager.currentProject!.installedPackages);

      // Load available packages from repositories
      _availablePackages = await packageManager.getAvailablePackages();
    } catch (e) {
      LogError('Error loading packages: $e');
    } finally {
      setState(() {
        _packageLoading = false;
      });
    }
  }

  /// Install a package in the project
  Future<void> _installPackage(RenPyPackage package) async {
    setState(() {
      _packageLoading = true;
    });

    try {
      final success = await packageManager.installPackage(package);
      if (success) {
        await _loadPackages();
      }
    } catch (e) {
      LogError('Error installing package: $e');
    } finally {
      setState(() {
        _packageLoading = false;
      });
    }
  }

  /// Uninstall a package from the project
  Future<void> _uninstallPackage(String packageName) async {
    setState(() {
      _packageLoading = true;
    });

    try {
      final success = await packageManager.uninstallPackage(packageName);
      if (success) {
        await _loadPackages();
      }
    } catch (e) {
      LogError('Error uninstalling package: $e');
    } finally {
      setState(() {
        _packageLoading = false;
      });
    }
  }

  /// Add a repository to the list
  Future<void> _addRepository() async {
    final repoUrl = _repoUrlController.text.trim();
    if (repoUrl.isEmpty) {
      return;
    }

    setState(() {
      _packageLoading = true;
    });

    try {
      packageManager.addRepository(repoUrl);
      _repoUrlController.clear();
      await _loadPackages();
    } catch (e) {
      LogError('Error adding repository: $e');
    } finally {
      setState(() {
        _packageLoading = false;
      });
    }
  }

  /// Remove a repository from the list
  Future<void> _removeRepository(String repoUrl) async {
    setState(() {
      _packageLoading = true;
    });

    try {
      packageManager.removeRepository(repoUrl);
      await _loadPackages();
    } catch (e) {
      LogError('Error removing repository: $e');
    } finally {
      setState(() {
        _packageLoading = false;
      });
    }
  }

  /// Scan a git repository for packages
  Future<void> _scanGitRepository() async {
    final gitUrl = _gitUrlController.text.trim();
    final gitBranch = _gitBranchController.text.trim();

    if (gitUrl.isEmpty) {
      return;
    }

    setState(() {
      _packageLoading = true;
    });

    try {
      final packages = await packageManager.scanGitRepositoryForPackages(
        gitUrl,
        branch: gitBranch.isEmpty ? null : gitBranch,
      );

      setState(() {
        _availablePackages = packages;
        _gitUrlController.clear();
        _gitBranchController.clear();
      });
    } catch (e) {
      LogError('Error scanning git repository: $e');
    } finally {
      setState(() {
        _packageLoading = false;
      });
    }
  }

  @override
  void applyChange(Map<String, dynamic> changes, bool markDirty) {
    // Package manager doesn't apply changes to content
  }

  @override
  Widget buildEditorBody() {
    return _packageLoading
        ? const Center(child: CircularProgressIndicator())
        : DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Installed Packages'),
                    Tab(text: 'Available Packages'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildInstalledPackagesTab(),
                      _buildAvailablePackagesTab(),
                    ],
                  ),
                ),
              ],
            ),
          );
  }

  @override
  void configureForProject(RenPyProject project) {
    _loadPackages();
  }

  @override
  String generateDefaultFilePath() {
    return 'packages.json';
  }

  Widget _buildInstalledPackagesTab() {
    if (_installedPackages.isEmpty) {
      return const Center(
        child: Text('No packages installed'),
      );
    }

    return ListView.builder(
      itemCount: _installedPackages.length,
      itemBuilder: (context, index) {
        final package = _installedPackages[index];
        return ListTile(
          title: Text(package.name),
          subtitle: Text(package.description),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _uninstallPackage(package.name),
          ),
        );
      },
    );
  }

  Widget _buildAvailablePackagesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _repoUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Repository URL',
                    hintText: 'Enter a repository URL',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addRepository,
              ),
            ],
          ),
        ),
        // Add repository list with delete buttons
        if (packageManager.packageRepositories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    'Added Repositories:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...packageManager.packageRepositories.map(
                  (repoUrl) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(repoUrl, overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          onPressed: () => _removeRepository(repoUrl),
                          tooltip: 'Remove repository',
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _gitUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Git URL',
                    hintText: 'Enter a git repository URL',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _gitBranchController,
                  decoration: const InputDecoration(
                    labelText: 'Branch (optional)',
                    hintText: 'Enter a branch name',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _scanGitRepository,
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _availablePackages.isEmpty
              ? const Center(
                  child: Text('No packages available'),
                )
              : ListView.builder(
                  itemCount: _availablePackages.length,
                  itemBuilder: (context, index) {
                    final package = _availablePackages[index];
                    final isInstalled =
                        _installedPackages.any((p) => p.name == package.name);
                    return ListTile(
                      title: Text(package.name),
                      subtitle: Text(package.description),
                      trailing: isInstalled
                          ? const Icon(Icons.check)
                          : IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () => _installPackage(package),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
