import 'package:flutter/material.dart';

class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required Object title,
    super.key,
    super.actions,
    super.bottom,
  }) : super(
          toolbarHeight: 78,
          titleSpacing: 8,
          title: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: Image.asset(
                    'assets/images/mpg_logo.png',
                    height: 58,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    child: title is Widget ? title : Text(title.toString()),
                  ),
                ),
              ],
            ),
          ),
        );
}
