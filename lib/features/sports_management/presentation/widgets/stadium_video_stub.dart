import 'package:flutter/widgets.dart';

/// Hors navigateur, rien à débloquer.
void primeStadiumVideo() {}

/// Hors navigateur, pas de lecteur vidéo : l'image fixe du stade suffit.
class StadiumVideo extends StatefulWidget {
  const StadiumVideo({
    super.key,
    required this.video,
    required this.lightVideo,
    required this.poster,
    required this.playing,
    required this.take,
    required this.elapsed,
    required this.onReady,
    this.onStatus,
  });

  final String video;
  final String lightVideo;
  final String poster;
  final bool playing;
  final int take;
  final double Function() elapsed;
  final VoidCallback onReady;
  final ValueChanged<String>? onStatus;

  @override
  State<StadiumVideo> createState() => _StadiumVideoState();
}

class _StadiumVideoState extends State<StadiumVideo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(widget.poster, fit: BoxFit.cover, gaplessPlayback: true);
  }
}
