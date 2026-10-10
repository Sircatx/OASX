import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oasx/utils/platform_utils.dart';

class GlobalSettingsView extends StatefulWidget {
  const GlobalSettingsView({super.key});

  @override
  State<GlobalSettingsView> createState() => _GlobalSettingsViewState();
}

class _GlobalSettingsViewState extends State<GlobalSettingsView> {
  static const _channel = MethodChannel('oasx/startup');
  bool _launchAtStartup = false;
  bool _startMinimized = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!PlatformUtils.isWindows) {
      setState(() {
        _busy = false;
      });
      return;
    }
    try {
      final values =
          await _channel.invokeMapMethod<String, dynamic>('getSettings');
      if (!mounted) return;
      setState(() {
        _launchAtStartup = values?['launchAtStartup'] == true;
        _startMinimized = values?['startMinimized'] == true;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '无法读取启动设置，请重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _save(String method, bool value) async {
    setState(() {
      _busy = true;
    });
    try {
      await _channel.invokeMethod<void>(method, value);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = PlatformUtils.isWindows && !_busy && _error == null;
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('全局设置', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  SwitchListTile(
                    title: const Text('开机启动'),
                    subtitle: const Text('登录 Windows 后自动打开 OASX。'),
                    value: _launchAtStartup,
                    onChanged: enabled
                        ? (value) => _save('setLaunchAtStartup', value)
                        : null,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text('最小化启动'),
                    subtitle: const Text('下次启动时收起到系统托盘，点击托盘图标可恢复窗口。'),
                    value: _startMinimized,
                    onChanged: enabled
                        ? (value) => _save('setStartMinimized', value)
                        : null,
                  ),
                ]),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (!PlatformUtils.isWindows)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('启动设置仅支持 Windows。')),
              if (_error != null)
                Row(children: [
                  Expanded(child: Text(_error!)),
                  TextButton(
                      onPressed: _busy ? null : _load, child: const Text('重试')),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
