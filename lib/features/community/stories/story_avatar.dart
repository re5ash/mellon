import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../club_photo.dart';
import 'story_composer.dart';
import 'story_repository.dart';
import 'story_viewer.dart';

class ClubStoryAvatar extends ConsumerStatefulWidget {
  const ClubStoryAvatar({
    required this.club,
    required this.enabled,
    this.path,
    this.onEdit,
    this.halo = false,
    super.key,
  });
  final String club;
  final bool enabled;
  final bool halo;
  final String? path;
  final VoidCallback? onEdit;
  @override
  ConsumerState<ClubStoryAvatar> createState() => _ClubStoryAvatarState();
}

class _ClubStoryAvatarState extends ConsumerState<ClubStoryAvatar> {
  ClubStory? _published;
  String? _publishedActor;
  bool _adding = false;
  @override
  void didUpdateWidget(ClubStoryAvatar old) {
    super.didUpdateWidget(old);
    if (old.club != widget.club) {
      _published = null;
      _publishedActor = null;
    }
  }

  Future<void> _add() async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null || _adding) return;
    final club = widget.club;
    setState(() => _adding = true);
    try {
      final story = await openStoryComposer(context, ref, club, actor);
      if (!mounted ||
          club != widget.club ||
          ref.read(authUserProvider).asData?.value?.id != actor)
        return;
      if (story != null)
        setState(() {
          _published = story;
          _publishedActor = actor;
        });
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authUserProvider).asData?.value?.id;
    final state = widget.enabled
        ? ref.watch(clubStoriesProvider(widget.club))
        : null;
    final list = [...?state?.asData?.value];
    final local = _published;
    if (widget.enabled &&
        local != null &&
        _publishedActor == actor &&
        local.expiresAt.isAfter(DateTime.now()) &&
        state?.hasError != true &&
        state?.isLoading == true &&
        !list.any((s) => s.id == local.id))
      list.add(local);
    return ClubPhoto(
      path: widget.path,
      halo: widget.halo,
      onEdit: widget.onEdit,
      onAddStory: widget.enabled && widget.onEdit != null && !_adding
          ? _add
          : null,
      hasStories: list.isNotEmpty,
      onViewStories: list.isEmpty
          ? null
          : () => openStoryViewer(context, widget.club, list),
    );
  }
}
