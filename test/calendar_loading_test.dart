import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/views/calendar/calendar_view.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/views/overview/overview_view.dart';

void main() {
  testWidgets('running and queued tasks follow live schedule changes',
      (tester) async {
    final model = ScriptModel('test');
    model.update(
        state: ScriptState.running,
        runningTask: const TaskItemModel('Test', '2020-01-01 07:00:00'));
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScriptCalendar(
      script: 'test',
      runtimeModel: model,
      loadCalendar: (_, __) async {
        calls++;
        return ApiResult.success({
          'events': [
            {
              'task': 'test',
              'at': '$date 07:00:00',
              'kind': 'overdue',
              'float_time': '00:00:00'
            }
          ],
          'warnings': []
        });
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('原定 01-01 07:00'), findsOneWidget);
    model.update(
        runningTask: TaskItemModel.empty(),
        pendingTaskList: [const TaskItemModel('Test', '2020-01-01 07:00:00')]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('排队中 · 等待前序完成'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('calendar refreshes silently and cancels timer on disposal',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScriptCalendar(
      script: 'test',
      loadCalendar: (_, __) async {
        calls++;
        return ApiResult.success({'events': [], 'warnings': []});
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
  });
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
