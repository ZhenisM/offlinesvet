import 'package:flutter/widgets.dart';
import 'package:offlinesvet/common/call_recording_service.dart';

/// Наблюдатель навигации — подключён в MaterialApp (main.dart).
final RouteObserver<ModalRoute<void>> recordingRouteObserver = RouteObserver<ModalRoute<void>>();

/// Экран, у которого есть свой этап консультации (каталог, корзина,
/// оформление). Этап ставится при открытии экрана И при возврате на него
/// кнопкой «Назад» — иначе после «Оформление → Назад → Корзина» этап так и
/// оставался бы «checkout».
mixin RecordingStageAware<T extends StatefulWidget> on State<T> implements RouteAware {
  /// Этап этого экрана: CallRecordingService.stageCatalog / stageCart / …
  String get recordingStage;

  ModalRoute<void>? _stageRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _stageRoute) {
      if (_stageRoute != null) recordingRouteObserver.unsubscribe(this);
      _stageRoute = route;
      recordingRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    recordingRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => CallRecordingService.instance.setStage(recordingStage, reason: '${recordingStage}_opened');

  @override
  void didPopNext() => CallRecordingService.instance.setStage(recordingStage, reason: 'returned');

  @override
  void didPop() {}

  @override
  void didPushNext() {}
}
