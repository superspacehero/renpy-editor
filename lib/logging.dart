import 'package:logging/logging.dart';

Logger logger = Logger("RenpyEditor");

void Log(Object object) {
  logger.info(object.toString());
}

void LogError(Object object) {
  logger.severe(object.toString());
}

void LogWarning(Object object) {
  logger.warning(object.toString());
}

void LogDebug(Object object) {
  logger.fine(object.toString());
}
