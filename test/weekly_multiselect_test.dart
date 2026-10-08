import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/views/args/args_view.dart';

void main() {
  tearDown(() async => Get.reset());

  testWidgets('weekday chips save multiple days and prevent empty selection',
      (tester) async {
    final controller = Get.put(ArgsController());
    final argument = ArgumentModel.fromJson({
      'name': 'weekly_day',
      'type': 'multi_enum',
      'value': ['星期一'],
      'enumEnum': ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    });
    controller.groupsData.value = {
      'scheduler': GroupsModel(groupName: 'scheduler', members: [argument]),
    };
    final saved = <dynamic>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ArgumentView(
      index: 0,
      getGroupName: () => 'scheduler',
      setArgument: (_, __, group, name, type, value) {
        expect(group, 'scheduler');
        expect(name, 'weekly_day');
        expect(type, 'multi_enum');
        saved.add(jsonDecode(value as String));
      },
    ))));
    expect(find.byType(FilterChip), findsNWidgets(7));
    expect(tester.widgetList<FilterChip>(find.byType(FilterChip))
        .every((chip) => chip.onSelected != null), isTrue);
    await tester.tap(find.text('星期一'));
    await tester.pump();
    expect(saved, isEmpty);
    await tester.tap(find.text('星期三'));
    await tester.pump();
    expect(saved.last, ['星期一', '星期三']);
    await tester.tap(find.text('星期一'));
    await tester.pump();
    expect(saved.last, ['星期三']);
    await tester.tap(find.text('星期三'));
    await tester.pump();
    expect(saved.length, 2);
  });
}
