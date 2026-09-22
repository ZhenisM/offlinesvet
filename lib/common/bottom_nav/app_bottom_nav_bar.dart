import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:offlinesvet/sync/sync_status_notifier.dart';
import 'package:offlinesvet/common/call_recording_service.dart';
import 'package:offlinesvet/customer/customer_storage.dart';

enum AppBottomTab { profile, scanner, mic, catalog, cart }

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentTab,
    this.onCartTap,
    this.onMicTap,
  });

  final AppBottomTab? currentTab;
  final VoidCallback? onCartTap; // если передан — используется вместо стандартного перехода
  final VoidCallback? onMicTap;  // старт/стоп записи разговора для текущей корзины — задаётся экраном, который знает, какая корзина сейчас активна

  void _goTo(BuildContext context, AppBottomTab tab) {
    if (currentTab == tab) return;
    switch (tab) {
      case AppBottomTab.profile:
        Navigator.of(context).pushReplacementNamed('/profile');
      case AppBottomTab.scanner:
        Navigator.of(context).pushReplacementNamed('/scanner');
      case AppBottomTab.mic:
        onMicTap?.call();
      case AppBottomTab.catalog:
        Navigator.of(context).pushReplacementNamed('/products-list');
      case AppBottomTab.cart:
        if (onCartTap != null) {
          onCartTap!();
        } else {
          Navigator.of(context).pushReplacementNamed('/cart');
        }
    }
  }

  void _goToCatalog(BuildContext context) => _goTo(context, AppBottomTab.catalog);
  void _goToCart(BuildContext context) => _goTo(context, AppBottomTab.cart);

  /// Поведение кнопки микрофона по умолчанию — используется на всех
  /// экранах, которые не передали свой onMicTap явно (checkout_screen.dart
  /// передаёт свой, т.к. там корзина известна точно и сразу; здесь же
  /// берём её из CustomerStorage — глобально сохранённая "активная
  /// корзина", актуальная на любом экране с этой нижней панелью).
  Future<void> _defaultMicTap(BuildContext context) async {
    final service = CallRecordingService.instance;

    if (service.isRecording.value) {
      await service.stopRecordingForCart();
      return;
    }

    final cartId = await CustomerStorage.getActiveCartId();
    if (cartId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет активной корзины — сначала выберите или создайте клиента')),
        );
      }
      return;
    }

    if (!await service.hasPermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нужно разрешение на использование микрофона')),
        );
      }
      return;
    }

    await service.startForCart(cartId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 1. Профиль
              _NavIcon(
                svgAsset: 'assets/icons/document.svg',
                selected: currentTab == AppBottomTab.profile,
                onTap: () => _goTo(context, AppBottomTab.profile),
              ),
              // 2. Сканер
              _NavIcon(
                svgAsset: 'assets/icons/shtrihcode.svg',
                selected: currentTab == AppBottomTab.scanner,
                onTap: () => _goTo(context, AppBottomTab.scanner),
              ),
              // 3. Микрофон — центральная кнопка, старт/стоп записи разговора
              // за текущую корзину (какая корзина активна — решает экран,
              // который передаёт onMicTap; сам виджет этого не знает).
              ValueListenableBuilder<bool>(
                valueListenable: CallRecordingService.instance.isRecording,
                builder: (context, isRecording, _) => GestureDetector(
                  onTap: onMicTap ?? () => _defaultMicTap(context),
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: isRecording ? Colors.red : const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
              // 4. Каталог
              _NavIcon(
                svgAsset: 'assets/icons/shop.svg',
                selected: currentTab == AppBottomTab.catalog,
                onTap: () => _goToCatalog(context),
              ),
              ValueListenableBuilder<int>(
                valueListenable: SyncStatusNotifier.instance,
                builder: (_, count, __) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _NavIcon(
                      svgAsset: 'assets/icons/shopping-cart.svg',
                      selected: currentTab == AppBottomTab.cart,
                      onTap: () => _goToCart(context),
                    ),
                    if (count > 0)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          width: 10, height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    this.icon,
    this.svgAsset,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon; // используется, если svgAsset не задан
  final String? svgAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF4CAF50) : Colors.grey.shade500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: svgAsset != null
            ? SvgPicture.asset(svgAsset!, width: 26, height: 26,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn))
            : Icon(icon, color: color, size: 26),
      ),
    );
  }
}
