import 'package:flutter/material.dart';

/// `true` quand le téléphone demande de réduire les animations.
///
/// Ce réglage existe pour les personnes sujettes au mal des transports : une
/// animation ignorée n'est pas un détail de confort, elle rend l'écran
/// pénible voire inutilisable. Toutes les animations du bilan passent par ce
/// drapeau.
bool wrappedReducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Apparition en fondu et léger glissement, après un délai.
///
/// Les éléments d'un écran entrent en cascade plutôt que d'un bloc : l'œil
/// suit l'ordre voulu au lieu de choisir le sien.
class WrappedReveal extends StatefulWidget {
  const WrappedReveal({
    super.key,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = 18,
    required this.child,
  });

  final Duration delay;
  final Duration duration;
  final double offset;
  final Widget child;

  @override
  State<WrappedReveal> createState() => _WrappedRevealState();
}

class _WrappedRevealState extends State<WrappedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (wrappedReducedMotion(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (wrappedReducedMotion(context)) return widget.child;

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Un compteur qui monte jusqu'à sa valeur.
///
/// C'est l'effet le plus payant du bilan : voir le chiffre grimper donne au
/// résultat une valeur que le même chiffre posé d'un coup n'a pas.
class WrappedCountUp extends StatefulWidget {
  const WrappedCountUp({
    super.key,
    required this.value,
    required this.style,
    this.delay = const Duration(milliseconds: 260),
    this.duration = const Duration(milliseconds: 1150),
    this.suffix = '',
    this.decimals = 0,
  });

  final num value;
  final TextStyle style;
  final Duration delay;
  final Duration duration;
  final String suffix;
  final int decimals;

  @override
  State<WrappedCountUp> createState() => _WrappedCountUpState();
}

class _WrappedCountUpState extends State<WrappedCountUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (wrappedReducedMotion(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(num value) {
    final text = widget.decimals == 0
        ? value.round().toString()
        : value.toStringAsFixed(widget.decimals).replaceAll('.', ',');
    return '$text${widget.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    if (wrappedReducedMotion(context)) {
      return Text(_format(widget.value), style: widget.style);
    }

    final curve = CurvedAnimation(
      parent: _controller,
      // Un compteur qui ralentit à l'approche du résultat : la fin compte
      // plus que le début.
      curve: Curves.easeOutQuart,
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => Text(
        _format(widget.value * curve.value),
        style: widget.style,
      ),
    );
  }
}

/// Texte tapé à la machine, lettre après lettre.
class WrappedTypewriter extends StatefulWidget {
  const WrappedTypewriter({
    super.key,
    required this.text,
    required this.style,
    this.delay = Duration.zero,
    this.perCharacter = const Duration(milliseconds: 38),
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final Duration delay;
  final Duration perCharacter;
  final TextAlign? textAlign;

  @override
  State<WrappedTypewriter> createState() => _WrappedTypewriterState();
}

class _WrappedTypewriterState extends State<WrappedTypewriter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.perCharacter * widget.text.characters.length,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (wrappedReducedMotion(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (wrappedReducedMotion(context)) {
      return Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shown = (widget.text.characters.length * _controller.value)
            .round()
            .clamp(0, widget.text.characters.length);
        return Text(
          widget.text.characters.take(shown).toString(),
          style: widget.style,
          textAlign: widget.textAlign,
        );
      },
    );
  }
}
