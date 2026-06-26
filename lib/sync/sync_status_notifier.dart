import 'package:flutter/foundation.dart';
import 'offline_queue.dart';

/// Глобальный статус синхронизации.
/// Подписываясь на него виджеты узнают сколько действий ожидает отправки.
class SyncStatusNotifier extends ValueNotifier<int> {
  SyncStatusNotifier._() : super(0);
  static final instance = SyncStatusNotifier._();

  /// Обновить счётчик из БД
  Future<void> refresh() async {
    value = await OfflineQueue.count();
  }

  /// Есть ли несинхронизированные данные
  bool get hasPending => value > 0;
}
