import 'package:flutter/material.dart';

class MatchOptionButton extends StatelessWidget {
  const MatchOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.height = 46,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    if (selected) {
      return SizedBox(
        height: height,
        child: FilledButton(
          onPressed: onPressed,
          child: child,
        ),
      );
    }

    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        child: child,
      ),
    );
  }
}
