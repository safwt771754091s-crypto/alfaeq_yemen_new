import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const _navy = Color(0xFF0A2540);
const _blue = Color(0xFF0D6EFD);

/// Camera barcode scanner used by the unified search: the detected code is
/// returned to the caller, which searches the catalog by name/barcode.
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
    ],
  );
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _handled = true;
        _controller.stop();
        Navigator.pop(context, value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('مسح الباركود', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                final on = state.torchState == TorchState.on;
                return IconButton(
                  tooltip: 'الفلاش',
                  onPressed: () => _controller.toggleTorch(),
                  icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                );
              },
            ),
          ],
        ),
        body: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              onDetectError: (error, _) => setState(() => _error = 'تعذر تشغيل الكاميرا. تحقق من صلاحية الكاميرا.'),
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
                      const SizedBox(height: 14),
                      const Text(
                        'تعذر الوصول إلى الكاميرا',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'امنح التطبيق صلاحية الكاميرا ثم أعد المحاولة، أو ابحث بكتابة الباركود.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: _blue, width: 3),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Text(
                _error ?? 'وجّه الكاميرا نحو باركود المنتج',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
