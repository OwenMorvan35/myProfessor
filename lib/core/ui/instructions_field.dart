import 'package:flutter/material.dart';

class InstructionsField extends StatelessWidget {
  const InstructionsField({
    super.key,
    required this.controller,
    this.label = 'Consignes',
    this.hint = 'Ajoute des consignes spécifiques pour personnaliser le rendu.',
    this.minLines = 3,
    this.maxLines = 6,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;
  final int maxLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: Icon(
          Icons.auto_awesome,
          color:
              theme.colorScheme.primary.withValues(alpha: enabled ? 0.6 : 0.25),
        ),
      ),
    );
  }
}
