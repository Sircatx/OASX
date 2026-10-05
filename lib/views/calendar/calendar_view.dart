import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/views/nav/view_nav.dart';

class ScriptCalendar extends StatefulWidget {
  final String script;
  final Future<ApiResult<Map<String, dynamic>>> Function(String, String)?
      loadCalendar;
  const ScriptCalendar({super.key, required this.script, this.loadCalendar});

  @override
  State<ScriptCalendar> createState() => _ScriptCalendarState();
}

class _ScriptCalendarState extends State<ScriptCalendar> {
  static DateTime get _now =>
      DateTime.now().toUtc().add(const Duration(hours: 8));
  late DateTime _week;
  Map<String, List<Map<String, dynamic>>> _days = {};
  List<String> _warnings = [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _week = _weekStart(_now);
    _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loadCalendar ?? ApiClient().getScriptCalendar;
      final result = await loader(widget.script, _dateKey(_week))
          .timeout(const Duration(seconds: 10));
      if (!result.isSuccess) {
        throw StateError(result.error ?? '无法读取脚本日历');
      }
      final days = <String, List<Map<String, dynamic>>>{};
      for (final raw in result.data!['events'] as List) {
        final event = Map<String, dynamic>.from(raw);
        final date = (event['at'] as String).substring(0, 10);
        (days[date] ??= []).add(event);
      }
      final warnings = (result.data!['warnings'] as List).cast<String>();
      if (!mounted || id != _requestId) return;
      setState(() {
        _days = days;
        _warnings = warnings;
      });
    } catch (error) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = error is TimeoutException
            ? '加载超时，后端暂未响应。请稍后重试。'
            : '无法加载脚本日历：$error';
      });
    } finally {
      if (mounted && id == _requestId) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _move(int offset) {
    setState(() {
      _week = _week.add(Duration(days: offset * 7));
    });
    _load();
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  DateTime _weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));

  String _taskKey(Map<String, dynamic> event) {
    final raw = event['task'] as String;
    final menus = Get.find<NavCtrl>().useablemenus;
    return menus.firstWhere(
        (menu) =>
            menu.replaceAll('_', '').toLowerCase() ==
            raw.replaceAll('_', '').toLowerCase(),
        orElse: () => raw);
  }

  String _label(Map<String, dynamic> event) => switch (event['kind']) {
        'next' => '下一次',
        'weekly' => '每周计划',
        'overdue' => '待运行',
        _ => '预计',
      };

  String _time(Map<String, dynamic> event) =>
      (event['at'] as String).substring(11, 16);

  void _showDay(DateTime date) {
    final events = _days[_dateKey(date)] ?? [];
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text('${date.month}月${date.day}日 · ${events.length} 项计划'),
              content: SizedBox(
                  width: 480,
                  height: 400,
                  child: events.isEmpty
                      ? const Center(child: Text('当天没有已启用的任务计划'))
                      : ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (_, index) {
                            final event = events[index];
                            final task = _taskKey(event);
                            final float = event['float_time'];
                            return ListTile(
                              leading: Text(
                                  (event['at'] as String).substring(11),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              title: Text(task.tr),
                              subtitle: Text(
                                  '${_label(event)}${float != '00:00:00' ? ' · 随机延迟上限 $float' : ''}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(dialogContext);
                                Get.find<NavCtrl>().switchContent(task);
                              },
                            );
                          })),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = _week.add(const Duration(days: 6));
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('脚本日历 · 周视图',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                    tooltip: '上周',
                    onPressed:
                        _week.subtract(const Duration(days: 7)).year < 2000
                            ? null
                            : () => _move(-1),
                    icon: const Icon(Icons.chevron_left)),
                Text(
                    '${_week.year}年${_week.month}月${_week.day}日 — ${last.year != _week.year ? '${last.year}年' : ''}${last.month}月${last.day}日',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    tooltip: '下周',
                    onPressed: _week.add(const Duration(days: 7)).year > 2100
                        ? null
                        : () => _move(1),
                    icon: const Icon(Icons.chevron_right)),
                TextButton(
                    onPressed: () {
                      setState(() {
                        _week = _weekStart(_now);
                      });
                      _load();
                    },
                    child: const Text('本周')),
                IconButton(
                    tooltip: '刷新计划',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh)),
              ]),
          const SizedBox(height: 8),
          Text('${widget.script} · 北京时间 · 仅加载当前显示的 7 天',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          const Text('周期计划为预计时间；实际运行受队列、随机延迟和脚本开关影响。此视图为计划，不是运行记录。',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Expanded(
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('重试'))
            ]))),
          if (!_loading && _error == null)
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              final dayWidth =
                  (constraints.maxWidth / 7).clamp(115.0, double.infinity);
              return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                      width: dayWidth * 7,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var day = 0; day < 7; day++)
                              Expanded(
                                  child: _dayColumn(
                                      _week.add(Duration(days: day)), colors)),
                          ])));
            })),
          for (final warning in _warnings)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(warning, style: TextStyle(color: colors.error))),
        ]));
  }

  Widget _dayColumn(DateTime date, ColorScheme colors) {
    final today = _dateKey(date) == _dateKey(_now);
    final events = _days[_dateKey(date)] ?? [];
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1];
    return Card(
        margin: const EdgeInsets.all(2),
        elevation: 0,
        color: today ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color: today ? colors.primary : colors.outlineVariant)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
              onTap: () => _showDay(date),
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('周$weekday${today ? ' · 今天' : ''}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color:
                                    today ? colors.primary : colors.onSurface)),
                        const SizedBox(height: 4),
                        Text('${date.month}月${date.day}日',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('${events.length} 项计划',
                            style: const TextStyle(fontSize: 11)),
                      ]))),
          const Divider(height: 1),
          Expanded(
              child: events.isEmpty
                  ? const Center(
                      child: Text('暂无计划', style: TextStyle(fontSize: 12)))
                  : ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final task = _taskKey(event);
                        return InkWell(
                            onTap: () =>
                                Get.find<NavCtrl>().switchContent(task),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 9),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_time(event),
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                              color: event['kind'] == 'overdue'
                                                  ? colors.error
                                                  : colors.primary)),
                                      const SizedBox(height: 3),
                                      Text(task.tr,
                                          style: const TextStyle(fontSize: 12)),
                                      Text(_label(event),
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: colors.onSurfaceVariant)),
                                    ])));
                      })),
        ]));
  }
}
