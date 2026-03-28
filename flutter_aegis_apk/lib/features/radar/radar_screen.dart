import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/mesh_provider.dart';

class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRadarSection(),
            const SizedBox(height: 32),
            _buildStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarSection() {
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                  blurRadius: 30,
                  spreadRadius: 10,
                )
              ]
            ),
          ),
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(250, 250),
                painter: RadarPainter(
                  animationValue: _animationController.value,
                  color: Theme.of(context).primaryColor,
                  peerCount: ref.watch(meshProvider).activePeers.length,
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Text(
              'RANGE: ~100m (MAX)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.memory, size: 12, color: Colors.white54),
                    SizedBox(width: 4),
                    Text('CPU LOAD', style: TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('24.8%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lock, size: 12, color: Colors.white54),
                    SizedBox(width: 4),
                    Text('VAULT', style: TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('LOCKED', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RadarPainter extends CustomPainter {
  final double animationValue;
  final Color color;
  final int peerCount;

  RadarPainter({required this.animationValue, required this.color, required this.peerCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * (i / 4), paint);
    }

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final angle = animationValue * 2 * pi;
    final sweepOffet = Offset(
      center.dx + maxRadius * cos(angle),
      center.dy + maxRadius * sin(angle),
    );
    canvas.drawLine(center, sweepOffet, linePaint);

    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    final gradientPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: angle - pi / 4,
        endAngle: angle,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.1),
          color.withValues(alpha: 0.3),
        ],
      ).createShader(sweepRect)
      ..style = PaintingStyle.fill;
      
    canvas.drawArc(
      sweepRect, 
      angle - pi/4, 
      pi/4, 
      true, 
      gradientPaint
    );

    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    final random = Random(42);
    for (int i = 0; i < peerCount; i++) {
      final r = maxRadius * (0.3 + 0.6 * random.nextDouble());
      final a = 2 * pi * random.nextDouble();
      
      final dotOffset = Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      
      double angleDiff = (angle - a) % (2 * pi);
      if (angleDiff < 0) angleDiff += 2 * pi;
      
      double dotOpacity = 1.0;
      if (angleDiff < pi/2) {
         dotOpacity = 1.0 - (angleDiff / (pi/2));
      } else {
         dotOpacity = 0.2;
      }
      
      dotPaint.color = color.withValues(alpha: dotOpacity);
      canvas.drawCircle(dotOffset, 3.0, dotPaint);
      
      if (dotOpacity > 0.5) {
         final glowPaint = Paint()..color = color.withValues(alpha: dotOpacity * 0.5)..style = PaintingStyle.fill;
         canvas.drawCircle(dotOffset, 8.0, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
