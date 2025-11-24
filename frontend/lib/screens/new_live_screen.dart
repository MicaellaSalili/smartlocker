import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';

class NewLiveScreen extends StatefulWidget {
  const NewLiveScreen({super.key});

  @override
  State<NewLiveScreen> createState() => _NewLiveScreenState();
}

class _NewLiveScreenState extends State<NewLiveScreen> {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // Steps: 0=Barcode, 1=Package Verification, 2=Motion Tracking, 3=Locker Detection
  int _currentStep = 0;
  String _instruction = 'Scan the barcode on the package';

  // Reference data
  String? _waybillId;
  List<double>? _referenceEmbedding;

  // Scanned data
  String? _scannedWaybillId;
  bool _barcodeDetected = false;
  MobileScannerController? _barcodeController;
  bool _isProcessing = false;

  // Tracking
  Rect? _trackedBox;
  Rect? _smoothedBox;
  // Keep explicit package and locker boxes for overlap checks
  Rect? _packageBox;
  Rect? _lockerBox;
  int _missCount = 0;
  static const int maxMisses = 2;
  double? _lastDetectionConfidence;
  DateTime? _lastDetectionTime;
  String? _trackedLabel;
  // Sequence state: must detect package then locker
  bool _packageDetected = false;
  DateTime? _packageDetectedAt;
  static const Duration packageToLockerTimeout = Duration(seconds: 8);
  // Debug: keep the last raw detections so we can render them on-screen
  List<Map<String, dynamic>> _lastDetections = [];
  // Last render-ready boxes (Rect, label, confidence) scaled in processing
  List<Map<String, dynamic>> _lastRenderBoxes = [];
  // Any-detection summary for UI banner (helps debugging mislabels)
  bool _detectedAny = false;
  String? _detectedAnyLabel;
  double? _detectedAnyConfidence;
  // Consecutive-frame gating: require multiple valid package frames before showing
  int _consecutivePackageFrames = 0;
  static const int packageFrameThreshold = 2; // require 2 consecutive frames
  // Capture next frame for debugging (shows raw detection JSON)
  bool _captureNextFrame = false;

  @override
  void initState() {
    super.initState();
    // Initialize barcode scanner first. Camera will be initialized after a successful scan.
    _initializeBarcodeScanner();
    // Load reference data after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReferenceData());
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) return;

    // Use high resolution (match ScanScreen) for better image quality
    _cameraController = CameraController(_cameras![0], ResolutionPreset.high, enableAudio: false);
    await _cameraController!.initialize();
    if (!mounted) return;
    
    setState(() => _isCameraInitialized = true);
    
    // Camera initialized; ready for motion tracking step later
  }

  void _initializeBarcodeScanner() {
    _barcodeController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  Future<void> _loadReferenceData() async {
    final transactionManager = Provider.of<TransactionManager>(context, listen: false);
    setState(() {
      _waybillId = transactionManager.waybillId;
      _referenceEmbedding = transactionManager.embedding;
    });
  }

  // --- Step 0: Barcode ---
  // Scanning handled by MobileScanner widget in build(); keep helper for future control
  void _startBarcodeDetection() {
    // No-op because MobileScanner widget drives scanning UI
  }

  // Called when barcode is scanned
  Future<void> _onBarcodeScanned() async {
    setState(() {
      _currentStep = 1;
      _instruction = "Verifying package...";
    });
    await _startPackageVerification();
  }

  // --- Step 1: Package Verification ---
  Future<void> _startPackageVerification() async {
    // Simulate verification delay
    await Future.delayed(Duration(seconds: 2));

    // Verify if scanned waybill matches reference
    bool isVerified = _scannedWaybillId == _waybillId;

    if (isVerified) {
      setState(() {
        _instruction = "Package verified. Track to locker.";
      });
      // Proceed to Step 2 after a short delay
      Timer(Duration(seconds: 1), () {
        if (mounted) _onPackageVerified();
      });
    } else {
      // Show error and reset to Step 0
      setState(() {
        _currentStep = 0;
        _instruction = "Verification failed. Scan barcode again.";
        _scannedWaybillId = null;
      });
      _startBarcodeDetection();
    }
  }

  // --- Transition Logic ---
  // Call this method when Step 1 (Verification) is complete
  Future<void> _onPackageVerified() async {
    setState(() {
      _currentStep = 2;
      _instruction = "Track package to locker";
    });
    await _startMotionTracking();
  }

  // --- Step 2 & 3: YOLO Tracking ---
  Future<void> _startMotionTracking() async {
    // 1. Stop existing stream if running
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }

    // Ensure YOLO model is loaded and log outcome before streaming frames
    try {
      debugPrint('NewLiveScreen: requesting YOLO model load before streaming');
      await TFLiteProcessor.loadYoloModel();
      debugPrint('NewLiveScreen: YOLO load request finished');
    } catch (e) {
      debugPrint('NewLiveScreen: Error loading YOLO model before streaming: $e');
    }

    // 2. Start new stream with YOLO logic
    bool isDetecting = false;
    // Process at most once every this interval (higher update rate -> more responsive)
    const processingInterval = Duration(milliseconds: 100);
    DateTime lastProcessed = DateTime.now().subtract(processingInterval);

    await _cameraController!.startImageStream((image) async {
      if (_currentStep != 2 && _currentStep != 3) return;

      // Throttling: skip if another processing is running or we processed too recently
      if (isDetecting) return;
      final now = DateTime.now();
      if (now.difference(lastProcessed) < processingInterval) return;

      isDetecting = true;
      lastProcessed = DateTime.now();

      try {
        final detections = await TFLiteProcessor.detectYoloOnFrame(image);

        // If user requested a capture, show the raw JSON in a dialog for inspection
        if (_captureNextFrame) {
          _captureNextFrame = false;
          final jsonStr = detections.isNotEmpty ? detections.toString() : '[]';
          if (mounted) {
            // showDialog must be called on the UI thread
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Captured Detections'),
                  content: SingleChildScrollView(child: Text(jsonStr)),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                  ],
                ),
              );
            });
          }
        }

        if (mounted) {
          _processDetections(detections, image.width, image.height);
        }
      } catch (e) {
        debugPrint("Error executing YOLO: $e");
      } finally {
        isDetecting = false;
      }
    });
  }

  void _processDetections(List<Map<String, dynamic>> detections, int imgW, int imgH) {
    // Debug log detections to help diagnose format/contents
    debugPrint('YOLO detections: count=${detections.length} imgW=$imgW imgH=$imgH');
    // Raw dump to help diagnose label/score/index mapping
    try {
      debugPrint('rawDetections: ${detections.map((d) => d.toString()).toList()}');
    } catch (_) {}

    // Keep a copy for the on-screen debug overlay (limit to 8 entries)
    try {
      _lastDetections = detections.map((d) => Map<String, dynamic>.from(d)).toList();
      if (_lastDetections.length > 8) _lastDetections = _lastDetections.sublist(0, 8);
    } catch (_) {
      _lastDetections = [];
    }

    // Build render-ready boxes for overlay (Rect in image pixels), label and confidence
    _lastRenderBoxes = [];

    // Canonical label sets and confidence threshold for this model
    // Only treat the exact 'package' model label as a package detection.
    final Set<String> packageLabels = {'package'};
    final Set<String> lockerLabels = {'locker'};
    const double minConfidence = 0.45; // tune if needed

    Rect? rectFromBoxRaw(dynamic boxRaw) {
      double x1 = 0, y1 = 0, x2 = 0, y2 = 0;
      try {
        if (boxRaw is List && boxRaw.length >= 4) {
          final v0 = (boxRaw[0] as num).toDouble();
          final v1 = (boxRaw[1] as num).toDouble();
          final v2 = (boxRaw[2] as num).toDouble();
          final v3 = (boxRaw[3] as num).toDouble();
          final allNormalized = v0 <= 1.01 && v1 <= 1.01 && v2 <= 1.01 && v3 <= 1.01;
          if (allNormalized) {
            // assume [cx,cy,w,h] normalized
            final cx = v0 * imgW;
            final cy = v1 * imgH;
            final w = v2 * imgW;
            final h = v3 * imgH;
            x1 = cx - w / 2;
            y1 = cy - h / 2;
            x2 = cx + w / 2;
            y2 = cy + h / 2;
          } else {
            // assume pixel coords
            x1 = v0;
            y1 = v1;
            x2 = v2;
            y2 = v3;
          }
        } else if (boxRaw is Map) {
          if (boxRaw.containsKey('x') && boxRaw.containsKey('y') && boxRaw.containsKey('w') && boxRaw.containsKey('h')) {
            final cx = (boxRaw['x'] as num).toDouble() * imgW;
            final cy = (boxRaw['y'] as num).toDouble() * imgH;
            final w = (boxRaw['w'] as num).toDouble() * imgW;
            final h = (boxRaw['h'] as num).toDouble() * imgH;
            x1 = cx - w / 2;
            y1 = cy - h / 2;
            x2 = cx + w / 2;
            y2 = cy + h / 2;
          } else if (boxRaw.containsKey('left') && boxRaw.containsKey('top') && boxRaw.containsKey('right') && boxRaw.containsKey('bottom')) {
            x1 = (boxRaw['left'] as num).toDouble();
            y1 = (boxRaw['top'] as num).toDouble();
            x2 = (boxRaw['right'] as num).toDouble();
            y2 = (boxRaw['bottom'] as num).toDouble();
          }
        }
      } catch (e) {
        debugPrint('rectFromBoxRaw parse error: $e');
      }

      return Rect.fromLTRB(x1.clamp(0.0, imgW.toDouble()), y1.clamp(0.0, imgH.toDouble()), x2.clamp(0.0, imgW.toDouble()), y2.clamp(0.0, imgH.toDouble()));
    }

    // Build render-ready boxes for ALL detections (so UI overlay shows everything)
    _detectedAny = false;
    _detectedAnyLabel = null;
    _detectedAnyConfidence = null;
    try {
      // Heuristics to reduce false positives (e.g., cables or tiny noise)
      const double minAreaRatio = 0.02; // detection area must be >= 2% of frame
      const double minAspect = 0.25; // width/height or height/width must be >= 0.25
      const double maxAspect = 4.0; // avoid extremely long thin boxes

      for (final d in detections) {
        final rawLabel = d['model_label'] ?? d['tag'] ?? d['label'] ?? d['name'] ?? d['class'];
        final label = rawLabel?.toString() ?? 'unknown';
        double? conf;
        try {
          if (d['box'] is List && (d['box'] as List).length > 4) conf = (d['box'][4] as num).toDouble();
          if (conf == null && d.containsKey('score')) conf = (d['score'] as num).toDouble();
        } catch (_) {
          conf = null;
        }

        final r = rectFromBoxRaw(d['box']);
        final area = (r?.width ?? 0.0) * (r?.height ?? 0.0);
        final frameArea = imgW * imgH;
        final areaRatio = frameArea > 0 ? (area / frameArea) : 0.0;
        final aspect = (r?.width ?? 0.0) > 0 && (r?.height ?? 0.0) > 0 ? ((r?.width ?? 0.0) / (r?.height ?? 0.0)) : 1.0;
        final aspectNorm = aspect >= 1.0 ? aspect : 1.0 / aspect; // treat tall/long symmetrically

        final low = label.toLowerCase().trim();
        final bool isPackageModel = packageLabels.contains(low);

        // Decide whether this detection should be considered a valid "package"
        final bool passesSize = areaRatio >= minAreaRatio;
        final bool passesAspect = aspectNorm >= minAspect && aspectNorm <= maxAspect;
        final bool isValidPackage = isPackageModel && (conf ?? 0.0) >= minConfidence && passesSize && passesAspect;

        _lastRenderBoxes.add({'rect': r, 'label': label, 'confidence': conf, 'is_package': isValidPackage});

        // Only promote valid package detections to the top banner
        if (isValidPackage) {
          final double c = conf ?? 0.0;
          if (!_detectedAny || (_detectedAnyConfidence != null && c > (_detectedAnyConfidence ?? 0.0))) {
            _detectedAny = true;
            _detectedAnyLabel = label;
            _detectedAnyConfidence = c;
          }
        }
      }
    } catch (e) {
      debugPrint('Error building render boxes: $e');
    }

    // Expire package-detected state if it exceeded the timeout
    if (_packageDetected && _packageDetectedAt != null) {
      final now = DateTime.now();
      if (now.difference(_packageDetectedAt!) > packageToLockerTimeout) {
        _packageDetected = false;
        _packageDetectedAt = null;
      }
    }

    // 1. Look for Package (Step 2)
    if (_currentStep == 2) {
      // Use validated render boxes (with is_package) to avoid re-parsing raw detections
      Map<String, dynamic>? validatedPackageBox;
      for (final rb in _lastRenderBoxes) {
        if (rb['is_package'] == true) {
          validatedPackageBox = rb;
          break;
        }
      }

      if (validatedPackageBox != null) {
        // we saw a candidate package in this frame
        _consecutivePackageFrames++;
      } else {
        _consecutivePackageFrames = 0;
      }

      if (_consecutivePackageFrames >= packageFrameThreshold && validatedPackageBox != null) {
        final Rect pkgRect = validatedPackageBox['rect'] as Rect? ?? Rect.zero;
        final double? conf = validatedPackageBox['confidence'] as double?;
        final String? packageLabel = (validatedPackageBox['label'] as String?) ?? 'package';

        setState(() {
          _packageBox = pkgRect;
          _smoothedBox = _smoothBox(pkgRect, _smoothedBox, 0.95);
          _trackedBox = _smoothedBox;
          _trackedLabel = packageLabel ?? _trackedLabel;
          _missCount = 0;
          _lastDetectionConfidence = conf;
          _lastDetectionTime = DateTime.now();
          _packageDetected = true;
          _packageDetectedAt = DateTime.now();
          debugPrint('NewLiveScreen: validated package detected -> $_trackedLabel conf=$conf frames=$_consecutivePackageFrames');
        });
      } else if (validatedPackageBox == null) {
        _handleTrackingMiss();
      }
    }

    // 2. Look for Locker (Step 3 Trigger)
    // We check for locker in both steps to allow transition
    // Look for locker label among detections (case-insensitive)
    // Also build render boxes list and try to find locker detection(s)
    Map<String, dynamic>? foundLocker;
    for (final d in detections) {
      final rawLabel = d['tag'] ?? d['label'] ?? d['name'] ?? d['class'];
      final label = rawLabel?.toString() ?? 'unknown';
      final low = label.toLowerCase().trim();
      double? conf;
      try {
        if (d['box'] is List && (d['box'] as List).length > 4) conf = (d['box'][4] as num).toDouble();
        if (conf == null && d.containsKey('score')) conf = (d['score'] as num).toDouble();
      } catch (_) {
        conf = null;
      }

      // rect already computed earlier when building render boxes

      // Use canonical locker labels and confidence threshold
      if (lockerLabels.contains(low) && (conf ?? 0.0) >= minConfidence) {
        foundLocker = d.cast<String, dynamic>();
      } else if ((conf ?? 0.0) >= 0.85 && low.contains('lock')) {
        // high-confidence heuristic for variants like 'locker_v1' etc.
        foundLocker = d.cast<String, dynamic>();
      }
    }

    if (foundLocker != null) {
      final lockerRect = rectFromBoxRaw(foundLocker['box']);
      setState(() {
        _lockerBox = lockerRect;
      });

      final now = DateTime.now();
      final packageFresh = _packageDetected && _packageDetectedAt != null && now.difference(_packageDetectedAt!) <= packageToLockerTimeout;

      // If we have both package and locker boxes, check overlap
      if (_packageBox != null) {
        final inter = _packageBox!.intersect(_lockerBox!);
        final interArea = (inter.width > 0 && inter.height > 0) ? inter.width * inter.height : 0.0;
        final pkgArea = _packageBox!.width * _packageBox!.height;
        final overlapRatio = pkgArea > 0 ? (interArea / pkgArea) : 0.0;

        debugPrint('Overlap ratio: $overlapRatio pkgArea=$pkgArea inter=$interArea');

        // If package is mostly inside locker (>=60%) and the package was seen recently, consider transaction complete
        if (overlapRatio >= 0.60 && packageFresh) {
          // Finalize transaction
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final tm = Provider.of<TransactionManager>(context, listen: false);
            final success = await tm.finalizeTransaction();
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Transaction Complete'),
                  content: Text(success ? 'Package placed and transaction finalized.' : 'Package placed but finalization failed.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                  ],
                ),
              );
            }
            // stop further processing (optional)
            try {
              await _cameraController?.stopImageStream();
            } catch (_) {}
          });
        } else {
          // If we transitioned earlier to step 3, keep instruction updated
          if (_currentStep == 2 && packageFresh) {
            setState(() {
              _currentStep = 3;
              _instruction = 'Locker detected. Place package inside.';
              debugPrint('NewLiveScreen: locker detected and transitioning to step 3');
            });
          }
        }
      } else {
        // No package box known; if locker seen and we previously had a package detection recently, transition to step 3
        if (_currentStep == 2 && packageFresh) {
          setState(() {
            _currentStep = 3;
            _instruction = 'Locker detected. Place package inside.';
            debugPrint('NewLiveScreen: locker detected and transitioning to step 3 (no packageBox)');
          });
        }
      }
    }
  }

  void _handleTrackingMiss() {
    _missCount++;
    final now = DateTime.now();
    final timeSinceLast = _lastDetectionTime == null ? Duration(days: 365) : now.difference(_lastDetectionTime!);

    // Clear more responsively: if we haven't seen a detection recently (~400ms)
    // OR the miss counter exceeds a modest threshold, then clear the tracked box.
    if (timeSinceLast > const Duration(milliseconds: 400) || _missCount > maxMisses) {
      setState(() {
        _trackedBox = null;
        _smoothedBox = null;
        // If we truly lost the package, clear package-detected state so the UI updates
        _packageDetected = false;
        _packageDetectedAt = null;
      });
    }
  }

  Rect _smoothBox(Rect newBox, Rect? oldBox, double alpha) {
    if (oldBox == null) return newBox;
    return Rect.fromLTRB(
      alpha * newBox.left + (1 - alpha) * oldBox.left,
      alpha * newBox.top + (1 - alpha) * oldBox.top,
      alpha * newBox.right + (1 - alpha) * oldBox.right,
      alpha * newBox.bottom + (1 - alpha) * oldBox.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    double scaleX = 1.0;
    double scaleY = 1.0;

    // Calculate Scale Factors based on screen vs camera preview size
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      final previewSize = _cameraController!.value.previewSize;
      // Note: Android often swaps width/height in portrait
      if (previewSize != null) {
        scaleX = screenSize.width / previewSize.height; 
        scaleY = screenSize.height / previewSize.width;
      }
    }

    // When step 0: show real barcode scanner using MobileScanner
    return Scaffold(
      appBar: AppBar(title: Text("Step $_currentStep: $_instruction")),
      body: _currentStep == 0
          ? Stack(
              fit: StackFit.expand,
              children: [
                // MobileScanner provides live barcode scanning UI
                MobileScanner(
                  controller: _barcodeController,
                  onDetect: (capture) async {
                    if (_barcodeDetected || _isProcessing) return;

                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isEmpty) return;

                    final barcode = barcodes.first;
                    if (barcode.rawValue == null) return;

                    setState(() {
                      _barcodeDetected = true;
                      _isProcessing = true;
                      _scannedWaybillId = barcode.rawValue;
                    });

                    debugPrint('📦 NewLiveScreen - Barcode scanned: $_scannedWaybillId');

                    // Give user feedback then initialize camera for next steps
                    await Future.delayed(const Duration(seconds: 1));
                    try {
                      await _barcodeController?.stop();
                    } catch (_) {}
                    await _initializeCamera();
                    if (mounted) {
                      setState(() {
                        _currentStep = 1;
                        _instruction = 'Verifying package...';
                        _isProcessing = false;
                      });
                      // proceed with verification flow
                      await _onBarcodeScanned();
                    }
                  },
                ),

                // Scanning frame overlay
                Center(
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _barcodeDetected ? Colors.green : Colors.white,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                // Top overlay with instructions and detection badge
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.black54,
                    child: SafeArea(
                      child: Column(
                        children: [
                          const Text(
                            'Step 1 of 3: Scan Barcode/QR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Position the barcode within the frame',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          if (_barcodeDetected) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Barcode Detected: ${_scannedWaybillId ?? ''}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : (_isCameraInitialized
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_cameraController!),

                    // Bounding Box Overlay: render all latest detection boxes with badges
                    for (final rb in _lastRenderBoxes)
                      Positioned(
                        left: ((rb['rect'] as Rect?)?.left ?? 0.0) * scaleX,
                        top: ((rb['rect'] as Rect?)?.top ?? 0.0) * scaleY,
                        width: ((rb['rect'] as Rect?)?.width ?? 0.0) * scaleX,
                        height: ((rb['rect'] as Rect?)?.height ?? 0.0) * scaleY,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: (rb['is_package'] == true)
                                  ? Colors.green
                                  : ((rb['label'] as String).toLowerCase().contains('locker') ? Colors.blue : Colors.yellow),
                              width: 3,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              color: (rb['is_package'] == true)
                                  ? Colors.green
                                  : ((rb['label'] as String).toLowerCase().contains('locker') ? Colors.blue : Colors.orange),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    (rb['label'] as String).toUpperCase(),
                                    style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  if (rb['confidence'] != null)
                                    Text(
                                      '${((rb['confidence'] as double) * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Package detection diagnostics (Step 2)
                    if (_currentStep == 2)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.black54,
                          child: SafeArea(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _packageDetected || _trackedBox != null ? Icons.check_circle : Icons.cancel,
                                  color: _packageDetected || _trackedBox != null ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _detectedAny
                                      ? 'Detected: ${_detectedAnyLabel ?? 'Unknown'} ${_detectedAnyConfidence != null ? '(${(_detectedAnyConfidence! * 100).toStringAsFixed(0)}%)' : ''}'
                                      : (_packageDetected
                                          ? 'Package detected — awaiting locker (${packageToLockerTimeout.inSeconds}s window)'
                                          : 'No object detected'),
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Diagnostics Overlay for Step 1
                    if (_currentStep == 1)
                      Positioned(
                        top: 50,
                        left: 20,
                        right: 20,
                        child: Container(
                          color: Colors.black.withOpacity(0.7),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scanned Waybill: ${_scannedWaybillId ?? "None"}',
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              Text(
                                'Reference Waybill: ${_waybillId ?? "None"}',
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              Text(
                                'Match: ${_scannedWaybillId == _waybillId ? "✓ YES" : "✗ NO"}',
                                style: TextStyle(
                                  color: _scannedWaybillId == _waybillId ? Colors.green : Colors.red,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Debug buttons removed for cleaner UI
                  ],
                )
              : const Center(child: CircularProgressIndicator())),
    );
  }
}
