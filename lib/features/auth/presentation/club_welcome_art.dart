import 'package:flutter/material.dart';

import 'club_sky_scene.dart';

/// Only this decorative layer repaints while the registration form stays still.
class ClubWelcomeArt extends StatefulWidget {
  const ClubWelcomeArt({super.key});
  @override
  State<ClubWelcomeArt> createState() => _ClubWelcomeArtState();
}

class _ClubWelcomeArtState extends State<ClubWelcomeArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clouds;
  @override
  void initState() {
    super.initState();
    _clouds = AnimationController(
      vsync: this,
      duration: skyCloudTravelDuration,
      value: .20,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!enabled) {
      _clouds.stop();
    } else if (!_clouds.isAnimating) {
      _clouds.repeat();
    }
  }

  @override
  void dispose() {
    _clouds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: AspectRatio(
          aspectRatio: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/illustrations/club_welcome.png',
                fit: BoxFit.cover,
              ),
              RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('club-sky-clouds'),
                  painter: SkyCloudsPainter(_clouds),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
