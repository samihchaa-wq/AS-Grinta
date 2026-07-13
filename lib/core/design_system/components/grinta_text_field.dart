import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:flutter/material.dart';

/// Shared text input for Ma Petite Grinta forms.
class GrintaTextField extends StatelessWidget {
  const GrintaTextField({
    required this.label,
    super.key,
    this.controller,
    this.hint,
    this.helperText,
    this.errorText,
    this.leadingIcon,
    this.trailing,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final IconData? leadingIcon;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: obscureText ? 1 : maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: leadingIcon == null
            ? null
            : Icon(leadingIcon, size: GrintaIconography.control),
        suffixIcon: trailing,
      ),
    );
  }
}
