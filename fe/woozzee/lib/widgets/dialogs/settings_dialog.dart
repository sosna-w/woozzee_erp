import 'package:flutter/material.dart';

class SettingsDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Настройки', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMenuOption('Основные', Icons.settings_outlined, context),
          _buildMenuOption('Аккаунт', Icons.person_outlined, context),
          _buildMenuOption('Безопасность', Icons.security_outlined, context),
        ],
      ),
    );
  }

  Widget _buildMenuOption(String text, IconData icon, BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
      title: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      onTap: () => Navigator.of(context).pop(),
    );
  }
}