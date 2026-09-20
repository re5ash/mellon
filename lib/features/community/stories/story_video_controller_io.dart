import 'dart:io';
import 'package:video_player/video_player.dart';

VideoPlayerController localStoryVideo(String path) =>
    VideoPlayerController.file(
      File(path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
