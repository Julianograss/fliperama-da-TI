import 'package:flutter/material.dart';

/// Tela provisória para módulos ainda não implementados.
class ModulePlaceholderPage extends StatelessWidget {
  const ModulePlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Módulo em construção.'),
        ],
      ),
    );
  }
}
