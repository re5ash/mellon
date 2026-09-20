import 'package:video_player/video_player.dart';

VideoPlayerController localStoryVideo(String path) =>
    VideoPlayerController.networkUrl(
      Uri.parse(path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
