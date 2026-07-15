import 'package:flutter/material.dart';

class GrintaAppBar extends AppBar {
  GrintaAppBar({required Object title, super.key, super.actions, super.bottom})
    : super(
        toolbarHeight: 104,
        titleSpacing: 8,
        title: SizedBox(
          width: double.infinity,
          child: Image.asset(
            'assets/images/mpg_logo.png',
            height: 88,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        ),
      );
}
