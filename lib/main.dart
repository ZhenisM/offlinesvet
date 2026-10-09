import 'package:flutter/material.dart';
import 'package:offlinesvet/router/router.dart';
import 'package:offlinesvet/theme/theme.dart';
import 'package:offlinesvet/repositories/products/local_db.dart';
import 'package:offlinesvet/sync/sync_service.dart';
import 'package:offlinesvet/catalog/compare/compare_store.dart';
import 'package:offlinesvet/customer/bad_lead_queue.dart';
import 'package:offlinesvet/foursell/foursell_upload_queue.dart';
import 'package:offlinesvet/cart/cart_local_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализируем локальную БД
  await LocalDb.init();

  // Инициализируем хранилище сравнения
  await CompareStore.instance.init();

  // Запускаем сервис синхронизации offline-очереди
  // Он слушает connectivity и отправляет накопленные действия при появлении сети
  SyncService.instance.start();

  // Подхватываем некачественные лиды, оставшиеся неотправленными с
  // прошлого запуска (например, приложение закрыли при плохом интернете).
  BadLeadQueue.instance.restore();

  // Записи разговоров, не доехавшие до 4sell в прошлый запуск.
  FourSellUploadQueue.instance.restore();

  // Значок количества товаров у корзины в нижнем меню.
  CartBadge.refresh();

  runApp(MaterialApp(
    theme: darkTheme,
    initialRoute: '/',
    routes: routes,
  ));
}
