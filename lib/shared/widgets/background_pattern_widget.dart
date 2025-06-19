import 'package:flutter/material.dart';

class BackgroundPatternWidget extends StatelessWidget {
  final Widget? child;
  final Color? patternColor;
  final double spacing;
  final double dotSize;

  const BackgroundPatternWidget({
    super.key,
    this.child,
    this.patternColor,
    this.spacing = 60.0,
    this.dotSize = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景圖案
        Positioned.fill(
          child: CustomPaint(
            painter: BackgroundPatternPainter(
              color: patternColor ?? Colors.white.withOpacity(0.05),
              spacing: spacing,
              dotSize: dotSize,
            ),
          ),
        ),
        // 前景內容
        if (child != null) child!,
      ],
    );
  }
}

class BackgroundPatternPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double dotSize;

  BackgroundPatternPainter({
    required this.color,
    this.spacing = 60.0,
    this.dotSize = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 繪製幾何圖案
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize, paint);

        // 添加連接線
        if (x + spacing < size.width) {
          canvas.drawLine(
            Offset(x + dotSize, y),
            Offset(x + spacing - dotSize, y),
            paint..strokeWidth = 0.5,
          );
        }
        if (y + spacing < size.height) {
          canvas.drawLine(
            Offset(x, y + dotSize),
            Offset(x, y + spacing - dotSize),
            paint..strokeWidth = 0.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is BackgroundPatternPainter &&
        (oldDelegate.color != color ||
         oldDelegate.spacing != spacing ||
         oldDelegate.dotSize != dotSize);
  }
} 