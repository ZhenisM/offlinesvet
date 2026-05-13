import 'package:flutter/material.dart';
import 'package:offlinesvet/router/router.dart';
import 'package:offlinesvet/theme/theme.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(
    theme: darkTheme,
    initialRoute: '/',
    routes: routes,
  ));
}

