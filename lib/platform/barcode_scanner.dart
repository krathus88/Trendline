import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';
import 'package:trendline/platform/android/camera_barcode_scanner.dart';

/// Scans a product barcode with the camera. Only Android has a camera
/// scanner; elsewhere [isAvailable] is false and the UI hides the option.
abstract interface class BarcodeScanner {
  bool get isAvailable;

  /// Opens the scanner and returns the scanned barcode, or null if the user
  /// backed out.
  Future<String?> scan(BuildContext context);
}

class UnavailableBarcodeScanner implements BarcodeScanner {
  const new();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> scan(BuildContext context) async => null;
}

BarcodeScanner createBarcodeScanner() => Platform.isAndroid
    ? const CameraBarcodeScanner()
    : const UnavailableBarcodeScanner();
