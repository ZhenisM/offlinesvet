import 'package:flutter/material.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Сканер', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 72, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Сканер в разработке',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54),
            ),
            SizedBox(height: 8),
            Text(
              'Функция будет доступна в следующем обновлении',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.scanner),
    );
  }
}
