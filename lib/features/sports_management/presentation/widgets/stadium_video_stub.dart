import 'package:flutter/widgets.dart';

/// Hors navigateur, pas de lecteur vidéo : l'image fixe du stade suffit.
class StadiumVideo extends StatefulWidget {
  const StadiumVideo({
    super.key,
    required this.video,
    required this.poster,
    required this.playing,
    required this.take,
    required this.onReady,
  });

  final String video;
  final String poster;
  final bool playing;
  final int take;
  final VoidCallback onReady;

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
