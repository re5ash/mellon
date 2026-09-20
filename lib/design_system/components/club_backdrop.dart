import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appearance_settings.dart';
import '../theme_controller.dart';
import 'mellon_theme_backdrop.dart';

String clubBackgroundLabel(ClubBackground value) => switch (value) {
  ClubBackground.current => 'Текущий фон',
  ClubBackground.sky => 'Небесный',
  ClubBackground.linen => 'Льняной',
  ClubBackground.olive => 'Оливковый',
  ClubBackground.lavender => 'Лавандовый',
  ClubBackground.evening => 'Вечерний',
};

/// Opt-in wrapper used only by the youth club screen, outside its scroll view.
class ClubScreenBackground extends ConsumerWidget {
  const ClubScreenBackground({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(
      appearanceControllerProvider.select((s) => s.clubBackground),
    );
    return MellonThemeBackdrop(
      enabled:
          background == ClubBackground.current &&
          !MellonThemeBackdrop.covered(context),
      child: ClubBackdrop(
        background: ref.watch(
          appearanceControllerProvider.select(
            (settings) => settings.clubBackground,
          ),
        ),
        child: child,
      ),
    );
  }
}

class ClubBackdrop extends StatelessWidget {
  const ClubBackdrop({
    required this.background,
    required this.child,
    super.key,
  });
  final ClubBackground background;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey('club-background-paint'),
              painter: _ClubBackgroundPainter(
                background,
                Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      ),
      // This child stays in the same slot when a preference changes.
      child,
    ],
  );
}

class _ClubBackgroundPainter extends CustomPainter {
  const _ClubBackgroundPainter(this.background, this.dark);
  final ClubBackground background;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // No paint at all: the existing application background shows through.
    if (background == ClubBackground.current) return;
    final colors = switch (background) {
      ClubBackground.sky =>
        dark
            ? const [Color(0xff152a3b), Color(0xff253e51)]
            : const [Color(0xffd3e7fa), Color(0xffeff7fc)],
      ClubBackground.linen =>
        dark
            ? const [Color(0xff302c27), Color(0xff413a30)]
            : const [Color(0xfff2e8d5), Color(0xfffcf8f0)],
      ClubBackground.olive =>
        dark
            ? const [Color(0xff23362f), Color(0xff34463a)]
            : const [Color(0xffdce9dc), Color(0xfff4f7ee)],
      ClubBackground.lavender =>
        dark
            ? const [Color(0xff2c2943), Color(0xff3a3551)]
            : const [Color(0xffe5def6), Color(0xfff5f2fc)],
      ClubBackground.evening =>
        dark
            ? const [Color(0xff151e35), Color(0xff34314b)]
            : const [Color(0xffaebdd9), Color(0xffded9eb)],
      ClubBackground.current => const [Colors.transparent, Colors.transparent],
    };
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.65, -.8),
          radius: 1.25,
          colors: [
            Colors.white.withValues(alpha: dark ? .05 : .38),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    // Static, sparse arcs are cheap to rasterize and stay behind the content.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: dark ? .04 : .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width * .86, size.height * .18),
        size.width * (.30 + .17 * i),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_ClubBackgroundPainter oldDelegate) =>
      background != oldDelegate.background || dark != oldDelegate.dark;
}
