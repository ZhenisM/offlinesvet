import 'package:flutter/material.dart';
import 'package:offlinesvet/router/router.dart';
import 'package:offlinesvet/theme/theme.dart';
import 'package:offlinesvet/repositories/products/local_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализируем локальную БД
  await LocalDb.init();

  runApp(MaterialApp(
    theme: darkTheme,
    initialRoute: '/',
    routes: routes,
  ));
}
