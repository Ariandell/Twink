part of 'app.dart';

Color _stickerPaperColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff08080b)
    : const Color(0xfff8f8fa);

class _StickerPictures {
  static Future<Map<String, List<String>>>? _loading;
  static String normalize(String word) =>
      word.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static Future<Map<String, List<String>>> load() => _loading ??= _load();
  static Future<Map<String, List<String>>> _load() async {
    try {
      return await compute(
        _decodeStickerPictures,
        await rootBundle.loadString('assets/word-images/lookup.json'),
      );
    } catch (_) {
      return {};
    }
  }
}

Map<String, List<String>> _decodeStickerPictures(String source) =>
    asMap(jsonDecode(source)).map(
      (word, ids) => MapEntry(word, [
        for (final id in ids as List)
          if (id is int && id > 0) 'assets/word-images/images/$id.webp',
      ]),
    );

class _PeelStep {
  const _PeelStep(this.corner, this.direction);
  final Offset corner, direction;
}

class _StickerPan extends PanGestureRecognizer {
  bool Function(Offset)? accepts;
  Offset origin = Offset.zero;
  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (accepts?.call(event.localPosition) != true) return;
    origin = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && (event.position - origin).distance > 3) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }
}

/// A word is the top sticker; each illustration is the next physical layer.
class StickerDeck extends StatefulWidget {
  static Future<void> preloadPictures() async {
    await _StickerPictures.load();
  }

  const StickerDeck({
    super.key,
    required this.contentId,
    required this.images,
    required this.height,
    required this.child,
    required this.onMotionStart,
    required this.onMotionEnd,
  });
  final String contentId;
  final List<String> images;
  final double height;
  final Widget child;
  final VoidCallback onMotionStart, onMotionEnd;
  @override
  State<StickerDeck> createState() => _StickerDeckState();
}

class _StickerDeckState extends State<StickerDeck>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  final steps = <_PeelStep>[];
  int page = 0, target = 0;
  bool dragging = false, active = false, undo = false;
  Offset down = Offset.zero,
      delta = Offset.zero,
      corner = Offset.zero,
      axis = Offset.zero;
  double travel = 1;
  int get count => widget.images.length + 1;
  void _warmImages() {
    for (final asset in widget.images.skip(page).take(2)) {
      precacheImage(
        ResizeImage(AssetImage(asset), width: 800),
        context,
        onError: (_, _) {},
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmImages();
  }

  @override
  void didUpdateWidget(StickerDeck old) {
    super.didUpdateWidget(old);
    if (widget.contentId != old.contentId ||
        !listEquals(widget.images, old.images)) {
      _warmImages();
    }
    if (widget.contentId != old.contentId) {
      final wasActive = active;
      controller.stop();
      page = target = 0;
      steps.clear();
      active = dragging = false;
      controller.value = 0;
      if (wasActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onMotionEnd();
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void begin(DragStartDetails details, Size size) {
    if (controller.isAnimating || widget.images.isEmpty) return;
    final nearX = math.min(down.dx, size.width - down.dx);
    final nearY = math.min(down.dy, size.height - down.dy);
    // Preserve scrolling long examples through the centre of the word face.
    if (page == 0 && (nearX > 72 || nearY > 72)) return;
    dragging = true;
    delta = Offset.zero;
    active = false;
    corner = Offset(
      down.dx < size.width / 2 ? 0 : 1,
      down.dy < size.height / 2 ? 0 : 1,
    );
    travel = math.min(size.width, size.height) * .7;
  }

  void update(DragUpdateDetails details) {
    if (!dragging) return;
    delta += details.delta;
    if (!active && delta.distance > 5) {
      axis = delta / delta.distance;
      undo =
          page > 0 &&
          steps.isNotEmpty &&
          delta.dx * steps.last.direction.dx +
                  delta.dy * steps.last.direction.dy <
              0;
      if (undo) corner = steps.last.corner;
      target = undo ? page - 1 : (page + 1) % count;
      active = true;
      widget.onMotionStart();
    }
    if (!active) return;
    final amount = ((delta.dx * axis.dx + delta.dy * axis.dy) / travel).clamp(
      0.0,
      1.0,
    );
    setState(() => controller.value = undo ? 1 - amount : amount);
  }

  Future<void> finish({bool cancel = false}) async {
    if (!dragging) return;
    dragging = false;
    if (!active) return;
    final contentId = widget.contentId;
    final amount = undo ? 1 - controller.value : controller.value;
    final commit = !cancel && amount > .22;
    final end = commit ? (undo ? 0.0 : 1.0) : (undo ? 1.0 : 0.0);
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = end;
    } else {
      await controller
          .animateTo(end, curve: Curves.easeOutCubic)
          .orCancel
          .catchError((_) {});
    }
    if (!mounted || widget.contentId != contentId) return;
    setState(() {
      if (commit) {
        if (undo) {
          steps.removeLast();
        } else if (target == 0) {
          steps.clear();
        } else {
          steps.add(_PeelStep(corner, delta));
        }
        page = target;
      }
      active = false;
      controller.value = 0;
    });
    _warmImages();
    widget.onMotionEnd();
  }

  Widget layer(int index) {
    if (index == 0) return widget.child;
    return Surface(
      radius: 24,
      background: _stickerPaperColor(context),
      padding: const EdgeInsets.all(16),
      glass: GlassKind.card,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                widget.images[index - 1],
                fit: BoxFit.contain,
                cacheWidth: 800,
                errorBuilder: (_, _, _) => Center(
                  child: label('Изображение недоступно', color: muted(context)),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: label(
                '$index / ${widget.images.length}',
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Square(
              'back',
              tooltip: 'Вернуться к слову',
              border: false,
              onTap: () => setState(() {
                page = 0;
                steps.clear();
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = active && undo ? target : page,
        bottom = active && undo ? page : target;
    return LayoutBuilder(
      builder: (context, c) => Listener(
        onPointerCancel: (_) => finish(cancel: true),
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            _StickerPan: GestureRecognizerFactoryWithHandlers<_StickerPan>(
              () => _StickerPan(),
              (pan) {
                pan.dragStartBehavior = DragStartBehavior.down;
                pan.accepts = (p) =>
                    widget.images.isNotEmpty &&
                    !controller.isAnimating &&
                    (page > 0 ||
                        (math.min(p.dx, c.maxWidth - p.dx) <= 72 &&
                            math.min(p.dy, widget.height - p.dy) <= 72));
                pan.onDown = (d) => down = d.localPosition;
                pan.onStart = (d) => begin(d, Size(c.maxWidth, widget.height));
                pan.onUpdate = update;
                pan.onEnd = (_) => finish();
                pan.onCancel = () => finish(cancel: true);
              },
            ),
          },
          child: SizedBox(
            height: widget.height,
            child: ClipRRect(
              clipBehavior: widget.images.isEmpty ? Clip.none : Clip.antiAlias,
              borderRadius: BorderRadius.circular(24),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    if (active)
                      RepaintBoundary(
                        key: const ValueKey('sticker-under'),
                        child: ColoredBox(
                          color: _stickerPaperColor(context),
                          child: layer(bottom),
                        ),
                      ),
                    ClipPath(
                      key: const ValueKey('sticker-top'),
                      clipper: _StickerClipper(
                        corner,
                        active ? controller.value : 0,
                      ),
                      child: RepaintBoundary(
                        child: ColoredBox(
                          color: active
                              ? _stickerPaperColor(context)
                              : Colors.transparent,
                          child: layer(top),
                        ),
                      ),
                    ),
                    if (active)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _StickerFold(corner, controller.value),
                        ),
                      ),
                    if (!active && page == 0 && widget.images.isNotEmpty)
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: IgnorePointer(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Glyph('image', size: 15, color: muted(context)),
                              const SizedBox(width: 5),
                              label(
                                '${widget.images.length}',
                                size: 11,
                                color: muted(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<Offset> _peelPolygon(Size size, Offset corner, double cut) {
  final points = [
    Offset.zero,
    Offset(size.width, 0),
    Offset(size.width, size.height),
    Offset(0, size.height),
  ];
  double side(Offset p) =>
      (corner.dx == 0 ? p.dx : size.width - p.dx) +
      (corner.dy == 0 ? p.dy : size.height - p.dy) -
      cut;
  final out = <Offset>[];
  for (var i = 0; i < 4; i++) {
    final a = points[i], b = points[(i + 1) % 4], sa = side(a), sb = side(b);
    if (sa >= 0) out.add(a);
    if ((sa >= 0) != (sb >= 0)) out.add(Offset.lerp(a, b, sa / (sa - sb))!);
  }
  return out;
}

class _StickerClipper extends CustomClipper<Path> {
  const _StickerClipper(this.corner, this.progress);
  final Offset corner;
  final double progress;
  @override
  Path getClip(Size size) {
    if (progress <= 0) return Path()..addRect(Offset.zero & size);
    if (progress >= 1) return Path();
    return Path()..addPolygon(
      _peelPolygon(size, corner, progress * (size.width + size.height)),
      true,
    );
  }

  @override
  bool shouldReclip(_StickerClipper old) =>
      corner != old.corner || progress != old.progress;
}

class _StickerFold extends CustomPainter {
  const _StickerFold(this.corner, this.progress);
  final Offset corner;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final cut = progress * (size.width + size.height);
    Offset map(Offset p) => Offset(
      corner.dx == 0 ? p.dx : size.width - p.dx,
      corner.dy == 0 ? p.dy : size.height - p.dy,
    );
    final a = map(
      Offset(math.min(cut, size.width), math.max(0, cut - size.width)),
    );
    final b = map(
      Offset(math.max(0, cut - size.height), math.min(cut, size.height)),
    );
    final normal =
        Offset(corner.dx == 0 ? 1 : -1, corner.dy == 0 ? 1 : -1) / math.sqrt2;
    final width = 34 * math.sin(math.pi * progress);
    final middle = (a + b) / 2;
    final flap = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(
        middle.dx + normal.dx * width,
        middle.dy + normal.dy * width,
        b.dx,
        b.dy,
      )
      ..quadraticBezierTo(
        middle.dx - normal.dx * width * .65,
        middle.dy - normal.dy * width * .65,
        a.dx,
        a.dy,
      )
      ..close();
    canvas.drawShadow(flap, Colors.black.withValues(alpha: .7), 8, false);
    canvas.drawPath(
      flap,
      Paint()
        ..shader = ui.Gradient.linear(
          middle - normal * width,
          middle + normal * width,
          [
            const Color(0xff626773),
            const Color(0xffe8ebf0),
            const Color(0xff9ba2af),
          ],
          [0, .65, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_StickerFold old) =>
      corner != old.corner || progress != old.progress;
}
