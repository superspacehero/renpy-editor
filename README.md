# Ren'Py Editor

A Flutter-based visual editor for Ren'Py, building off of [doc-to-renpy](https://github.com/pass-by-reference/doc-to-renpy).

## Features

### Text Converter

Convert text documents (.txt, .md, .doc, .docx) to Ren'Py script format.

### Settings Editor

Edit Ren'Py project settings with a user-friendly interface. Supports:

- Automatic saving of changes
- Undo/redo functionality
- Easy editing of options.rpy and styles.rpy files

### Package Manager

Easily manage and install modules for your Ren'Py projects:

- Browse available packages
- Install packages to your project
- Create your own packages to share with others
- Manage dependencies between packages

## Getting Started

1. Clone this repository
2. Install dependencies with `flutter pub get`
3. Run the application with `flutter run`

## Usage

### Opening a Project

You can open a Ren'Py project in both the Settings Editor and Package Manager tabs.
The project is loaded and validated to ensure it's a valid Ren'Py project with a 'game' directory.

#### Recent Projects

The application maintains a list of recently opened projects for quick access:

1. Click the folder icon in the top-right corner of the application
2. Select a project from the "Recent Projects" section
3. The project will be loaded automatically

#### Command-Line Options

You can also open a project directly from the command line using one of these formats:

```bash
# Direct path format
./renpy-editor /path/to/your/project

# Named parameter format
./renpy-editor --project=/path/to/your/project
```

This will launch the application and immediately open the specified project.

### Converting Text

1. Select a text file to convert
2. View the converted Ren'Py script
3. Save the output to your project

### Managing Packages

1. Open your Ren'Py project
2. Browse available packages
3. Install packages with a single click
4. Create your own packages to share with the community

### Creating Packages

1. Click "Create Package" in the Package Manager tab
2. Fill in the package details
3. Add your Ren'Py script files and resources
4. Specify dependencies if your package requires other packages
5. Create and save your package
