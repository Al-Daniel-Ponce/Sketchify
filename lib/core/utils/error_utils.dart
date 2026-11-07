import 'dart:io';

import '../../services/image_processing_service.dart';

String friendlyError(Object error) {
  if (error is ImageProcessingException) return error.message;
  if (error is FileSystemException) {
    return 'The file could not be read. It may have been moved or deleted.';
  }
  return 'Something went wrong. Please try again.';
}
