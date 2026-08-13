import 'package:flutter/material.dart';

class BadgeEmblemBody extends StatelessWidget {
  const BadgeEmblemBody({
    super.key,
    required this.child,
    required this.size,
    required this.base,
    required this.footer,
    this.value,
  });

  final Widget child;
  final double size;
  final Color base;
  final String footer;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.isNotEmpty == true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size * 0.82,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(size * 0.18),
          ),
          child: child,
        ),
        if (hasValue)
          Transform.translate(
            offset: Offset(0, -size * 0.05),
            child: CircleAvatar(
              radius: size * 0.16,
              backgroundColor: base,
              child: Text(value!),
            ),
          ),
        Transform.translate(
          offset: Offset(0, hasValue ? -size * 0.1 : 0),
          child: Container(
            width: size,
            height: size * 0.3,
            alignment: Alignment.center,
            color: const Color(0xFF0B1D40),
            child: FittedBox(
              child: Text(
                footer,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
