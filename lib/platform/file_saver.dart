import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Lets the user choose where to save a file the app made.
abstract interface class FileSaver {
  /// Asks where to save [contents] (UTF-8) as [fileName]. Returns false if
  /// the user cancelled.
  Future<bool> save({
    required String fileName,
    required String mimeType,
    required String contents,
  });
}

/// Android's document picker (no storage permission needed) or Windows'
/// save dialog.
class SystemFileSaver implements FileSaver {
  const new();

  @override
  Future<bool> save({
    required String fileName,
    required String mimeType,
    required String contents,
  }) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save your data',
      fileName: fileName,
      mimeType: mimeType,
      bytes: Uint8List.fromList(utf8.encode(contents)),
    );
    return saved != null;
  }
}
