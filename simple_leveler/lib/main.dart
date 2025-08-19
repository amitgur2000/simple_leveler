import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const LevelApp());
}

class LevelApp extends StatelessWidget {
  const LevelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bubble Level',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0F12),
        useMaterial3: true,
      ),
      home: const LevelScreen(),
    );
  }
}

class LevelScreen extends StatefulWidget {
  const LevelScreen({super.key});

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen> {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // Smoothed accelerometer values (m/s^2)
  double _smoothedX = 0.0;
  double _smoothedY = 0.0;
  double _smoothedZ = 0.0;

  // Tuning constants
  static const double _smoothingFactor = 0.15; // 0..1 higher = snappier
  static const double _gClamp = 4.0; // g-range that maps to the edge
  static const double _standardGravity = 9.80665;

  // Displayed degree values (0..90), updated at a throttled cadence
  int _degX = 0;
  int _degY = 0;
  int _degZ = 0;

  Timer? _degreesTimer;

  @override
  void initState() {
    super.initState();
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      // Low-pass filter to smooth motion
      final nextX = event.x;
      final nextY = event.y;
      final nextZ = event.z;
      setState(() {
        _smoothedX = _smoothedX + (nextX - _smoothedX) * _smoothingFactor;
        _smoothedY = _smoothedY + (nextY - _smoothedY) * _smoothingFactor;
        _smoothedZ = _smoothedZ + (nextZ - _smoothedZ) * _smoothingFactor;
      });
    });

    _degreesTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final degX = _toDegrees(_smoothedX);
      final degY = _toDegrees(_smoothedY);
      final degZ = _toDegrees(_smoothedZ);
      if (degX != _degX || degY != _degY || degZ != _degZ) {
        setState(() {
          _degX = degX;
          _degY = degY;
          _degZ = degZ;
        });
      }
    });
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _degreesTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final isLandscape = screenSize.width > screenSize.height;

        // Swap X/Y when in landscape so UI axes match the screen orientation
        final effectiveSmoothedX = isLandscape ? _smoothedY : _smoothedX;
        final effectiveSmoothedY = isLandscape ? _smoothedX : _smoothedY;

        final effectiveDegX = isLandscape ? _degY : _degX;
        final effectiveDegY = isLandscape ? _degX : _degY;

        return Stack(
          children: [
            // Background crosshair covering the whole screen
            Positioned.fill(
              child: CustomPaint(
                painter: _CrosshairPainter(),
              ),
            ),

            // Circular level container with moving bubble
            Center(
              child: _LevelCircle(
                screenSize: screenSize,
                smoothedX: effectiveSmoothedX,
                smoothedY: effectiveSmoothedY,
                gClamp: _gClamp,
              ),
            ),

            // Top-left overlay with X/Y/Z degrees
            Positioned(
              top: 30,
              left: 50,
              child: _AxisDegreesOverlay(
                degX: effectiveDegX,
                degY: effectiveDegY,
                degZ: _degZ,
              ),
            ),
          ],
        );
      },
    );
  }
}

int _toDegrees(double component) {
  final ratio = (component.abs() / _LevelScreenState._standardGravity).clamp(0.0, 1.0);
  final radians = math.asin(ratio);
  final degrees = radians * 180.0 / math.pi;
  return degrees.round().clamp(0, 90);
}

class _AxisDegreesOverlay extends StatelessWidget {
  const _AxisDegreesOverlay({
    required this.degX,
    required this.degY,
    required this.degZ,
  });

  final int degX;
  final int degY;
  final int degZ;

  Color _statusColor(int deg) => deg == 0 ? const Color(0xFF4CAF50) : const Color(0xFFFFEB3B);

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final valueStyle = Theme.of(context).textTheme.titleMedium;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('X', style: labelStyle?.copyWith(color: Colors.redAccent)),
              const SizedBox(width: 8),
              Text('$degX°', style: valueStyle?.copyWith(color: _statusColor(degX))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Y', style: labelStyle?.copyWith(color: Colors.lightBlueAccent)),
              const SizedBox(width: 8),
              Text('$degY°', style: valueStyle?.copyWith(color: _statusColor(degY))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Z', style: labelStyle?.copyWith(color: Colors.purpleAccent)),
              const SizedBox(width: 8),
              Text('$degZ°', style: valueStyle?.copyWith(color: _statusColor(degZ))),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelCircle extends StatelessWidget {
  const _LevelCircle({
    required this.screenSize,
    required this.smoothedX,
    required this.smoothedY,
    required this.gClamp,
  });

  final Size screenSize;
  final double smoothedX;
  final double smoothedY;
  final double gClamp;

  @override
  Widget build(BuildContext context) {
    // Responsive sizing
    final diameter = math.min(screenSize.width, screenSize.height) * 0.9;
    final bubbleDiameter = diameter * 0.12;
    final radius = diameter / 2;
    final bubbleRadius = bubbleDiameter / 2;

    // Map accelerometer to bubble offset.
    // Invert axes so bubble moves toward the "high" side (like a real level).
    final isLandscape = screenSize.width > screenSize.height;
    final normalizedXRaw = ((smoothedX) / gClamp).clamp(-1.0, 1.0);
    final normalizedY = (-(smoothedY) / gClamp).clamp(-1.0, 1.0);
    final normalizedX = isLandscape ? -normalizedXRaw : normalizedXRaw;

    final maxOffset = radius - bubbleRadius;
    double dx = normalizedX * maxOffset;
    double dy = normalizedY * maxOffset;

    // Clamp inside the circle boundary
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance > maxOffset) {
      final scale = maxOffset / distance;
      dx *= scale;
      dy *= scale;
    }

    final isCentered = distance < bubbleRadius * 0.6;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer circular container
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF121418),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ],
            ),
          ),

          // Subtle target rings inside the level
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(diameter * 0.08),
              child: CustomPaint(
                painter: _RingsPainter(),
              ),
            ),
          ),

          // Bubble (translated from center)
          Transform.translate(
            offset: Offset(dx, dy),
            child: _Bubble(
              diameter: bubbleDiameter,
              isCentered: isCentered,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.diameter, required this.isCentered});

  final double diameter;
  final bool isCentered;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isCentered
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFEB3B);

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            bubbleColor.withOpacity(0.95),
            bubbleColor.withOpacity(0.7),
            bubbleColor.withOpacity(0.4),
          ],
          stops: const [0.5, 0.8, 1.0],
        ),
        border: Border.all(
          color: isCentered ? const Color(0xFF69F0AE) : Colors.white70,
          width: isCentered ? 3 : 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 1),
        ],
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1.2;

    // Horizontal line
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    // Vertical line
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white12;

    // Draw 3 inner rings for reference
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
