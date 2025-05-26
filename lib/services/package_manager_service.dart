import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/project_manager.dart';
import 'package:renpy_editor/utils/git_utils.dart';
import 'package:renpy_editor/models/renpy_package.dart';

/// A service class to manage Ren'Py packages
class PackageManagerService {
  static final PackageManagerService _instance =
      PackageManagerService._internal();
  final List<String> _packageRepositories = [];

  factory PackageManagerService() {
    return _instance;
  }

  PackageManagerService._internal();

  /// Get list of package repositories
  List<String> get packageRepositories => _packageRepositories;

  /// Add a new repository to the list
  void addRepository(String repoUrl) {
    if (!_packageRepositories.contains(repoUrl)) {
      _packageRepositories.add(repoUrl);
    }
  }

  /// Remove a repository from the list
  void removeRepository(String repoUrl) {
    _packageRepositories.remove(repoUrl);
  }

  /// Get available packages from all repositories
  Future<List<RenPyPackage>> getAvailablePackages() async {
    final List<RenPyPackage> allPackages = [];

    // If there are no repositories, return empty list
    if (_packageRepositories.isEmpty) {
      return allPackages;
    }

    // Fetch packages from each repository
    for (final repoUrl in _packageRepositories) {
      try {
        // Scan the repository for packages
        final repoPackages = await scanGitRepositoryForPackages(repoUrl);
        allPackages.addAll(repoPackages);
      } catch (e) {
        LogError('Error fetching packages from repository $repoUrl: $e');
        // Continue to next repository even if one fails
      }
    }

    return allPackages;
  }

  /// Install a package in the project
  Future<bool> installPackage(RenPyPackage package) async {
    final projectManager = ProjectManager();
    if (!projectManager.hasOpenProject() ||
        !projectManager.currentProject!.isValid) {
      throw Exception('Cannot install packages in an invalid project');
    }

    final project = projectManager.currentProject!;
    final gameDirPath = project.gameDirPath;

    try {
      // Check if package is already installed
      if (project.installedPackages.any((p) => p.name == package.name)) {
        // Update the package if it's already installed
        await uninstallPackage(package.name);
      }

      // Determine the installation path
      final installPath = 'game/modules/${package.name}';

      // Create the installation directory if it doesn't exist
      final installDir = Directory(path.join(gameDirPath, installPath));
      if (!await installDir.exists()) {
        await installDir.create(recursive: true);
      }

      // If the package URL ends with .git, it's a git repository
      if (package.url.endsWith('.git')) {
        final tempDir =
            Directory(path.join(gameDirPath, 'temp_${package.name}'));
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
          await tempDir.create();

          // Clone the repository
          final repoPath = await GitUtils.cloneRepository(
            url: package.url,
            targetDirectory: tempDir.path,
            branch: package.gitBranch,
          );

          // Look for package.json in the repository to find the package
          final packageJsonFiles =
              await GitUtils.findPackageJsonFiles(repoPath);
          Directory sourceDir = Directory(repoPath);

          // Find the package.json file that matches our package name
          for (final packageJsonFile in packageJsonFiles) {
            try {
              final json =
                  jsonDecode(await File(packageJsonFile).readAsString());
              if (json['name'] == package.name) {
                // Found the matching package.json, use its directory as the source
                sourceDir = Directory(path.dirname(packageJsonFile));
                break;
              }
            } catch (e) {
              LogError('Error parsing package.json file: $e');
            }
          }

          // Copy all files from the source directory to the installation directory
          for (final file in package.files) {
            final sourceFile = File(path.join(sourceDir.path, file));
            final targetFile = File(path.join(installDir.path, file));

            // Create parent directories if they don't exist
            final targetDir = Directory(path.dirname(targetFile.path));
            if (!await targetDir.exists()) {
              await targetDir.create(recursive: true);
            }

            if (await sourceFile.exists()) {
              await sourceFile.copy(targetFile.path);
            } else {
              LogError('Source file does not exist: ${sourceFile.path}');
            }
          }

          // Clean up the temporary directory
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } catch (e) {
          LogError('Error installing package from git: $e');
          return false;
        }
      } else {
        // Just a local package, copy the files
        // This would be implemented later for packages created within the editor
      }

      // Add the package to the list of installed packages
      project.installedPackages.add(package);

      await saveInstalledPackages();
      return true;
    } catch (e) {
      LogError('Error installing package ${package.name}: $e');
      return false;
    }
  }

  /// Uninstall a package from the project
  Future<bool> uninstallPackage(String packageName) async {
    final projectManager = ProjectManager();
    if (!projectManager.hasOpenProject() ||
        !projectManager.currentProject!.isValid) {
      throw Exception('Cannot uninstall packages in an invalid project');
    }

    final project = projectManager.currentProject!;
    final gameDirPath = project.gameDirPath;

    try {
      // Find the package in the installed packages list
      final packageIndex = project.installedPackages
          .indexWhere((package) => package.name == packageName);
      if (packageIndex == -1) {
        LogError('Package $packageName is not installed');
        return false;
      }

      final package = project.installedPackages[packageIndex];

      // Determine the installation path
      final installPath = 'game/modules/${package.name}';

      // Remove the package files
      final installDir = Directory(path.join(gameDirPath, installPath));
      if (await installDir.exists()) {
        await installDir.delete(recursive: true);
      }

      // Remove the package from the installed packages list
      project.installedPackages.removeAt(packageIndex);
      await saveInstalledPackages();

      return true;
    } catch (e) {
      LogError('Error uninstalling package $packageName: $e');
      return false;
    }
  }

  /// Scan a git repository URL for available packages
  Future<List<RenPyPackage>> scanGitRepositoryForPackages(String gitUrl,
      {String? branch}) async {
    final projectManager = ProjectManager();
    if (!projectManager.hasOpenProject() ||
        !projectManager.currentProject!.isValid) {
      throw Exception('Cannot scan packages for an invalid project');
    }

    final gameDirPath = projectManager.currentProject!.gameDirPath;
    final List<RenPyPackage> packages = [];

    final tempDir = Directory(path.join(
        gameDirPath, 'temp_scan_${DateTime.now().millisecondsSinceEpoch}'));

    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create();

      // Clone the repository
      final repoPath = await GitUtils.cloneRepository(
        url: gitUrl,
        targetDirectory: tempDir.path,
        branch: branch,
      );

      // Find all package.json files in the repository
      final packageFiles = await GitUtils.findPackageJsonFiles(repoPath);

      for (final packageFile in packageFiles) {
        try {
          final packageDir = path.dirname(packageFile);
          final packageJson =
              json.decode(await File(packageFile).readAsString());

          // Only process files that have the required fields
          if (packageJson.containsKey('name')) {
            // Find all .rpy files in the package directory
            final dir = Directory(packageDir);
            final List<String> rpyFiles = [];

            await for (final entity in dir.list(recursive: true)) {
              if (entity is File && entity.path.endsWith('.rpy')) {
                rpyFiles.add(path.relative(entity.path, from: packageDir));
              }
            }

            // Create a package from the package.json data
            final package = RenPyPackage(
              name: packageJson['name'],
              description: packageJson['description'] ?? '',
              version: packageJson['version'] ?? '1.0.0',
              author: packageJson['author'] ?? 'Unknown',
              url: gitUrl, // Use the repository URL
              license: packageJson['license'] ?? 'MIT',
              dependencies:
                  List<String>.from(packageJson['dependencies'] ?? []),
              files: packageJson.containsKey('files')
                  ? List<String>.from(packageJson['files'])
                  : rpyFiles,
              gitBranch: branch,
            );

            packages.add(package);
          }
        } catch (e) {
          LogError('Error processing package.json file $packageFile: $e');
        }
      }
    } catch (e) {
      LogError('Error scanning git repository for packages: $e');
    } finally {
      // Clean up the temporary directory in all cases
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (e) {
          LogError('Error cleaning up temporary directory: $e');
        }
      }
    }

    return packages; // Always return the packages list
  }

  /// Save the installed packages information
  Future<void> saveInstalledPackages() async {
    final projectManager = ProjectManager();
    if (!projectManager.hasOpenProject() ||
        !projectManager.currentProject!.isValid) {
      return;
    }

    final project = projectManager.currentProject!;

    try {
      final packagesFile =
          File(path.join(project.gameDirPath, 'packages.json'));
      final content = json.encode(project.installedPackages
          .map((package) => package.toJson())
          .toList());
      await packagesFile.writeAsString(content);
    } catch (e) {
      LogError('Error saving installed packages: $e');
    }
  }
}
