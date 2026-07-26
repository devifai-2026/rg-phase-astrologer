import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Normalise a user-picked image to a small JPEG before upload.
///
/// Why this exists: `ImagePicker.imageQuality` is **silently ignored for PNG**
/// ("compressing is not supported for type PNG. Returning the image with
/// original quality"), and Android saves every screenshot as PNG. So a seeker
/// sharing a screenshot uploaded it at full size — 350KB to several MB — and the
/// chat bubble on both apps sat on a loading placeholder long enough that it
/// looked like a permanently broken image.
///
/// Users can pick any format, so rather than trusting the picker's quality hint
/// we re-encode ourselves: PNG / HEIC / WebP / JPEG all come out as JPEG, which
/// every surface in both apps can decode and which is 5-20x smaller for photos.
///
/// Best-effort by design: if the platform can't decode the input (an exotic
/// format, a corrupt file) the ORIGINAL file is returned so the send still works.
/// A slow upload is a far better outcome than refusing to send the photo.
class ImagePrep {
  /// Long-edge cap. 1080 keeps a shared screenshot legible when zoomed while
  /// landing comfortably under ~150KB at quality 80.
  static const int maxEdge = 1080;
  static const int quality = 80;

  /// Re-encode [file] as a JPEG under [maxEdge] on its long side.
  /// Returns the converted file, or [file] itself if conversion isn't possible.
  static Future<File> toUploadableJpeg(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      // Unique name per call so a retry never collides with a cached temp file.
      final target =
          '${dir.path}/upload_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final out = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        format: CompressFormat.jpeg,
        quality: quality,
        minWidth: maxEdge,
        minHeight: maxEdge,
        // Honour EXIF rotation, else portrait photos from some cameras upload
        // sideways once the orientation tag is dropped by re-encoding.
        autoCorrectionAngle: true,
      );
      if (out == null) return file;
      final converted = File(out.path);
      // Never make things worse: if re-encoding grew the file (already-optimised
      // small JPEG), send the original.
      if (await converted.length() >= await file.length()) return file;
      return converted;
    } catch (_) {
      return file; // decode/encode unsupported → upload as-is
    }
  }
}
