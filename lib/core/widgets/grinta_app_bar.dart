import 'package:flutter/material.dart';

class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required Object title,
    super.key,
    super.actions,
    super.bottom,
  }) : super(
          toolbarHeight: 104,
          titleSpacing: 8,
          title: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: Image.asset(
                    'assets/images/mpg_logo.png',
                    height: 88,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                if (_showTitle(title)) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 72),
                    child: DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      child: title is Widget ? title : Text(title.toString()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

  static bool _showTitle(Object title) {
    if (title is SizedBox && title.child == null) return false;
    if (title is Text) {
      return title.data != 'Saisie du match' &&
          title.data != 'Détails du match' &&
          (title.data?.isNotEmpty ?? false);
    }
    return true;
  }
}
