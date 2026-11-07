import 'package:flutter/material.dart';

/// A draggable before/after comparison. The processed image is revealed from
/// the right side of the divider.
class BeforeAfterPreview extends StatefulWidget {
  const BeforeAfterPreview({
    super.key,
    required this.before,
    required this.after,
    required this.active,
  });

  final Widget before;
  final Widget after;
  final bool active;

  @override
  State<BeforeAfterPreview> createState() => _BeforeAfterPreviewState();
}

class _BeforeAfterPreviewState extends State<BeforeAfterPreview> {
  double _split = 0.5;

  @override
  void didUpdateWidget(covariant BeforeAfterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active && widget.active) {
      _split = 0.5;
    }
  }

  void _update(double dx, double width) {
    if (width <= 0) return;
    setState(() {
      _split = (dx / width).clamp(0.04, 0.96).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final dividerX = width * _split;
        final handleY = height.isFinite ? (height / 2 - 21) : 80.0;

        return Semantics(
          label: 'Before and after comparison',
          value: '${(_split * 100).round()} percent',
          increasedValue: '${((_split + 0.05) * 100).round()} percent',
          decreasedValue: '${((_split - 0.05) * 100).round()} percent',
          onIncrease: () => setState(() {
            _split = (_split + 0.05).clamp(0.04, 0.96);
          }),
          onDecrease: () => setState(() {
            _split = (_split - 0.05).clamp(0.04, 0.96);
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.active
                ? (details) => _update(details.localPosition.dx, width)
                : null,
            onHorizontalDragUpdate: widget.active
                ? (details) => _update(details.localPosition.dx, width)
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: widget.before),
                if (widget.active)
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _RightClipper(_split),
                      child: widget.after,
                    ),
                  ),
                if (widget.active) ...[
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _PreviewLabel(
                      text: 'BEFORE',
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _PreviewLabel(
                      text: 'AFTER',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Positioned(
                    left: dividerX - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  Positioned(
                    left: dividerX - 21,
                    top: handleY,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        size: 21,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _RightClipper extends CustomClipper<Rect> {
  _RightClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(size.width * fraction, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(covariant _RightClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}
