import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../map/application/map_temples.dart';

/// fallbackAddress is the address joined from parishes by the club RPC.
/// It is not a second stored address and keeps the row stable during refresh.
class ClubTempleAddress extends ConsumerWidget {
  const ClubTempleAddress({
    required this.parishId,
    required this.fallbackAddress,
    super.key,
  });
  final String? parishId;
  final String fallbackAddress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = parishId;
    final state = id == null || id.isEmpty ? null : ref.watch(mapTemplesProvider);
    final temple = id == null || state == null || !state.hasValue || state.isReloading
        ? null
        : templeById(state.requireValue, id);
    final address = temple?.address ?? fallbackAddress;
    final text = address.trim().isEmpty ? 'Адрес храма не указан' : address;
    final enabled = id != null && id.isNotEmpty;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: enabled,
      child: InkWell(
        key: const ValueKey('club-temple-address'),
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? () {
          context.go(Uri(path: '/map', queryParameters: {
            'parish': id,
            'focus': DateTime.now().microsecondsSinceEpoch.toString(),
          }).toString());
        } : null,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined, size: 17, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
