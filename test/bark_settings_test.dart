import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/views/home/bark_settings_card.dart';

Map<String, dynamic> settings() => {
      'enabled': true,
      'summary_enabled': true,
      'error_enabled': true,
      'endpoint': '',
      'group': '阴阳师',
      'sound': '',
      'icon': '',
      'level': 'passive',
      'error_level': 'active',
      'summary_title': '摘要 {date}',
      'summary_body': '{content}',
      'error_title': '{profile}出错',
      'error_body': '{title}\n{content}',
    };

void main() {
  testWidgets('save persists toggles and templates; test sends unsaved values',
      (tester) async {
    Map<String, dynamic>? saved;
    Map<String, dynamic>? tested;
    String? event;
    await tester.binding.setSurfaceSize(const Size(850, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: BarkSettingsCard(
        load: () async => ApiResult.success(settings()),
        save: (values) async {
          saved = Map.from(values);
          return ApiResult.success({'success': true});
        },
        sendTest: (values, type) async {
          tested = Map.from(values);
          event = type;
          return ApiResult.success({'success': true});
        },
      ),
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('error_title')), '自定义 {profile}');
    await tester.ensureVisible(find.text('出错提醒').first);
    await tester.tap(find.widgetWithText(SwitchListTile, '出错提醒'));
    await tester.pump();
    await tester.ensureVisible(find.text('保存设置'));
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(saved?['error_title'], '自定义 {profile}');
    expect(saved?['error_enabled'], false);
    expect(saved?['summary_enabled'], true);
    expect(find.text('有未保存的更改'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('error_body')));
    await tester.enterText(
        find.byKey(const ValueKey('error_body')), '未保存：{content}');
    await tester.ensureVisible(find.text('发送测试'));
    await tester.tap(find.text('发送测试'));
    await tester.pumpAndSettle();
    expect(tested?['error_body'], '未保存：{content}');
    expect(event, 'error');
    expect(saved?['error_body'], '{title}\n{content}');
    expect(find.text('有未保存的更改'), findsOneWidget);
    expect(find.text('Bark 服务已接受测试通知，请在手机上确认。'), findsOneWidget);
  });

  testWidgets('load failure allows retry and prevents overwriting settings',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BarkSettingsCard(
      load: () async {
        loads++;
        return ApiResult.failure('offline');
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('保存设置'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });
}
