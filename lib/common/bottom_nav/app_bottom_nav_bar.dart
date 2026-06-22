import 'package:flutter/material.dart';

/// Какая вкладка активна на нижней панели — используется для подсветки
/// и для решения, нужно ли вообще переходить при нажатии (если уже там).
enum AppBottomTab { catalog, cart }

/// Плавающая нижняя панель навигации — общая для каталога и мультикорзины.
/// На главном экране, экранах авторизации и поиска клиента панель не
/// используется вообще (эти экраны просто не оборачиваются в этот виджет).
///
/// Сейчас реализованы только 2 рабочие иконки (Каталог, Корзина).
/// Остальные позиции на референсном дизайне — заглушки на будущее,
/// сюда не добавляются, пока не появится реальная функция за ними —
/// нет смысла показывать неактивные кнопки, которые выглядят как баг.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key, required this.currentTab});

  final AppBottomTab currentTab;

  void _goToCatalog(BuildContext context) {
    if (currentTab == AppBottomTab.catalog) return;
    Navigator.of(context).pushReplacementNamed('/products-list');
  }

  void _goToCart(BuildContext context) {
    if (currentTab == AppBottomTab.cart) return;
    Navigator.of(context).pushReplacementNamed('/cart');
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
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavIcon(
                icon: Icons.storefront_outlined,
                selected: currentTab == AppBottomTab.catalog,
                onTap: () => _goToCatalog(context),
              ),
              _NavIcon(
                icon: Icons.shopping_cart_outlined,
                selected: currentTab == AppBottomTab.cart,
                onTap: () => _goToCart(context),
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
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          color: selected ? const Color(0xFF4CAF50) : Colors.grey.shade500,
          size: 26,
        ),
      ),
    );
  }
}
