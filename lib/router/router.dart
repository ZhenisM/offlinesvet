import 'package:flutter/material.dart';
import 'package:offlinesvet/catalog/product_list/view/product_list_screen.dart';
import 'package:offlinesvet/catalog/product_item/view/product_item_screen.dart';
import 'package:offlinesvet/cart/view/cart_screen.dart';
import 'package:offlinesvet/pages/home.dart';
import 'package:offlinesvet/pages/main_screen.dart';
import 'package:offlinesvet/auth/login_screen.dart';
import 'package:offlinesvet/auth/splash_screen.dart';

final routes = {
  '/': (context) => SplashScreen(),
  '/home': (context) => MainScreen(),
  '/auth': (context) => LoginScreen(),
  '/products-list': (context) => const ProductListScreen(),
  '/products-item': (context) => const ProductItemScreen(),
  '/cart': (context) => const CartScreen(),
};