import 'package:flutter/material.dart';

import '../tokens.dart';

class ContentFrame extends StatelessWidget {
  const ContentFrame({
    required this.child,
    this.padding,
    this.maxWidth = AppLayout.contentMaxWidth,
    super.key,
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpace.md),
        child: child,
      ),
    ),
  );
}
