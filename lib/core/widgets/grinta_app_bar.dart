import 'package:flutter/material.dart';

class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required String title,
    super.key,
    super.actions,
    super.bottom,
  }) : super(
          titleSpacing: 12,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/mpg_logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
}
