/// What the smart UI may upload (homework): images and PDFs.
const uploadExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'];

/// Per file.
const maxUploadBytes = 20 * 1024 * 1024;

bool isUploadAllowed(String name, int? size) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return uploadExtensions.contains(ext) &&
      size != null &&
      size > 0 &&
      size <= maxUploadBytes;
}
