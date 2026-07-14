import 'package:flutter/material.dart';

class GrintaAppBar extends AppBar {
  GrintaAppBar({
    required Object title,
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
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: title is Widget ? title : Text(title.toString()),
                ),
              ),
            ],
          ),
        );
}
