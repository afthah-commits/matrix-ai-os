import 'package:flutter/material.dart';

/// Reusable vector-drawn Matrix AI OS Brand Identity Emblem.
/// Features a futuristic Neural Shield and Geometric 'M' Core
/// rendered via custom canvas vector paths in neon emerald & electric cyan.
class MatrixLogoWidget extends StatelessWidget {
  final double size;
  final bool withGlow;
  final bool withBackground;
  final BorderRadius? borderRadius;

  const MatrixLogoWidget({
    super.key,
    this.size = 32.0,
    this.withGlow = true,
    this.withBackground = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    const primaryEmerald = Color(0xFF10B981);
    const neonCyan = Color(0xFF06B6D4);
    const deepObsidian = Color(0xFF090D16);

    final widgetRadius = borderRadius ?? BorderRadius.circular(size * 0.28);

    final emblem = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MatrixLogoPainter(),
        size: Size(size, size),
      ),
    );

    if (!withBackground) {
      return RepaintBoundary(child: emblem);
    }

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: deepObsidian,
          borderRadius: widgetRadius,
          border: Border.all(
            color: primaryEmerald.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: withGlow
              ? [
                  BoxShadow(
                    color: primaryEmerald.withValues(alpha: 0.22),
                    blurRadius: size * 0.35,
                    spreadRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                  BoxShadow(
                    color: neonCyan.withValues(alpha: 0.15),
                    blurRadius: size * 0.2,
                    spreadRadius: 0,
                    offset: const Offset(0, 0),
                  ),
                ]
              : null,
        ),
        padding: EdgeInsets.all(size * 0.12),
        child: CustomPaint(
          painter: _MatrixLogoPainter(),
        ),
      ),
    );
  }
}

class _MatrixLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Scaling helpers: map coordinate space [0, 100] to canvas [w, h]
    double sx(double x) => (x / 100.0) * w;
    double sy(double y) => (y / 100.0) * h;

    final emeraldPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cyanPaint = Paint()
      ..color = const Color(0xFF06B6D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shieldOutlinePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shieldFillPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // 1. Outer Faceted Hex Shield
    final shieldPath = Path()
      ..moveTo(sx(50), sy(8))
      ..lineTo(sx(88), sy(28))
      ..lineTo(sx(88), sy(72))
      ..lineTo(sx(50), sy(92))
      ..lineTo(sx(12), sy(72))
      ..lineTo(sx(12), sy(28))
      ..close();

    canvas.drawPath(shieldPath, shieldFillPaint);
    canvas.drawPath(shieldPath, shieldOutlinePaint);

    // 2. Inner Cyber Hex Accent
    final innerAccentPaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02;

    final innerPath = Path()
      ..moveTo(sx(50), sy(15))
      ..lineTo(sx(82), sy(32))
      ..lineTo(sx(82), sy(68))
      ..lineTo(sx(50), sy(85))
      ..lineTo(sx(18), sy(68))
      ..lineTo(sx(18), sy(32))
      ..close();
    canvas.drawPath(innerPath, innerAccentPaint);

    // 3. Geometric 'M' Core: Left Wing (Electric Cyan)
    final leftWingPath = Path()
      ..moveTo(sx(30), sy(72))
      ..lineTo(sx(30), sy(36))
      ..lineTo(sx(50), sy(54));
    canvas.drawPath(leftWingPath, cyanPaint);

    // 4. Geometric 'M' Core: Right Wing (Neon Emerald)
    final rightWingPath = Path()
      ..moveTo(sx(50), sy(54))
      ..lineTo(sx(70), sy(36))
      ..lineTo(sx(70), sy(72));
    canvas.drawPath(rightWingPath, emeraldPaint);

    // 5. Central Neural Focus Diamond (Bright Electric Cyan)
    final centerDiamondPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.fill;

    final diamondPath = Path()
      ..moveTo(sx(50), sy(48))
      ..lineTo(sx(55), sy(54))
      ..lineTo(sx(50), sy(60))
      ..lineTo(sx(45), sy(54))
      ..close();
    canvas.drawPath(diamondPath, centerDiamondPaint);

    // 6. Neural Crest Diamond (Neon Emerald)
    final crestDiamondPaint = Paint()
      ..color = const Color(0xFF34D399)
      ..style = PaintingStyle.fill;

    final crestPath = Path()
      ..moveTo(sx(50), sy(20))
      ..lineTo(sx(54), sy(24))
      ..lineTo(sx(50), sy(28))
      ..lineTo(sx(46), sy(24))
      ..close();
    canvas.drawPath(crestPath, crestDiamondPaint);

    // 7. Micro Neural Vertex Nodes
    final nodePaintCyan = Paint()
      ..color = const Color(0xFF06B6D4)
      ..style = PaintingStyle.fill;

    final nodePaintEmerald = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;

    final nodeRadius = w * 0.038;
    canvas.drawCircle(Offset(sx(30), sy(36)), nodeRadius, nodePaintCyan);
    canvas.drawCircle(Offset(sx(70), sy(36)), nodeRadius, nodePaintEmerald);
    canvas.drawCircle(Offset(sx(50), sy(92)), nodeRadius * 0.8, nodePaintCyan);
  }

  @override
  bool shouldRepaint(covariant _MatrixLogoPainter oldDelegate) => false;
}
