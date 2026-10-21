import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/app_mark.dart';

class AlreadyRunningScreen extends StatelessWidget {
  const AlreadyRunningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppMark(size: 44),
              const SizedBox(height: 20),
               Text(
                '应用已经在运行',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
               Text(
                '同一时间只允许一个实例操作备份库，避免控制锁与写入冲突。请切换到已打开的窗口。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => exit(0),
                  child: const Text('退出'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
