import 'package:flutter/material.dart';
import 'package:oasx/api/api_client.dart';

class BarkSettingsCard extends StatefulWidget {
  const BarkSettingsCard({super.key, this.load, this.save, this.sendTest});

  final Future<ApiResult<dynamic>> Function()? load;
  final Future<ApiResult<dynamic>> Function(Map<String, dynamic>)? save;
  final Future<ApiResult<dynamic>> Function(Map<String, dynamic>, String)?
      sendTest;

  @override
  State<BarkSettingsCard> createState() => _BarkSettingsCardState();
}

class _BarkSettingsCardState extends State<BarkSettingsCard> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  Map<String, dynamic> _values = {};
  bool _loading = true;
  bool _busy = false;
  bool _showAddress = false;
  bool _dirty = false;
  String? _message;
  bool _failed = false;
  String _testEvent = 'error';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await (widget.load ?? ApiClient().loadBarkSettings)();
      if (!mounted) return;
      if (!result.isSuccess || result.data is! Map) {
        throw StateError('load');
      }
      _values = Map<String, dynamic>.from(result.data as Map);
      for (final entry in _values.entries) {
        if (entry.value is String) {
          (_fields[entry.key] ??= TextEditingController()).text = entry.value;
        }
      }
      setState(() {
        _loading = false;
        _message = null;
        _failed = false;
        _dirty = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _message = '无法读取 Bark 设置，请确认后端已更新并连接正常。';
        });
      }
    }
  }

  Map<String, dynamic> _settings() => {
        ..._values,
        for (final entry in _fields.entries) entry.key: entry.value.text,
      };

  Future<void> _submit({bool test = false}) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final settings = _settings();
      final result = test
          ? await (widget.sendTest ?? ApiClient().testBarkSettings)(
              settings, _testEvent)
          : await (widget.save ?? ApiClient().saveBarkSettings)(settings);
      if (!mounted) return;
      final data = result.data;
      final success =
          result.isSuccess && data is Map && data['success'] == true;
      setState(() {
        _failed = !success;
        _message = success
            ? (test ? 'Bark 服务已接受测试通知，请在手机上确认。' : '已保存，下次通知立即使用新设置。')
            : (data is Map ? data['message']?.toString() : null) ??
                '操作失败，请检查设置、网络和后端连接。';
        if (success && !test) _dirty = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '操作失败，请检查网络和后端连接。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _toggle(String key, String title, String subtitle) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: _values[key] == true,
        onChanged: _busy
            ? null
            : (value) => setState(() {
                  _values[key] = value;
                  _dirty = true;
                }),
      );

  Widget _field(String key, String label,
          {String? hint, int lines = 1, bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(
          key: ValueKey(key),
          controller: _fields[key],
          enabled: !_busy,
          maxLines: lines,
          obscureText: key == 'endpoint' && !_showAddress,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: label,
            helperText: hint,
            helperMaxLines: 3,
            suffixIcon: key == 'endpoint'
                ? IconButton(
                    tooltip: _showAddress ? '隐藏 Bark 地址' : '显示 Bark 地址',
                    onPressed: () =>
                        setState(() => _showAddress = !_showAddress),
                    icon: Icon(
                        _showAddress ? Icons.visibility_off : Icons.visibility),
                  )
                : null,
          ),
          onChanged: (_) => setState(() => _dirty = true),
          validator: (value) {
            final text = (value ?? '').trim();
            if (required && text.isEmpty) return '请填写通知模板';
            if (key == 'endpoint' && text.isNotEmpty) {
              final uri = Uri.tryParse(text);
              if (uri == null ||
                  !['http', 'https'].contains(uri.scheme) ||
                  uri.host.isEmpty ||
                  uri.path.replaceAll('/', '').isEmpty ||
                  uri.hasQuery ||
                  uri.hasFragment ||
                  uri.userInfo.isNotEmpty ||
                  uri.path.endsWith('/push')) {
                return '请填写包含设备 Key 的 Bark 地址，不含正文或查询参数';
              }
            }
            return null;
          },
        ),
      );

  Widget _level(String key, String label) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: DropdownButtonFormField<String>(
          value: _values[key] as String?,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'passive', child: Text('静默')),
            DropdownMenuItem(value: 'active', child: Text('普通提醒')),
            DropdownMenuItem(value: 'timeSensitive', child: Text('时效性提醒')),
            DropdownMenuItem(value: 'critical', child: Text('重要警告（需手机授权）')),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _values[key] = value;
                    _dirty = true;
                  }),
        ),
      );

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bark 通知', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('全局应用于所有脚本的出错提醒，以及日常任务的定时摘要。保存后生效。'),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator()),
            if (!_loading && _values.isEmpty)
              TextButton(onPressed: _load, child: const Text('重试')),
            if (!_loading && _values.isNotEmpty)
              Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _toggle('enabled', '启用 Bark 通知', '关闭后不发送定时摘要和全局出错提醒。'),
                      _field('endpoint', 'Bark 地址（含设备 Key）',
                          hint:
                              '留空复用现有 Bark 通道；自定义示例：https://api.day.app/你的Key'),
                      _field('group', '通知分组'),
                      _field('sound', '铃声',
                          hint: '留空使用默认铃声；可填写 Bark 铃声名称，例如 alarm。'),
                      _field('icon', '通知图标 URL'),
                      const SizedBox(height: 20),
                      const Text(
                          '模板变量：{profile} 配置名 · {title} 任务/主题 · {content} 原始内容 · {date} 日期 · {time} 时间'),
                      const SizedBox(height: 8),
                      _toggle('summary_enabled', '定时摘要', '沿用现有计划任务的发送时间。'),
                      _field('summary_title', '摘要标题', required: true),
                      _field('summary_body', '摘要正文', lines: 3, required: true),
                      _level('level', '摘要提醒级别'),
                      const SizedBox(height: 16),
                      _toggle('error_enabled', '出错提醒',
                          '设备连接恢复失败、游戏卡住、脚本异常或连续失败时通知。'),
                      _field('error_title', '出错标题', required: true),
                      _field('error_body', '出错正文', lines: 3, required: true),
                      _level('error_level', '出错提醒级别'),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: _testEvent,
                        decoration: const InputDecoration(
                            labelText: '测试通知类型', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'error', child: Text('出错提醒')),
                          DropdownMenuItem(
                              value: 'summary', child: Text('定时摘要')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _testEvent = value!),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton(
                                onPressed: _busy ? null : () => _submit(),
                                child: const Text('保存设置')),
                            OutlinedButton(
                                onPressed:
                                    _busy ? null : () => _submit(test: true),
                                child: const Text('发送测试')),
                            if (_dirty) const Text('有未保存的更改'),
                          ]),
                      const SizedBox(height: 8),
                      const Text('发送测试使用当前填写的内容，不保存设置；即使通知开关关闭也可测试。'),
                    ]),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!,
                    style: TextStyle(
                        color: _failed
                            ? Theme.of(context).colorScheme.error
                            : null)),
              ),
          ]),
        ),
      );
}
