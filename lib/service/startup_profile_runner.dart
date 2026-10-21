import 'dart:convert';

import 'package:oasx/service/websocket_service.dart';

/// One automatic run per app process, including when the login page is reopened.
class StartupProfileRunner {
  bool _handled = false;

  Future<void> run({
    required List<String> profiles,
    required Future<String> Function() loadProfile,
    required Future<void> Function(String) start,
  }) async {
    if (_handled) return;
    _handled = true;
    final profile = await loadProfile();
    if (profile.isEmpty) return;
    if (!profiles.contains(profile)) {
      throw StateError('启动方案“$profile”已不存在，请在全局设置中重新选择。');
    }
    await start(profile);
  }
}

/// Returns false when the selected profile is already running.
Future<bool> startProfileIfIdle(WebSocketClient client) async {
  Map? stateMessage(dynamic message) {
    if (message is! String || !message.startsWith('{')) return null;
    final data = jsonDecode(message);
    return data is Map && data.containsKey('state') ? data : null;
  }

  final state = await client.sendAndWaitUntil<Map>(
    'get_state',
    check: (message) async => stateMessage(message) != null,
    onResult: (message) => stateMessage(message)!,
  );
  if (state == null) throw StateError('无法确认“${client.name}”的运行状态，请稍后手动启动。');
  // Starting a running backend profile would stop and restart it.
  if (state['state'] == 1) return false;
  final started = await client.sendAndWaitUntil<Map>(
    'start',
    check: (message) async => stateMessage(message)?['state'] == 1,
    onResult: (message) => stateMessage(message)!,
  );
  if (started == null) throw StateError('“${client.name}”未确认启动，请检查任务日志。');
  return true;
}
