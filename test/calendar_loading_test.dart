import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/views/calendar/calendar_view.dart';

void main() {
  testWidgets('a stalled request stops loading and offers retry',
      (tester) async {
    final pending = Completer<ApiResult<Map<String, dynamic>>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScriptCalendar(
      script: 'test',
      loadCalendar: (_, __) => pending.future,
    ))));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('加载超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    pending.complete(ApiResult.success({'events': [], 'warnings': []}));
    await tester.pump();
    expect(find.textContaining('加载超时'), findsOneWidget);
  });

  testWidgets('invalid response can be retried successfully', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScriptCalendar(
      script: 'test',
      loadCalendar: (_, __) async => ApiResult.success(
          ++calls == 1 ? {'events': null} : {'events': [], 'warnings': []}),
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法加载脚本日历'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无计划'), findsNWidgets(7));
    expect(find.text('重试'), findsNothing);
  });
}
