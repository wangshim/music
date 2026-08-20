import 'package:audio_analyzer_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App 骨架冒烟测试：能渲染首页', (WidgetTester tester) async {
    await tester.pumpWidget(const AudioAnalyzerApp());

    expect(find.text('音频分析助手'), findsOneWidget);
    expect(find.text('选择音频文件'), findsOneWidget);
    expect(find.text('开始分析'), findsOneWidget);
  });
}
