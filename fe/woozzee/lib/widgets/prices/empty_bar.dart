import 'package:flutter/material.dart';

class EmptyBar extends StatelessWidget {
  final double width;

  const EmptyBar({Key? key, required this.width}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: 0);
  }
}