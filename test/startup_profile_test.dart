import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/service/startup_profile_runner.dart';
import 'package:oasx/service/websocket_service.dart';
import 'package:oasx/views/home/global_settings_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup is once per process and validates the current profile list',
      () async {
    final calls = <String>[];
    final runner = StartupProfileRunner();
    Future<void> run() => runner.run(
          profiles: ['日常任务', '肝就完了', '新方案'],
          loadProfile: () async => '新方案',
          start: (name) async => calls.add(name),
        );
    await Future.wait([run(), run()]);
    expect(calls, ['新方案']);
    await StartupProfileRunner().run(
      profiles: [],
      loadProfile: () async => '',
      start: (name) async => calls.add(name),
    );
    await expectLater(
        StartupProfileRunner().run(
          profiles: ['日常任务'],
          loadProfile: () async => '已删除',
          start: (name) async => calls.add(name),
        ),
        throwsStateError);
    expect(calls, ['新方案']);
  });

  for (final initialState in [0, 1]) {
    test('websocket confirms state $initialState before automatic start',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final messages = <String>[];
      final sockets = <WebSocket>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((message) {
          messages.add(message as String);
          socket.add('task log');
          socket.add('{"schedule": {}}');
          socket.add('{"state": ${message == 'start' ? 1 : initialState}}');
        });
      });
      final service = WebSocketService();
      final client = await service.connect(
          name: '日常任务', url: 'ws://127.0.0.1:${server.port}/ws/test');
      try {
        expect(await startProfileIfIdle(client), initialState == 0);
        expect(messages,
            initialState == 0 ? ['get_state', 'start'] : ['get_state']);
      } finally {
        await service.closeAll();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    });
  }

  testWidgets('profile selection persists, reloads and discovers new profiles',
      (tester) async {
    var profile = '日常任务';
    var profiles = ['日常任务', '肝就完了'];
    const channel = MethodChannel('oasx/startup');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getSettings') {
        return {
          'launchAtStartup': true,
          'startMinimized': true,
          'startupProfile': profile,
        };
      }
      if (call.method == 'setStartupProfile') {
        profile = call.arguments as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget view() => MaterialApp(
            home: Scaffold(
                body: GlobalSettingsView(
          loadProfiles: () async => profiles,
          barkSettings: const SizedBox.shrink(),
        )));
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('肝就完了').last);
    await tester.pumpAndSettle();
    expect(profile, '肝就完了');
    profiles = [...profiles, '新增方案'];
    await tester.tap(find.byTooltip('刷新任务方案'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增方案').last);
    await tester.pumpAndSettle();
    expect(profile, '新增方案');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        '新增方案');
    profiles = ['日常任务'];
    await tester.tap(find.byTooltip('刷新任务方案'));
    await tester.pumpAndSettle();
    expect(find.text('新增方案（已不存在）'), findsOneWidget);
  });
}
