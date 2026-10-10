import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/views/args/args_view.dart';

class TestMessages with DynamicMessages {}

void main() {
  tearDown(() async => Get.reset());

  testWidgets('new translations refresh the displayed role and dropdown',
      (tester) async {
    final messages = TestMessages();
    final controller = Get.put(ArgsController());
    controller.groupsData.value = {
      'evo_zone_config': GroupsModel(groupName: 'evo_zone_config', members: [
        ArgumentModel.fromJson({
          'name': 'user_status',
          'type': 'enum',
          'value': 'alone',
          'enumEnum': ['leader', 'member', 'alone', 'wild'],
        }),
      ]),
    };
    await tester.pumpWidget(GetMaterialApp(
      translations: messages.messages,
      locale: const Locale('zh', 'CN'),
      home: Scaffold(
        body: ArgumentView(
          index: 0,
          getGroupName: () => 'evo_zone_config',
          setArgument: (_, __, ___, ____, _____, ______) {},
        ),
      ),
    ));
    expect(find.text('alone'), findsOneWidget);

    messages.applyAdditionalTranslate({
      'zh-CN': {
        'leader': '队长',
        'member': '队员',
        'alone': '单独刷',
        'wild': '野队（未实现）',
      },
    });
    final refreshed = Get.updateLocale(const Locale('zh', 'CN'));
    await tester.pump();
    await tester.pumpAndSettle();
    await refreshed;
    expect(find.text('alone'), findsNothing);
    expect(find.text('单独刷'), findsOneWidget);
    await tester.tap(find.text('单独刷'));
    await tester.pumpAndSettle();
    expect(find.text('队长'), findsOneWidget);
    expect(find.text('队员'), findsOneWidget);
    expect(find.text('野队（未实现）'), findsOneWidget);
    final field = controller.groupsData.value['evo_zone_config']!.members.first
        as ArgumentModel;
    expect(field.value, 'alone');
  });

  test('refresh preserves existing translations and replaces old values', () {
    final messages = TestMessages();
    final original = messages.messages.keys['zh_CN']!['user_status'];
    messages.applyAdditionalTranslate({'zh-CN': {'alone': '旧标签'}});
    messages.applyAdditionalTranslate({'zh-CN': {'alone': '单独刷'}});
    expect(messages.messages.keys['zh_CN']!['user_status'], original);
    Get.locale = const Locale('zh', 'CN');
    expect('alone'.tr, '单独刷');
  });
}
