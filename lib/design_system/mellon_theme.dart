import 'package:flutter/material.dart';

import 'appearance_settings.dart';

/// Visual identity only. Membership, chat icons and routes keep their own data.
class MellonThemeStyle extends ThemeExtension<MellonThemeStyle> {
  const MellonThemeStyle(this.kind, {this.customAccent});
  final Color? customAccent;
  final MellonVisualTheme kind;

  static MellonThemeStyle of(BuildContext context) =>
      Theme.of(context).extension<MellonThemeStyle>() ??
      const MellonThemeStyle(MellonVisualTheme.current);

  bool get enabled => kind != MellonVisualTheme.current;
  bool get classical => kind == MellonVisualTheme.cathedral;
  bool get luminous => kind == MellonVisualTheme.radiance;
  String get title => switch (kind) {
    MellonVisualTheme.current => 'Текущее оформление',
    MellonVisualTheme.cathedral => 'Соборное стекло',
    MellonVisualTheme.radiance => 'Золотой свет',
    MellonVisualTheme.azure => 'Небесный ореол',
  };
  String get asset => 'assets/themes/${kind.name}.webp';
  String get headingFamily => classical ? 'PTSerif' : 'Roboto';
  Color get accent =>
      customAccent ??
      (classical
          ? const Color(0xff285c86)
          : luminous
          ? const Color(0xff087bff)
          : const Color(0xff2354ec));
  Color get ink => classical
      ? const Color(0xff11182b)
      : luminous
      ? const Color(0xff090d25)
      : const Color(0xff080d42);
  Color get muted => classical
      ? const Color(0xff586476)
      : luminous
      ? const Color(0xff7080a0)
      : const Color(0xff6181c3);
  Color get base => classical
      ? const Color(0xffeee9df)
      : luminous
      ? const Color(0xfff9f6ef)
      : const Color(0xffdcecff);
  double get surfaceTop => classical
      ? .63
      : luminous
      ? .87
      : .73;
  double get surfaceBottom => classical
      ? .42
      : luminous
      ? .62
      : .49;
  double get radius => classical
      ? 18
      : luminous
      ? 24
      : 16;
  double get iconRadius => classical || luminous ? 999 : 13;
  double get haloWidth => luminous ? 1.8 : 1.1;
  Color get halo =>
      luminous ? const Color(0xffffd778) : const Color(0xfff4e6c8);
  double get pageInset => classical
      ? 24
      : luminous
      ? 10
      : 18;

  @override
  MellonThemeStyle copyWith({MellonVisualTheme? kind}) =>
      MellonThemeStyle(kind ?? this.kind, customAccent: customAccent);

  @override
  MellonThemeStyle lerp(covariant MellonThemeStyle? other, double t) =>
      other == null || t < .5 ? this : other;
}

/// Shared live icon treatment, including the theme picker miniature.
class MellonFeatureIcon extends StatelessWidget {
  const MellonFeatureIcon({
    required this.icon,
    required this.color,
    this.size = 28,
    super.key,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    if (design.classical) return Icon(icon, color: design.accent, size: size);
    return Container(
      width: size + 8,
      height: size + 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(design.luminous ? size : 10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .35)!, color],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .17),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * .83),
    );
  }
}
