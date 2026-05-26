import 'package:flutter/material.dart';

class MenuDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Меню', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMenuOption('Файл', Icons.folder_outlined, context),
          _buildMenuOption('Редактировать', Icons.edit_outlined, context),
          _buildMenuOption('Вид', Icons.visibility_outlined, context),
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