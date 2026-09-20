import 'package:flutter/material.dart';

import '../domain/map_place.dart';

class TemplePin extends StatelessWidget {
  const TemplePin({
    required this.onTap,
    this.place = alexanderNevsky,
    this.selected = false,
    super.key,
  });
  final MapPlace place;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: place.title,
    selected: selected,
    child: GestureDetector(
      key: const ValueKey('temple-map-pin'),
      onTap: onTap,
      child: CustomPaint(
        painter: const _DropShadow(),
        foregroundPainter: _DropBorder(selected: selected),
        child: ClipPath(
          clipper: const TempleDropClipper(),
          child: place.photoAsset == null
              ? const ColoredBox(
                  color: Color(0xffe6f3fc),
                  child: Center(child: Icon(Icons.church_rounded, color: Color(0xff318fc9))),
                )
              : Image.asset(
                  place.photoAsset!,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -.25),
                  cacheWidth: 640,
                  excludeFromSemantics: true,
                ),
        ),
      ),
    ),
  );
}

// One geometry, in the same bounds, for the photograph, outline and shadow.
// Stroke stays inside the clipping path; the photo is cropped, never stretched.
Path templeDropPath(Size size) => Path()
  ..moveTo(size.width / 2, size.height)
  ..cubicTo(
    size.width * .38,
    size.height * .83,
    0,
    size.height * .56,
    0,
    size.height * .37,
  )
  ..cubicTo(
    0,
    -size.height * .13,
    size.width,
    -size.height * .13,
    size.width,
    size.height * .37,
  )
  ..cubicTo(
    size.width,
    size.height * .56,
    size.width * .62,
    size.height * .83,
    size.width / 2,
    size.height,
  )
  ..close();

class TempleDropClipper extends CustomClipper<Path> {
  const TempleDropClipper();
  @override
  Path getClip(Size size) => templeDropPath(size);
  @override
  bool shouldReclip(TempleDropClipper oldClipper) => false;
}

class _DropShadow extends CustomPainter {
  const _DropShadow();
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawShadow(templeDropPath(size), const Color(0x60223f58), 5, true);
  @override
  bool shouldRepaint(_DropShadow oldDelegate) => false;
}

class _DropBorder extends CustomPainter {
  const _DropBorder({this.selected = false});
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final path = templeDropPath(size);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Colors.white,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 8 : 5
        ..color = selected ? const Color(0xff1455a3) : const Color(0xff318fc9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DropBorder oldDelegate) => oldDelegate.selected != selected;
}
