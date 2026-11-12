import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/theme/app_colors.dart';
import 'package:itaaleem/core/theme/app_theme.dart';

/// Gives [child] the smart UI's identity ([AppTheme.smartBrand]): the
/// entry screens every student sees before the app knows their center.
/// Follows the app's light / dark mode.
class SmartBrandTheme extends StatelessWidget {
  const SmartBrandTheme({super.key, required this.child});

  final Widget child;

  static final _light = AppTheme.smartBrand(Brightness.light);
  static final _dark = AppTheme.smartBrand(Brightness.dark);

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).brightness == Brightness.dark ? _dark : _light,
    child: child,
  );
}

/// A tap sound for the brand's main buttons. Android already clicks through
/// the ink feedback; iOS doesn't, so it plays the system click there.
VoidCallback? withTapSound(VoidCallback? onPressed) => onPressed == null
    ? null
    : () {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          SystemSound.play(SystemSoundType.click);
        }
        onPressed();
      };

/// The form card: rounded, on the page colour, with a soft navy shadow.
class BrandCard extends StatelessWidget {
  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 22, 18, 18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: dark ? Border.all(color: scheme.outlineVariant) : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.smartNavy.withValues(alpha: dark ? 0.4 : 0.08),
            blurRadius: 30,
            spreadRadius: -8,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The brand's icon tile: [icon] on a blue rounded square with a gold dot.
class BrandIconTile extends StatelessWidget {
  const BrandIconTile({super.key, required this.icon, this.size = 84});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [AppColors.smartBlue, Color(0xFF1B2FB0)],
            ),
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(
                color: AppColors.smartBlue.withValues(alpha: 0.35),
                blurRadius: 28,
                spreadRadius: -6,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(icon, size: size * 0.46, color: Colors.white),
        ),
        PositionedDirectional(
          top: -4,
          end: -4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.smartGold,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
