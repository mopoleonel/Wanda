import 'package:flutter/material.dart';

/// Bascule Connexion / Inscription : `SegmentedButton` Material, stylé par
/// le thème.
class AuthModeToggle extends StatelessWidget {
  final bool isPrimarySelected;
  final String primaryLabel;
  final String secondaryLabel;
  final ValueChanged<bool> onChanged;

  const AuthModeToggle({
    super.key,
    required this.isPrimarySelected,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: true, label: Text(primaryLabel)),
          ButtonSegment(value: false, label: Text(secondaryLabel)),
        ],
        selected: {isPrimarySelected},
        onSelectionChanged: (s) => onChanged(s.first),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(0, 48)),
        ),
      ),
    );
  }
}
