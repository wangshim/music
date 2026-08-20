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
    return MaterialApp(
      title: '音频分析助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
