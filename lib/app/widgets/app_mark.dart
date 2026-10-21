import 'package:flutter/material.dart';

import '../theme.dart';

class AppMark extends StatelessWidget {
  const AppMark({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.shield_moon_outlined,
        size: size * 0.55,
        color: const Color(0xFF04140D),
      ),
    );
  }
}
