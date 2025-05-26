import 'dart:io';
import 'package:git/git.dart';
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';

/// A utility class for Git operations
class GitUtils {
  /// Clone a git repository to a local directory
  ///
  /// Returns the path to the cloned repository directory
  static Future<String> cloneRepository({
    required String url,
    required String targetDirectory,
    String? branch,
    bool shallow = true,
  }) async {
    try {
      // Build git arguments
      final List<String> args = ['clone'];
      if (shallow) args.add('--depth=1');
      if (branch != null) {
        args.add('--branch');
        args.add(branch);
      }
      args.add(url);
      args.add(targetDirectory);

      // Run git clone command
      final result = await Process.run('git', args);

      if (result.exitCode != 0) {
        throw Exception('Git clone failed: ${result.stderr}');
      }

      // Create a GitDir instance from the cloned directory
      final gitDir = await GitDir.fromExisting(targetDirectory);
      return gitDir.path;
    } catch (e) {
      LogError('Error cloning git repository: $e');
      rethrow;
    }
  }

  /// Pull the latest changes from a git repository
  static Future<bool> pullRepository(String repoPath, {String? branch}) async {
    try {
      final GitDir gitDir = await GitDir.fromExisting(repoPath);
      final result =
          await gitDir.runCommand(['pull', 'origin', branch ?? 'main']);

      return result.exitCode == 0;
    } catch (e) {
      LogError('Error pulling git repository: $e');
      return false;
    }
  }

  /// Check if a path is a git repository
  static Future<bool> isGitRepository(String dirPath) async {
    try {
      final gitDir = Directory(path.join(dirPath, '.git'));
      return await gitDir.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get the current branch of a git repository
  static Future<String?> getCurrentBranch(String repoPath) async {
    try {
      final GitDir gitDir = await GitDir.fromExisting(repoPath);
      final result =
          await gitDir.runCommand(['rev-parse', '--abbrev-ref', 'HEAD']);

      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
      return null;
    } catch (e) {
      LogError('Error getting current branch: $e');
      return null;
    }
  }

  /// Check if a repository has a specific branch
  static Future<bool> hasBranch(String repoPath, String branch) async {
    try {
      final GitDir gitDir = await GitDir.fromExisting(repoPath);
      final result = await gitDir.runCommand(['branch', '--list', branch]);

      return result.exitCode == 0 && result.stdout.toString().contains(branch);
    } catch (e) {
      LogError('Error checking if branch exists: $e');
      return false;
    }
  }

  /// Check if a directory within a git repository contains a package.json file
  static Future<bool> hasPackageJson(String repoPath, [String? subPath]) async {
    final packagePath = subPath != null
        ? path.join(repoPath, subPath, 'package.json')
        : path.join(repoPath, 'package.json');

    return File(packagePath).exists();
  }

  /// Find all package.json files in a git repository
  static Future<List<String>> findPackageJsonFiles(String repoPath) async {
    final List<String> packageFiles = [];

    try {
      final dir = Directory(repoPath);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && path.basename(entity.path) == 'package.json') {
          packageFiles.add(entity.path);
        }
      }
    } catch (e) {
      LogError('Error finding package.json files: $e');
    }

    return packageFiles;
  }
}
