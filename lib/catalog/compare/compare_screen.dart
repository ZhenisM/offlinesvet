import 'package:flutter/material.dart';
import 'package:offlinesvet/common/animated_search_bar.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

class CompareScreen extends StatelessWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Сравнение'),
        centerTitle: false,
        actions: const [CatalogSearchBar(), SizedBox(width: 8)],
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.compare_arrows, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Нет товаров для сравнения',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Нажмите на иконку сравнения в карточке товара',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            textAlign: TextAlign.center),
        ]),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: null),
    );
  }
}
