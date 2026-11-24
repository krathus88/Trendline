import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:trendline/platform/barcode_scanner.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Android camera scanner. This is the only file that may import
/// `mobile_scanner`, so other platforms build without it being used.
class CameraBarcodeScanner implements BarcodeScanner {
  const new();

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<String>(builder: (_) => const _ScannerPage()));
}

class _ScannerPage extends StatefulWidget {
  const new();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  // Product barcodes only, which also makes detection faster.
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && RegExp(r'^[0-9]{6,14}$').hasMatch(value)) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  Center(
                    child: Text(
                      'Point the camera at the barcode',
                      style: text.bodyLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
