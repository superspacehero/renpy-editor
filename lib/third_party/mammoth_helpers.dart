// Helper functions for the mammoth.dart file

/// Convert Word's highlight color name to hex color code
String convertHighlightToHex(String highlightName) {
  // Map of Word's highlight color names to hex color codes
  final Map<String, String> highlightColors = {
    'black': '000000',
    'blue': '0000FF',
    'cyan': '00FFFF',
    'green': '00FF00',
    'magenta': 'FF00FF',
    'red': 'FF0000',
    'yellow': 'FFFF00',
    'white': 'FFFFFF',
    'darkBlue': '000080',
    'darkCyan': '008080',
    'darkGreen': '008000',
    'darkMagenta': '800080',
    'darkRed': '800000',
    'darkYellow': '808000',
    'darkGray': '808080',
    'lightGray': 'C0C0C0',
  };
  
  return highlightColors[highlightName.toLowerCase()] ?? 'FFFF00'; // Default to yellow if not found
}
