import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';

// QR Scanner Screen (Using MobileScanner)
class QRScannerScreen extends StatefulWidget {
  final Function(String) onScanned;
  
  const QRScannerScreen({super.key, required this.onScanned});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );
  bool _hasScanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() {
          _hasScanned = true;
        });
        widget.onScanned(barcode.rawValue!);
        if (mounted) {
          Navigator.pop(context);
        }
        break; 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'SCAN QR CODE',
          style: GoogleFonts.orbitron(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Torch Button
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              // MobileScanner 7.x: state is MobileScannerState
              switch (state.torchState) {
                case TorchState.off:
                  return IconButton(
                    icon: const Icon(Icons.flash_off, color: Colors.grey),
                    onPressed: () => controller.toggleTorch(),
                  );
                case TorchState.on:
                  return IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.yellow),
                    onPressed: () => controller.toggleTorch(),
                  );
                case TorchState.auto: // Handle auto case if exists, or default
                  return IconButton(
                    icon: const Icon(Icons.flash_auto, color: Colors.white),
                    onPressed: () => controller.toggleTorch(),
                  );
                 case TorchState.unavailable:
                   return const SizedBox.shrink(); 
              }
            },
          ),
          // Camera Switch Button
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              switch (state.cameraDirection) {
                case CameraFacing.front:
                  return IconButton(
                    icon: const Icon(Icons.camera_front),
                    onPressed: () => controller.switchCamera(),
                  );
                case CameraFacing.back:
                  return IconButton(
                     icon: const Icon(Icons.camera_rear),
                     onPressed: () => controller.switchCamera(),
                  );
                case CameraFacing.external:
                   return IconButton(
                     icon: const Icon(Icons.cameraswitch), 
                     onPressed: () => controller.switchCamera(),
                   );
                case CameraFacing.unknown:
                   return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
          ),
          // Overlay
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: Colors.greenAccent,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Overlay Shape (Re-implemented for MobileScanner as it's not included)
class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 10.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.right, rect.top);
    }

    return getLeftTopPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final borderWidthSize = width / 2;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final _cutOutSize = cutOutSize;
    final _borderLength = borderLength;
    final _borderRadius = borderRadius;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final boxPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - _cutOutSize / 2 + borderOffset,
      rect.top + height / 2 - _cutOutSize / 2 + borderOffset,
      _cutOutSize - borderWidth,
      _cutOutSize - borderWidth,
    );

    canvas
      ..saveLayer(
        rect,
        backgroundPaint,
      )
      ..drawRect(
        rect,
        backgroundPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          cutOutRect,
          Radius.circular(_borderRadius),
        ),
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();

    final rRect = RRect.fromRectAndRadius(
      cutOutRect,
      Radius.circular(_borderRadius),
    );

    // Draw corners
    // Top left
    canvas.drawPath(
      Path()
        ..moveTo(rRect.left, rRect.top + _borderLength)
        ..lineTo(rRect.left, rRect.top + _borderRadius)
        ..arcToPoint(
          Offset(rRect.left + _borderRadius, rRect.top),
          radius: Radius.circular(_borderRadius),
        )
        ..lineTo(rRect.left + _borderLength, rRect.top),
      borderPaint,
    );

    // Top right
    canvas.drawPath(
      Path()
        ..moveTo(rRect.right - _borderLength, rRect.top)
        ..lineTo(rRect.right - _borderRadius, rRect.top)
        ..arcToPoint(
          Offset(rRect.right, rRect.top + _borderRadius),
          radius: Radius.circular(_borderRadius),
        )
        ..lineTo(rRect.right, rRect.top + _borderLength),
      borderPaint,
    );

    // Bottom right
    canvas.drawPath(
      Path()
        ..moveTo(rRect.right, rRect.bottom - _borderLength)
        ..lineTo(rRect.right, rRect.bottom - _borderRadius)
        ..arcToPoint(
          Offset(rRect.right - _borderRadius, rRect.bottom),
          radius: Radius.circular(_borderRadius),
        )
        ..lineTo(rRect.right - _borderLength, rRect.bottom),
      borderPaint,
    );

    // Bottom left
    canvas.drawPath(
      Path()
        ..moveTo(rRect.left + _borderLength, rRect.bottom)
        ..lineTo(rRect.left + _borderRadius, rRect.bottom)
        ..arcToPoint(
          Offset(rRect.left, rRect.bottom - _borderRadius),
          radius: Radius.circular(_borderRadius),
        )
        ..lineTo(rRect.left, rRect.bottom - _borderLength),
      borderPaint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }
}
