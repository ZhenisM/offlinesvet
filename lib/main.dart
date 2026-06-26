import 'package:flutter/material.dart';
import 'package:offlinesvet/router/router.dart';
import 'package:offlinesvet/theme/theme.dart';
import 'package:offlinesvet/repositories/products/local_db.dart';
import 'package:offlinesvet/sync/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализируем локальную БД
  await LocalDb.init();

  // Запускаем сервис синхронизации offline-очереди
  // Он слушает connectivity и отправляет накопленные действия при появлении сети
  SyncService.instance.start();

  runApp(MaterialApp(
    theme: darkTheme,
    initialRoute: '/',
    routes: routes,
  ));
}
