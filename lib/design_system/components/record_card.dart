import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' as scheduler show TickerCanceled;

import 'publication_text_layout.dart';

/// The header always keeps its dimensions while only the continuation expands.
class RecordCard extends StatefulWidget {
  const RecordCard({
    required this.title,
    required this.body,
    required this.category,
    required this.icon,
    this.date,
    this.photo,
    this.location,
    this.showTime = false,
    super.key,
  });
  final String title, body, category;
  final IconData icon;
  final DateTime? date;
  final Widget? photo;
  final String? location;
  final bool showTime;
  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard>
    with
        SingleTickerProviderStateMixin<RecordCard>,
        AutomaticKeepAliveClientMixin<RecordCard> {
  late final AnimationController _motion;
  final _header = GlobalKey();
  final _detailsButton = GlobalKey();
  double _detailsHeight = 40;
  bool _expanded = false, _showDetails = false, _changing = false;
  @override
  bool get wantKeepAlive => _showDetails;
  ScrollPosition? _scroll;
  double? _anchorTop;
  bool _adjusting = false;
  Object? _previewLayout;
  PublicationTextLayout? _textLayout;
  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = _expanded ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  double? _top() {
    final box = _header.currentContext?.findRenderObject();
    return box is RenderBox && box.attached
        ? box.localToGlobal(Offset.zero).dy
        : null;
  }

  void _keepAnchor() {
    if (_adjusting || _anchorTop == null) return;
    _adjusting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adjusting = false;
      final scroll = _scroll;
      final top = _top();
      if (!mounted ||
          scroll == null ||
          top == null ||
          !scroll.hasContentDimensions ||
          _anchorTop == null)
        return;
      // A bottom-of-list shrink can otherwise clamp the scroll offset in one jump.
      if (scroll.isScrollingNotifier.value) {
        _anchorTop = null;
        return;
      }
      final correction = top - _anchorTop!;
      if (correction.abs() > .5 && !scroll.isScrollingNotifier.value) {
        final offset = (scroll.pixels + correction).clamp(
          scroll.minScrollExtent,
          scroll.maxScrollExtent,
        );
        if ((offset - scroll.pixels).abs() > .5)
          scroll.jumpTo(offset.toDouble());
      }
    });
  }

  Future<void> _toggle() async {
    if (_changing) return;
    _changing = true;
    try {
      final reduced = MediaQuery.disableAnimationsOf(context);
      if (_expanded && (_top() ?? 0) < 0 && _header.currentContext != null) {
        await Scrollable.ensureVisible(
          _header.currentContext!,
          alignment: 0,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        if (!mounted) return;
      }
      _scroll = Scrollable.maybeOf(context)?.position;
      _anchorTop = _top();
      if (!_expanded) {
        final button = _detailsButton.currentContext?.findRenderObject();
        if (button is RenderBox && button.hasSize) {
          _detailsHeight = button.size.height;
        }
      }
      setState(() {
        _expanded = !_expanded;
        if (_expanded) _showDetails = true;
      });
      updateKeepAlive();
      if (reduced) {
        _motion.value = _expanded ? 1 : 0;
      } else if (_expanded) {
        await _motion.forward().orCancel;
      } else {
        await _motion.reverse().orCancel;
      }
    } on scheduler.TickerCanceled {
      // A system reduced-motion change or disposal may end the transition.
    } finally {
      _changing = false;
      if (mounted) {
        if (!_expanded) setState(() => _showDetails = false);
        updateKeepAlive();
        _anchorTop = null;
      }
    }
  }

  ButtonStyle _detailsStyle() => OutlinedButton.styleFrom(
    foregroundColor: const Color(0xff7954b4),
    backgroundColor: const Color(0xff7954b4).withValues(alpha: .06),
    side: const BorderSide(color: Color(0xff9673c7), width: 1.2),
    shape: const StadiumBorder(),
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final color = theme.brightness == Brightness.light
        ? Colors.white
        : theme.colorScheme.surface;
    final style = theme.textTheme.bodyMedium!.copyWith(
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Card(
      color: color,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final photo = widget.photo;
          final leftWidth = photo == null
              ? bounds.maxWidth
              : bounds.maxWidth * .56;
          final padding = bounds.maxWidth < 380 ? 12.0 : 16.0;
          final textWidth = math.max(1.0, leftWidth - padding * 2);
          final layout = (
            widget.body,
            style,
            textWidth,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
            _detailsHeight,
            padding,
          );
          if (_previewLayout != layout) {
            _previewLayout = layout;
            _textLayout = PublicationTextLayout.measure(
              text: widget.body,
              style: style,
              width: textWidth,
              direction: Directionality.of(context),
              scaler: MediaQuery.textScalerOf(context),
              controlHeight: _detailsHeight,
              bottomPadding: padding,
            );
          }
          final flow = _textLayout!;
          final preview = flow.preview, rest = flow.below;
          final date = widget.date?.toLocal();
          final dateText = date == null
              ? ''
              : '${MaterialLocalizations.of(context).formatMediumDate(date)}'
                    '${widget.showTime ? ' · ${TimeOfDay.fromDateTime(date).format(context)}' : ''}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                key: _header,
                children: [
                  if (photo != null)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: bounds.maxWidth * .48,
                      child: RepaintBoundary(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            photo,
                            // Feather only the first 10% of the photograph (was 52%).
                            // A narrow alpha gradient needs no offscreen blur pass.
                            IgnorePointer(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: .10,
                                  heightFactor: 1,
                                  child: DecoratedBox(
                                    key: const ValueKey(
                                      'publication-photo-edge',
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          color,
                                          color.withValues(alpha: .75),
                                          color.withValues(alpha: 0),
                                        ],
                                        stops: const [0, .35, 1],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(
                    width: leftWidth,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        padding,
                        padding,
                        _showDetails && flow.hasDetails ? 0 : padding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: theme
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: .45),
                                foregroundColor: theme.colorScheme.primary,
                                child: Icon(widget.icon, size: 23),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (dateText.isNotEmpty)
                                      Text(
                                        dateText,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    Text(
                                      widget.category,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((widget.location ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.location!,
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                          if (preview.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            if (_showDetails && flow.hasDetails)
                              SizedBox(
                                height: flow.slotHeight,
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: AnimatedBuilder(
                                    animation: _motion,
                                    builder: (context, child) => _LineReveal(
                                      text: flow.beside,
                                      style: style,
                                      progress: _motion.value,
                                      reduced: reduced,
                                      textKey: const ValueKey(
                                        'publication-preview',
                                      ),
                                      initiallyVisibleLines: flow.previewLines,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Text(
                                preview,
                                key: const ValueKey('publication-preview'),
                                style: style,
                              ),
                          ],
                          if (flow.hasDetails && !_showDetails) ...[
                            const SizedBox(height: 10),
                            OutlinedButton(
                              key: _detailsButton,
                              onPressed: _toggle,
                              style: _detailsStyle(),
                              child: const Text('Подробнее'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (flow.hasDetails)
                AnimatedBuilder(
                  animation: _motion,
                  builder: (context, child) {
                    _keepAnchor();
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: Curves.easeInOutCubic.transform(
                          _motion.value,
                        ),
                        child: _motion.value == 0
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: EdgeInsets.fromLTRB(
                                  padding,
                                  0,
                                  padding,
                                  padding,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (rest.isNotEmpty)
                                      _LineReveal(
                                        text: rest,
                                        style: style,
                                        progress: _motion.value,
                                        reduced: reduced,
                                      ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: OutlinedButton(
                                          key: const ValueKey(
                                            'publication-collapse',
                                          ),
                                          onPressed: _toggle,
                                          style: _detailsStyle(),
                                          child: const Text('Свернуть'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LineReveal extends StatefulWidget {
  const _LineReveal({
    required this.text,
    required this.style,
    required this.progress,
    required this.reduced,
    this.textKey = const ValueKey('publication-continuation'),
    this.initiallyVisibleLines = 0,
  });
  final Key textKey;
  final int initiallyVisibleLines;
  final String text;
  final TextStyle style;
  final double progress;
  final bool reduced;
  @override
  State<_LineReveal> createState() => _LineRevealState();
}

class _LineRevealState extends State<_LineReveal> {
  Object? _layout;
  final _stops = <double>[];
  final _delays = <double>[];
  @override
  Widget build(BuildContext context) {
    final child = Text(widget.text, key: widget.textKey, style: widget.style);
    if (widget.reduced || widget.progress >= 1) return child;
    return LayoutBuilder(
      builder: (context, bounds) {
        final key = (
          widget.text,
          widget.style,
          bounds.maxWidth,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        );
        if (_layout != key) {
          _layout = key;
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: bounds.maxWidth);
          final lines = painter.computeLineMetrics();
          final height = math.max(1.0, painter.height);
          painter.dispose();
          _stops.clear();
          _delays.clear();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            final top = ((line.baseline - line.ascent) / height)
                .clamp(0.0, 1.0)
                .toDouble();
            final bottom = ((line.baseline + line.descent) / height)
                .clamp(top, 1.0)
                .toDouble();
            _stops.addAll([top, bottom]);
            _delays.add(lines.length <= 1 ? 0 : .35 * i / (lines.length - 1));
          }
        }
        if (_stops.length < 2)
          return Opacity(opacity: widget.progress, child: child);
        final colors = <Color>[];
        for (var i = 0; i < _delays.length; i++) {
          final color = Colors.white.withValues(
            alpha: i < widget.initiallyVisibleLines
                ? 1
                : ((widget.progress - _delays[i]) / .65)
                      .clamp(0.0, 1.0)
                      .toDouble(),
          );
          colors.addAll([color, color]);
        }
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: _stops,
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
