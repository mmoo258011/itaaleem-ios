import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Themed text field: filled, 12px radius, a hairline border that turns
/// brand-colored on focus (all from [InputDecorationTheme] in `AppTheme`),
/// exposed as a widget for the common label/hint/prefixIcon shape.
class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.maxLines = 1,
    this.autofocus = false,
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.style,
    this.inputFormatters,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;

  /// Merged on top of the field's default text style (Cairo, 15px) — e.g. a
  /// larger, bolder, letter-spaced style for a short code-entry field.
  final TextStyle? style;

  /// e.g. `[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]`
  /// for a phone-number field.
  final List<TextInputFormatter>? inputFormatters;

  /// A server-side error to show beneath the field (e.g. a 422 validation
  /// message for this field), independent of [validator]'s local checks —
  /// set this after a failed submit, alongside the returned
  /// `ValidationFailure.fieldErrors`.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      textAlign: textAlign,
      inputFormatters: inputFormatters,
      style: TextStyle(
        // The theme's font: Cairo app-wide, Readex Pro on the entry screens.
        fontFamily:
            Theme.of(context).textTheme.bodyLarge?.fontFamily ?? 'Cairo',
        fontSize: 15,
        color: context.palette.textPrimary,
      ).merge(style),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: AppIconSize.sm)
            : null,
        suffixIcon: suffixIcon,
        // Fill, borders and padding come from the theme's
        // InputDecorationTheme so every field in the app matches.
      ),
    );
  }
}
