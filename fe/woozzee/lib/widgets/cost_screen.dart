// cost_screen.dart - Изменено в диалоговое окно
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:open_file/open_file.dart'; // Добавлен импорт для открытия файлов

class CostDialog extends StatefulWidget {
  @override
  _CostDialogState createState() => _CostDialogState();
}

class _CostDialogState extends State<CostDialog> {
  bool _isLoading = false;

  Future<void> _downloadTemplate() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await http.get(Uri.parse('https://hide_domain.com/cost-template'));
      
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        // Получаем путь для сохранения
        final directory = await FilePicker.platform.getDirectoryPath();
        
        if (directory != null) {
          final file = File('$directory/cost_template.xlsx');
          await file.writeAsBytes(bytes);
          
          // Открываем файл после сохранения
          await OpenFile.open(file.path);
          
          _showSuccess('Шаблон сохранен и открыт');
        } else {
          _showError('Не выбрана директория для сохранения');
        }
      } else {
        _showError('Ошибка скачивания шаблона');
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadXlsx() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        final bytes = await file.readAsBytes();

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://hide_domain.com/upload-cost-xlsx'),
        );
        
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: result.files.first.name,
        ));

        setState(() {
          _isLoading = true;
        });

        final response = await request.send();
        final responseData = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseData);

        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        if (response.statusCode == 200) {
          _showSuccess('Файл загружен успешно!');
        } else {
          _showError('Ошибка: ${jsonResponse['error']}');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showError('Ошибка загрузки файла: $e');
    }
  }

  Future<void> _exportToXlsx() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await http.get(Uri.parse('https://hide_domain.com/cost/export'));
      
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final directory = await FilePicker.platform.getDirectoryPath();
        
        if (directory != null) {
          final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
          final file = File('$directory/cost_export_$timestamp.xlsx');
          await file.writeAsBytes(bytes);
          
          // Открываем файл после сохранения
          await OpenFile.open(file.path);
          
          _showSuccess('Экспорт сохранен и открыт');
        } else {
          _showError('Не выбрана директория для сохранения');
        }
      } else {
        _showError('Ошибка экспорта данных');
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Управление себестоимостью'),
      content: Container(
        height: 220, // Фиксированная высота
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8),
              ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: Text('Скачать шаблон'),
                onPressed: _downloadTemplate,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                ),
              ),
              SizedBox(height: 12),
              ElevatedButton.icon(
                icon: Icon(Icons.upload),
                label: Text('Загрузить XLSX'),
                onPressed: _uploadXlsx,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                ),
              ),
              SizedBox(height: 12),
              ElevatedButton.icon(
                icon: Icon(Icons.download_for_offline),
                label: Text('Экспорт в XLSX'),
                onPressed: _exportToXlsx,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Закрыть'),
        ),
      ],
    );
  }
}