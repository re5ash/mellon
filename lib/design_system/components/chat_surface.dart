import 'package:flutter/material.dart';

import '../appearance_palette.dart';
import '../appearance_settings.dart';
import '../chat_wallpaper_catalog.dart';

class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({required this.settings, required this.child, super.key});
  final AppearanceSettings settings;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final design = ChatWallpapers.designs[settings.wallpaper];
    if (design != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [design.top, design.bottom],
                  ),
                ),
                child: CustomPaint(painter: OrthodoxWallpaperPainter(design)),
              ),
            ),
          ),
          child,
        ],
      );
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tone = switch (settings.wallpaper) {
      ChatWallpaper.sky => const Color(0xFF7EBDE0),
      ChatWallpaper.olive => const Color(0xFF9CA976),
      ChatWallpaper.sand => const Color(0xFFE0BE8C),
      ChatWallpaper.lavender => const Color(0xFFB5A0D1),
      _ => colors.primary,
    };
    final plain =
        settings.wallpaper == ChatWallpaper.plain ||
        settings.wallpaper == ChatWallpaper.automatic &&
            !dark &&
            settings.preset == AppearancePreset.day;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: plain ? theme.scaffoldBackgroundColor : null,
                gradient: plain
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(colors.surface, tone, dark ? .18 : .2)!,
                          Color.lerp(colors.surface, tone, dark ? .06 : .055)!,
                          Color.lerp(colors.surface, tone, dark ? .12 : .12)!,
                        ],
                      ),
              ),
              child: CustomPaint(
                painter: plain
                    ? null
                    : _BranchesPainter(tone.withValues(alpha: dark ? .1 : .13)),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BranchesPainter extends CustomPainter {
  const _BranchesPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double y = 24; y < size.height; y += 112) {
      for (double x = 22; x < size.width; x += 120) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-.45);
        canvas.drawPath(
          Path()
            ..moveTo(0, 38)
            ..quadraticBezierTo(11, 16, 0, -12),
          paint,
        );
        for (var i = 0; i < 3; i++) {
          final dy = i * 12.0;
          canvas.drawPath(
            Path()
              ..moveTo(5, dy)
              ..quadraticBezierTo(-16, dy - 12, -10, dy - 17)
              ..quadraticBezierTo(5, dy - 13, 5, dy),
            paint,
          );
          canvas.drawPath(
            Path()
              ..moveTo(5, dy + 4)
              ..quadraticBezierTo(24, dy - 1, 20, dy - 10)
              ..quadraticBezierTo(7, dy - 9, 5, dy + 4),
            paint,
          );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_BranchesPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// The real chat and appearance preview share this exact message renderer.
class ChatMessageCard extends StatelessWidget {
  const ChatMessageCard({
    required this.settings,
    required this.body,
    required this.author,
    required this.time,
    required this.outgoing,
    this.reply,
    this.reactions,
    super.key,
  });
  final AppearanceSettings settings;
  final String body, author, time;
  final bool outgoing;
  final Widget? reply, reactions;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nameColor = AppearancePalette.color(
      settings.nameColorIndex,
      dark: theme.brightness == Brightness.dark,
    );
    final text = LayoutBuilder(
      builder: (context, constraints) {
        final metadataStyle = theme.textTheme.bodySmall!.copyWith(
          fontSize: 11,
          height: 1.1,
          letterSpacing: 0,
          color: colors.onSurfaceVariant,
        );
        // Measure only the short timestamp; the message itself is laid out once.
        final clock = TextPainter(
          text: TextSpan(text: time, style: metadataStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final clockWidth = clock.width, clockHeight = clock.height;
        clock.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reply != null) ...[reply!, const SizedBox(height: 6)],
            if (!outgoing) ...[
              Text(
                author,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: nameColor,
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
            ],
            Stack(
              children: [
                Container(
                  constraints: BoxConstraints(minWidth: clockWidth),
                  padding: EdgeInsets.only(bottom: clockHeight + 3),
                  child: Text(
                    body,
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamilyFallback: const ['MellonEmoji'],
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                      color: colors.onSurface,
                      height: 1.25,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(time, style: metadataStyle),
                ),
              ],
            ),
            if (reactions != null) ...[const SizedBox(height: 6), reactions!],
          ],
        );
      },
    );
    if (!settings.messageBlocks) {
      return Align(
        alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: .94,
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (outgoing ? colors.primaryContainer : colors.surface)
                  .withValues(alpha: .94),
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .25),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    outgoing ? Icons.person_outline : Icons.person,
                    size: 18,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: text),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: (constraints.maxWidth * .86).clamp(0.0, 560.0).toDouble(),
          ),
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: outgoing ? colors.primaryContainer : colors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(outgoing ? 18 : 5),
              bottomRight: Radius.circular(outgoing ? 5 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: text,
        ),
      ),
    );
  }
}
