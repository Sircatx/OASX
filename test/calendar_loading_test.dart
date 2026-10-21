import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/views/calendar/calendar_view.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/views/overview/overview_view.dart';

void main() {
  testWidgets('guild raid displays battle count separately and only last time',
      (tester) async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScriptCalendar(
      script: 'test',
      loadCalendar: (_, __) async => ApiResult.success({
        'events': [
          {'task': 'ryou_toppa', 'at': '$date 08:57:29', 'kind': 'completed',
            'completed_count': 18, 'float_time': '00:00:00'},
          {'task': 'done', 'at': '$date 10:00:00', 'kind': 'completed',
            'completed_count': 1, 'float_time': '00:00:00'},
        ], 'warnings': [],
      }),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('共战斗 18 次'), findsOneWidget);
    expect(find.text('08:57'), findsOneWidget);
    expect(find.text('0 项计划 · 已完成 1 次 · 寮突破 18 战'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'success counts are green, grouped and separate from future plans',
      (tester) async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScriptCalendar(
      script: 'test',
      loadCalendar: (_, __) async => ApiResult.success({
        'events': [
          {
            'task': 'done',
            'at': '$date 10:00:00',
            'kind': 'completed',
            'completed_count': 3,
            'float_time': '00:00:00'
          },
          {
            'task': 'done',
            'at': '$date 20:00:00',
            'kind': 'next',
            'float_time': '00:00:00'
          },
        ],
        'warnings': [],
      }),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('日历 · 周视图'), findsOneWidget);
    expect(find.text('已完成 3 次'), findsOneWidget);
    expect(find.text('下一次'), findsOneWidget);
    expect(find.text('1 项计划 · 已完成 3 次'), findsOneWidget);
    final label = tester.widget<Text>(find.text('已完成 3 次'));
    expect(label.style!.color, const Color(0xFF256B2A));
    await tester.tap(find.text('1 项计划 · 已完成 3 次'));
    await tester.pumpAndSettle();
    expect(find.text('已完成 3 次'), findsNWidgets(2));
    expect(find.textContaining('随机延迟上限'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
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
    expect(find.textContaining('无法加载日历'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无计划'), findsNWidgets(7));
    expect(find.text('重试'), findsNothing);
  });
}
