part of 'app.dart';

// A separate paint layer only ticks while particles are alive. No widget rebuilds
// or permanent animation loop are needed for the original pointer effect.
class NativeTrail extends StatefulWidget {
  const NativeTrail({super.key, required this.prefs, required this.child});
  final NativePreferences prefs;
  final Widget child;
  @override
  State<NativeTrail> createState() => _NativeTrailState();
}

class _NativeTrailState extends State<NativeTrail>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final particles = <_Particle>[];
  final repaint = ValueNotifier<int>(0);
  final random = math.Random();
  late final Ticker ticker = createTicker(tick);
  Duration last = Duration.zero;
  Offset? previous;
  bool resumed = true;
  bool get enabled =>
      resumed &&
      widget.prefs.values['trail'] != false &&
      !MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (!resumed) clear();
  }

  @override
  void didUpdateWidget(NativeTrail old) {
    super.didUpdateWidget(old);
    if (widget.prefs.values['trail'] == false) clear();
  }

  void clear() {
    ticker.stop();
    particles.clear();
    previous = null;
    repaint.value++;
  }

  void add(Offset point) {
    if (!enabled) return;
    if (previous != null && (previous! - point).distance < 3) return;
    previous = point;
    final fluid = widget.prefs.values['trailType'] == 'fluid';
    const colors = [
      Color(0xff3b82f6),
      Color(0xff10b981),
      Colors.white,
      Color(0xff818cf8),
    ];
    for (var i = 0; i < 3; i++) {
      final angle = random.nextDouble() * math.pi * 2,
          speed = fluid
              ? 30 + random.nextDouble() * 120
              : 10 + random.nextDouble() * 20;
      particles.add(
        _Particle(
          point,
          Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          fluid
              ? const Color(0xff3b82f6)
              : colors[random.nextInt(colors.length)],
          fluid ? 1 + random.nextDouble() * 2 : .5 + random.nextDouble() * 1.2,
          fluid,
        ),
      );
    }
    if (particles.length > 96) particles.removeRange(0, particles.length - 96);
    if (!ticker.isActive) {
      last = Duration.zero;
      ticker.start();
    }
    repaint.value++;
  }

  void tick(Duration time) {
    final double dt = last == Duration.zero
        ? 1 / 60
        : ((time - last).inMicroseconds / 1e6).clamp(0, .05).toDouble();
    last = time;
    for (final p in particles) {
      p.life -= dt;
      p.point += p.velocity * dt;
      if (p.fluid) p.velocity += Offset(0, -280 * dt);
    }
    particles.removeWhere((p) => p.life <= 0);
    repaint.value++;
    if (particles.isEmpty) {
      ticker.stop();
      previous = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) => add(e.localPosition),
    onPointerMove: (e) => add(e.localPosition),
    onPointerHover: (e) => add(e.localPosition),
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _TrailPaint(particles, repaint)),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Particle {
  _Particle(this.point, this.velocity, this.color, this.size, this.fluid);
  Offset point, velocity;
  final Color color;
  final double size;
  final bool fluid;
  double life = .7;
}

class _TrailPaint extends CustomPainter {
  _TrailPaint(this.particles, Listenable repaint) : super(repaint: repaint);
  final List<_Particle> particles;
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: (p.life / .7 * .6).clamp(0, 1));
      if (p.fluid) {
        paint
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p.point, p.point - p.velocity * .025, paint);
      } else {
        canvas.drawCircle(
          p.point,
          p.size * 2,
          Paint()
            ..color = paint.color.withValues(alpha: paint.color.a * .25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(p.point, p.size, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPaint old) => old.particles != particles;
}
