/// Represents a Ren'Py package/module that can be installed in a project
class RenPyPackage {
  final String name;
  final String description;
  final String version;
  final String author;

  /// URL to the package website or git repository
  /// If URL ends with .git, it will be treated as a git repository
  final String url;
  final String license;
  final List<String> dependencies;
  final List<String> files;
  final String? gitBranch; // Branch to use (defaults to 'main' or 'master')

  RenPyPackage({
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.url = '',
    this.license = 'MIT',
    this.dependencies = const [],
    required this.files,
    this.gitBranch,
  });

  /// Create a package from a JSON map
  factory RenPyPackage.fromJson(Map<String, dynamic> json) {
    // Prioritize gitRepository if present, otherwise use website
    String url = '';
    if (json['gitRepository'] != null) {
      url = json['gitRepository'] as String;
    } else if (json['website'] != null) {
      url = json['website'] as String;
    }

    return RenPyPackage(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Unknown',
      url: url,
      license: json['license'] as String? ?? 'MIT',
      dependencies: (json['dependencies'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      files:
          (json['files'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      gitBranch: json['gitBranch'] as String?,
    );
  }

  /// Convert the package to a JSON map
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'name': name,
      'description': description,
      'version': version,
      'author': author,
      'license': license,
      'dependencies': dependencies,
      'files': files,
    };

    // If URL ends with .git, treat it as a git repository
    if (url.endsWith('.git')) {
      json['gitRepository'] = url;
    } else if (url.isNotEmpty) {
      json['website'] = url;
    }

    if (gitBranch != null) json['gitBranch'] = gitBranch;

    return json;
  }
}
