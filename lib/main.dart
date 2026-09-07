import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/asr_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 后台预加载 ASR 模型，避免首次分析等待
  AsrService.instance.init().catchError((_) {});
  runApp(const AudioAnalyzerApp());
}

class AudioAnalyzerApp extends StatelessWidget {
  const AudioAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4E6AF0);
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return MaterialApp(
      title: '音频分析助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          backgroundColor: const Color(0xFFF7F8FC),
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: scheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
