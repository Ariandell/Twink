part of 'app.dart';

enum GlassKind { panel, profile, navigation, card, overlay }

class _LiquidExpansion extends StatelessWidget {
  const _LiquidExpansion({required this.open, required this.child});
  final bool open;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    const curve = Cubic(.16, 1, .3, 1);
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: open ? 1 : 0, end: open ? 1 : 0),
        duration: Duration(milliseconds: reduce ? 0 : 800),
        curve: curve,
        child: IgnorePointer(
          ignoring: !open,
          child: ExcludeSemantics(
            excluding: !open,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: Duration(milliseconds: reduce ? 0 : 600),
              curve: curve,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: open ? 1 : 0, end: open ? 1 : 0),
                duration: Duration(milliseconds: reduce ? 0 : 700),
                curve: curve,
                child: child,
                builder: (context, t, body) => Transform.translate(
                  offset: Offset(0, -15 * (1 - t)),
                  child: Transform.scale(scale: .97 + .03 * t, child: body),
                ),
              ),
            ),
          ),
        ),
        builder: (context, t, body) => Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: Offstage(offstage: t == 0, child: body),
        ),
      ),
    );
  }
}

/// The original material: a transparent surface, dark depth, diagonal glare,
/// a bright upper rim and a soft shadow. Only explicit frosted surfaces sample
/// the backdrop; dictionary rows never allocate a blur layer.
class NativeGlass extends StatelessWidget {
  const NativeGlass({
    super.key,
    required this.child,
    this.kind = GlassKind.panel,
    this.radius = 20,
    this.blur = 0,
    this.grouped = false,
    this.gradient,
    this.borderColor,
  });
  final Widget child;
  final GlassKind kind;
  final double radius, blur;
  final bool grouped;
  final Gradient? gradient;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final polished = kind == GlassKind.profile || kind == GlassKind.navigation;
    final fg = ink(context);
    final fill =
        gradient ??
        (polished
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, .5, 1],
                colors: light
                    ? [
                        Colors.white.withValues(alpha: .62),
                        Colors.white.withValues(alpha: .32),
                        Colors.white.withValues(alpha: .5),
                      ]
                    : [
                        Colors.white.withValues(alpha: .05),
                        Colors.black.withValues(alpha: .15),
                        Colors.black.withValues(alpha: .55),
                      ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [fg.withValues(alpha: .03), fg.withValues(alpha: .02)],
              ));
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(gradient: fill),
      child: CustomPaint(
        painter: polished ? _GlassGlare(light) : null,
        foregroundPainter: _GlassRim(radius, light, polished, borderColor),
        child: child,
      ),
    );
    if (blur > 0) {
      final filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
      surface = grouped
          ? BackdropFilter.grouped(filter: filter, child: surface)
          : BackdropFilter(filter: filter, child: surface);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (polished)
            BoxShadow(
              color: Colors.black.withValues(alpha: light ? .08 : .3),
              blurRadius: kind == GlassKind.navigation ? 40 : 32,
              offset: const Offset(0, 8),
            ),
          if (kind == GlassKind.card)
            BoxShadow(
              color: Colors.black.withValues(alpha: light ? .1 : .5),
              blurRadius: 30,
              offset: const Offset(0, 10),
              spreadRadius: -10,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: surface,
      ),
    );
  }
}

class _GlassGlare extends CustomPainter {
  const _GlassGlare(this.light);
  final bool light;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.skew(-.364, 0);
    final rect = Rect.fromLTWH(
      -size.width * .25,
      0,
      size.width * 1.6,
      size.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: light ? .16 : .07),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassGlare old) => old.light != light;
}

class _GlassRim extends CustomPainter {
  const _GlassRim(this.radius, this.light, this.polished, this.borderColor);
  final double radius;
  final bool light, polished;
  final Color? borderColor;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.65),
        round = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final base =
        borderColor ??
        (light
            ? Colors.black.withValues(alpha: .1)
            : Colors.white.withValues(alpha: .2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (polished) {
      paint
        ..strokeWidth = 1.3
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            light
                ? Colors.white.withValues(alpha: .85)
                : Colors.white.withValues(alpha: .5),
            base,
            light
                ? Colors.black.withValues(alpha: .12)
                : Colors.black.withValues(alpha: .35),
          ],
          stops: const [0, .35, 1],
        ).createShader(rect);
    } else {
      paint.color = base;
    }
    canvas.drawRRect(round, paint);
  }

  @override
  bool shouldRepaint(_GlassRim old) =>
      old.radius != radius ||
      old.light != light ||
      old.polished != polished ||
      old.borderColor != borderColor;
}

BoxDecoration activeNavigationDecoration(BuildContext context) {
  final fg = ink(context),
      light = Theme.of(context).brightness == Brightness.light;
  return BoxDecoration(
    color: fg,
    borderRadius: BorderRadius.circular(99),
    border: Border.all(color: fg.withValues(alpha: .4), width: 2),
    boxShadow: [
      BoxShadow(
        color: fg.withValues(alpha: light ? .15 : .3),
        blurRadius: 15,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class GlassNavigation extends StatelessWidget {
  const GlassNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.wide = false,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    const names = ['Профиль', 'Учить', 'Словарь', 'Импорт', 'Настройки'];
    const icons = ['user', 'play', 'book', 'upload', 'settings'];
    final order = wide ? [0, 1, 2, 3, 4] : [0, 2, 1, 3, 4], fg = ink(context);
    Widget symbol(int i, Color color) => Center(
      child: wide
          ? label(
              names[i],
              size: 14,
              weight: selected == i ? FontWeight.w700 : FontWeight.w500,
              color: color,
            )
          : Glyph(icons[i], size: 18, color: color),
    );
    final base = Row(
      children: [
        for (final i in order)
          Expanded(
            child: Tap(
              label: names[i],
              onTap: () => onSelect(i),
              child: symbol(i, fg.withValues(alpha: .8)),
            ),
          ),
      ],
    );
    final inverted = ExcludeSemantics(
      child: Row(
        children: [
          for (final i in order)
            Expanded(
              child: symbol(i, Theme.of(context).scaffoldBackgroundColor),
            ),
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 700 : 450),
        child: NativeGlass(
          kind: GlassKind.navigation,
          radius: 99,
          blur: 25,
          child: SizedBox(
            height: wide ? 70 : 56,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(
                builder: (context, c) {
                  final width = c.maxWidth / 5,
                      target = order.indexOf(selected) * width;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: target, end: target),
                    duration: Duration(
                      milliseconds: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 500,
                    ),
                    curve: const Cubic(.23, 1, .32, 1),
                    child: base,
                    builder: (context, left, buttons) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          key: const ValueKey('liquid-navigation-indicator'),
                          left: left,
                          top: 0,
                          bottom: 0,
                          width: width,
                          child: DecoratedBox(
                            decoration: activeNavigationDecoration(context),
                          ),
                        ),
                        buttons!,
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipPath(
                              clipper: _NavigationLens(left, width),
                              child: inverted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationLens extends CustomClipper<Path> {
  const _NavigationLens(this.left, this.width);
  final double left, width;
  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, width, size.height),
        const Radius.circular(99),
      ),
    );
  @override
  bool shouldReclip(_NavigationLens old) =>
      old.left != left || old.width != width;
}
