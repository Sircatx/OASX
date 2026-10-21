library overview;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/component/log/log_mixin.dart';
import 'package:oasx/component/log/log_widget.dart';
import 'package:oasx/model/script_model.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/api/api_client.dart';

import 'package:styled_widget/styled_widget.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'package:oasx/views/nav/view_nav.dart';
import 'package:oasx/config/translation/i18n_content.dart';

part '../../controller/overview/overview_controller.dart';
part '../../controller/overview/taskitem_model.dart';
part './taskitem_view.dart';

class Overview extends StatelessWidget {
  const Overview({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    NavCtrl navController = Get.find<NavCtrl>();
    OverviewController overviewController =
        Get.find<OverviewController>(tag: navController.selectedScript.value);
    if (context.mediaQuery.orientation == Orientation.portrait) {
      // 竖方向
      return SingleChildScrollView(
        child: <Widget>[
          _SchedulerWidget(controller: overviewController),
          _GameControls(configName: overviewController.name),
          _RunningWidget(controller: overviewController),
          _PendingWidget(controller: overviewController),
          _WaitingWidget(controller: overviewController)
              .constrained(maxHeight: 200),
          LogWidget(
                  key: ValueKey(overviewController.hashCode),
                  controller: overviewController,
                  title: I18n.log.tr,
                  enableCollapse: false)
              .constrained(maxHeight: 500)
              .marginOnly(left: 10, top: 10, right: 10)
        ].toColumn(),
      );
    } else {
      //横方向
      return <Widget>[
        // 左边
        <Widget>[
          _SchedulerWidget(controller: overviewController),
          _GameControls(configName: overviewController.name),
          _RunningWidget(controller: overviewController),
          _PendingWidget(controller: overviewController),
          Expanded(child: _WaitingWidget(controller: overviewController)),
        ].toColumn().constrained(width: 300),
        // 右边
        LogWidget(
                key: ValueKey(overviewController.hashCode),
                controller: overviewController,
                title: I18n.log.tr,
                enableCollapse: false)
            .marginOnly(right: 10)
            .expanded()
      ].toRow();
    }
  }
}

class _GameControls extends StatefulWidget {
  const _GameControls({required this.configName});
  final String configName;

  @override
  State<_GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends State<_GameControls> {
  String? _action;
  bool? _running;
  bool _refreshing = false;
  int _generation = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshStatus());
  }

  @override
  void didUpdateWidget(covariant _GameControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configName != widget.configName) {
      _generation++;
      _running = null;
      _refreshStatus();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (_refreshing || _action != null) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final running = await ApiClient().gameRunning(widget.configName);
      if (mounted && generation == _generation && _action == null) {
        setState(() => _running = running);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _controlGame({required bool stop}) async {
    final name = widget.configName;
    final generation = ++_generation;
    setState(() => _action = stop ? 'stop' : 'start');
    try {
      final result = stop
          ? await ApiClient().stopGame(name)
          : await ApiClient().startGame(name);
      if (mounted && result.isSuccess) {
        if (generation == _generation) setState(() => _running = !stop);
        Get.snackbar(stop ? '关闭游戏' : '启动游戏',
            stop ? '游戏和模拟器已关闭，当前调度器已停止。' : '游戏已启动。');
      }
    } finally {
      if (mounted) {
        setState(() => _action = null);
        _refreshStatus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => <Widget>[
        Text('游戏',
            style: Theme.of(context).textTheme.titleMedium),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (_action != null)
            Padding(padding: const EdgeInsets.only(right: 8),
              child: Tooltip(message: _action == 'stop' ? '正在关闭游戏和模拟器' : '正在启动游戏',
                child: const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_running == true)
            const Tooltip(message: '模拟器运行中',
              child: Icon(Icons.circle, color: Colors.green, size: 8)),
          IconButton(
            tooltip: _running == true ? '打开游戏窗口' : '启动游戏',
            onPressed: _action != null ? null : () => _controlGame(stop: false),
            icon: const Icon(Icons.sports_esports_outlined),
          ),
          if (_running == true || _action == 'stop')
            IconButton(
              tooltip: '关闭游戏和模拟器，并停止当前调度器',
              onPressed: _action != null ? null : () => _controlGame(stop: true),
              icon: const Icon(Icons.power_settings_new),
            ),
        ]),
      ]
        .toRow(mainAxisAlignment: MainAxisAlignment.spaceBetween)
        .constrained(height: 48)
        .paddingOnly(left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
}

class _WaitingWidget extends StatelessWidget {
  const _WaitingWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.waiting.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      Expanded(child: Obx(() {
        return ListView.builder(
            itemBuilder: (context, index) =>
                TaskItemView(controller.scriptModel.waitingTaskList[index]),
            itemCount: controller.scriptModel.waitingTaskList.length);
      }))
    ]
        .toColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
        )
        .paddingAll(8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}

class _PendingWidget extends StatelessWidget {
  const _PendingWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.pending.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      SizedBox(
          height: 140,
          child: Obx(() {
            return ListView.builder(
                itemBuilder: (context, index) =>
                    TaskItemView(controller.scriptModel.pendingTaskList[index]),
                itemCount: controller.scriptModel.pendingTaskList.length);
          }))
    ]
        .toColumn(crossAxisAlignment: CrossAxisAlignment.start)
        .padding(top: 8, bottom: 0, left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}

class _RunningWidget extends StatelessWidget {
  const _RunningWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.running.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      Obx(() {
        return TaskItemView(controller.scriptModel.runningTask.value);
      })
    ]
        .toColumn(crossAxisAlignment: CrossAxisAlignment.start)
        .padding(top: 8, bottom: 0, left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}

class _SchedulerWidget extends StatelessWidget {
  const _SchedulerWidget({
    required this.controller,
  });

  final OverviewController controller;

  @override
  Widget build(BuildContext context) {
    return <Widget>[
      Text(I18n.scheduler.tr,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium),
      <Widget>[
        Obx(() {
          return switch (controller.scriptModel.state.value) {
            ScriptState.running => const SpinKitChasingDots(
                color: Colors.green,
                size: 22,
              ),
            ScriptState.inactive =>
              const Icon(Icons.donut_large, size: 26, color: Colors.grey),
            ScriptState.paused =>
              const Icon(Icons.pause_circle_outline, size: 26, color: Colors.orange),
            ScriptState.warning =>
              const SpinKitDoubleBounce(color: Colors.orange, size: 26),
            ScriptState.updating => const Icon(Icons.browser_updated_rounded,
                size: 26, color: Colors.blue),
          };
        }),
        Obx(() {
          return IconButton(
            tooltip: controller.scriptModel.state.value == ScriptState.paused
                ? '继续调度器' : '暂停调度器',
            onPressed: controller.scriptModel.state.value == ScriptState.running ||
                    controller.scriptModel.state.value == ScriptState.paused
                ? () => controller.scriptService.togglePause(controller.name)
                : null,
            icon: Icon(controller.scriptModel.state.value == ScriptState.paused
                ? Icons.play_arrow_rounded : Icons.pause_rounded),
          );
        }),
        Obx(() {
          return IconButton(
            tooltip: controller.scriptModel.state.value == ScriptState.running ||
                    controller.scriptModel.state.value == ScriptState.paused
                ? '停止调度器' : '启动调度器',
            onPressed: () => {controller.toggleScript()},
            icon: const Icon(Icons.power_settings_new_rounded),
            isSelected:
                controller.scriptModel.state.value == ScriptState.running ||
                controller.scriptModel.state.value == ScriptState.paused,
          );
        }),
      ].toRow(mainAxisAlignment: MainAxisAlignment.center)
    ]
        .toRow(mainAxisAlignment: MainAxisAlignment.spaceBetween)
        .constrained(height: 48)
        .paddingOnly(left: 8, right: 8)
        .card(margin: const EdgeInsets.fromLTRB(10, 0, 10, 10));
  }
}
