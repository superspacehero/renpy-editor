#!/bin/bash

# Centralized App Configuration Build Script
# This script helps maintain consistency across all platform configurations

APP_DISPLAY_NAME="Ren'Py Editor"
APP_PACKAGE_NAME="renpy-editor"
APP_VERSION="1.0.0"

echo "🔧 Updating centralized app configuration..."
echo "   Display Name: $APP_DISPLAY_NAME"
echo "   Package Name: $APP_PACKAGE_NAME"
echo "   Version: $APP_VERSION"

# Update Flutter constants
echo "📱 Updating Flutter constants..."
cat >lib/constants.dart <<EOF
/// Application constants and configuration
class AppConstants {
  /// The display name of the application
  static const String appDisplayName = "$APP_DISPLAY_NAME";
  
  /// The package name/identifier
  static const String packageName = "$APP_PACKAGE_NAME";
  
  /// Application version
  static const String version = "$APP_VERSION";
}
EOF

# Update Linux CMakeLists.txt (if the variable doesn't exist, add it)
echo "🐧 Checking Linux configuration..."
if ! grep -q "set(APP_DISPLAY_NAME" linux/CMakeLists.txt; then
    echo "   Adding APP_DISPLAY_NAME to linux/CMakeLists.txt..."
    sed -i '/^project(runner LANGUAGES CXX)$/a\\n# App display name configuration\nset(APP_DISPLAY_NAME "'"$APP_DISPLAY_NAME"'")' linux/CMakeLists.txt
else
    echo "   APP_DISPLAY_NAME already exists in linux/CMakeLists.txt"
fi

# Update Windows CMakeLists.txt (if the variable doesn't exist, add it)
echo "🪟 Checking Windows configuration..."
if ! grep -q "set(APP_DISPLAY_NAME" windows/CMakeLists.txt; then
    echo "   Adding APP_DISPLAY_NAME to windows/CMakeLists.txt..."
    sed -i '/^project(renpy-editor LANGUAGES CXX)$/a\\n# App display name configuration\nset(APP_DISPLAY_NAME "'"$APP_DISPLAY_NAME"'")' windows/CMakeLists.txt
else
    echo "   APP_DISPLAY_NAME already exists in windows/CMakeLists.txt"
fi

echo "✅ Configuration update complete!"
echo ""
echo "📋 Summary of configured files:"
echo "   - lib/constants.dart (Flutter)"
echo "   - linux/CMakeLists.txt (Linux platform)"
echo "   - windows/CMakeLists.txt (Windows platform)"
echo "   - macOS uses Xcode's PRODUCT_NAME variable"
echo ""
echo "🚀 To apply changes:"
echo "   - Run 'flutter clean && flutter build <platform>' to rebuild"
echo "   - For platform-specific builds, use the respective build commands"
