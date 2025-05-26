import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:path/path.dart' as path;

import 'package:renpy_editor/utils/logging.dart';
import 'package:renpy_editor/models/renpy_package.dart';

/// A widget for creating new Ren'Py packages
class PackageCreator extends StatefulWidget {
  const PackageCreator({super.key});

  @override
  State<PackageCreator> createState() => _PackageCreatorState();
}

class _PackageCreatorState extends State<PackageCreator> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _versionController = TextEditingController(text: '1.0.0');
  final _authorController = TextEditingController();
  final _websiteController = TextEditingController();
  final _licenseController = TextEditingController(text: 'MIT');
  final _installPathController = TextEditingController(text: 'game/modules');

  final List<String> _selectedFiles = [];
  final List<String> _dependencies = [];
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _versionController.dispose();
    _authorController.dispose();
    _websiteController.dispose();
    _licenseController.dispose();
    _installPathController.dispose();
    super.dispose();
  }

  /// Add files to the package
  Future<void> _addFiles() async {
    final result = await file_picker.FilePicker.platform.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Select Ren\'Py script files',
      type: file_picker.FileType.custom,
      allowedExtensions: [
        'rpy',
        'rpyc',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'mp3',
        'ogg',
        'wav'
      ],
    );

    if (result != null) {
      setState(() {
        for (final file in result.files) {
          if (file.path != null && !_selectedFiles.contains(file.path)) {
            _selectedFiles.add(file.path!);
          }
        }
      });
    }
  }

  /// Remove a file from the package
  void _removeFile(String filePath) {
    setState(() {
      _selectedFiles.remove(filePath);
    });
  }

  /// Add a dependency to the package
  void _addDependency() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Dependency'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Package Name',
            hintText: 'Enter the name of the required package',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final dependency = controller.text.trim();
              if (dependency.isNotEmpty &&
                  !_dependencies.contains(dependency)) {
                setState(() {
                  _dependencies.add(dependency);
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Remove a dependency from the package
  void _removeDependency(String dependency) {
    setState(() {
      _dependencies.remove(dependency);
    });
  }

  /// Create the package
  Future<void> _createPackage() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must select at least one file for the package.'),
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Create a package object
      final package = RenPyPackage(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        version: _versionController.text.trim(),
        author: _authorController.text.trim(),
        url: _websiteController.text.trim(),
        license: _licenseController.text.trim(),
        dependencies: _dependencies,
        files: _selectedFiles,
      );

      // Ask for output directory
      final outputDir = await file_picker.FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select directory to save package',
      );

      if (outputDir != null) {
        // Create package manifest file
        final manifestFile =
            File(path.join(outputDir, '${package.name}_package.json'));
        await manifestFile.writeAsString(json.encode(package.toJson()));

        // Copy all files to the output directory
        final packageDir = Directory(path.join(outputDir, package.name));
        if (!await packageDir.exists()) {
          await packageDir.create(recursive: true);
        }

        for (final filePath in _selectedFiles) {
          final file = File(filePath);
          if (await file.exists()) {
            final fileName = path.basename(filePath);
            final destPath = path.join(packageDir.path, fileName);
            await file.copy(destPath);
          }
        }

        // Show success message - check if still mounted
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Package ${package.name} created successfully at $outputDir'),
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Reset the form
        if (mounted) {
          _formKey.currentState!.reset();
          setState(() {
            _selectedFiles.clear();
            _dependencies.clear();
          });
        }
      }
    } catch (e) {
      LogError('Error creating package: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating package: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Ren\'Py Package'),
      ),
      body: _isCreating
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Package Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Package Name*',
                          hintText: 'e.g. simple-inventory',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Package name is required';
                          }
                          if (!RegExp(r'^[a-z0-9-_]+$').hasMatch(value)) {
                            return 'Package name can only contain lowercase letters, numbers, hyphens and underscores';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description*',
                          hintText: 'Describe what your package does',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Description is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _versionController,
                              decoration: const InputDecoration(
                                labelText: 'Version*',
                                hintText: 'e.g. 1.0.0',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Version is required';
                                }
                                if (!RegExp(r'^\d+\.\d+\.\d+$')
                                    .hasMatch(value)) {
                                  return 'Version must be in format x.y.z';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _authorController,
                              decoration: const InputDecoration(
                                labelText: 'Author*',
                                hintText: 'Your name or organization',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Author is required';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _websiteController,
                        decoration: const InputDecoration(
                          labelText: 'Website (optional)',
                          hintText: 'e.g. https://github.com/username/repo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _licenseController,
                              decoration: const InputDecoration(
                                labelText: 'License',
                                hintText: 'e.g. MIT',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _installPathController,
                              decoration: const InputDecoration(
                                labelText: 'Install Path*',
                                hintText: 'Relative to game directory',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Install path is required';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Package Files',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _addFiles,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Files'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _selectedFiles.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('No files selected'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _selectedFiles.length,
                              itemBuilder: (context, index) {
                                final filePath = _selectedFiles[index];
                                return ListTile(
                                  leading: const Icon(Icons.insert_drive_file),
                                  title: Text(path.basename(filePath)),
                                  subtitle: Text(filePath),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _removeFile(filePath),
                                  ),
                                );
                              },
                            ),
                      const SizedBox(height: 24),
                      const Text(
                        'Dependencies (Optional)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _addDependency,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Dependency'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _dependencies.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('No dependencies'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _dependencies.length,
                              itemBuilder: (context, index) {
                                final dependency = _dependencies[index];
                                return ListTile(
                                  leading: const Icon(Icons.extension),
                                  title: Text(dependency),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () =>
                                        _removeDependency(dependency),
                                  ),
                                );
                              },
                            ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _createPackage,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16.0),
                        ),
                        child: const Text('Create Package'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
