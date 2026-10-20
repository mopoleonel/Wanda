import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Snackbar standard (succès / erreur) : fond encre, icône colorée.
void showAppSnackBar(BuildContext context, String message,
    {bool isError = true}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_rounded : Icons.check_circle_rounded,
              color: isError ? const Color(0xFFFF9A8F) : AppColors.brandLeaf,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: AppText.body.copyWith(color: Colors.white)),
            ),
          ],
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
}
