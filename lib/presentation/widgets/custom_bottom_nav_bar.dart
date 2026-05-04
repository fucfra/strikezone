import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(top: BorderSide(color: Colors.grey.shade800)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.surfaceColor,
        selectedItemColor: AppTheme.accentGreen,
        unselectedItemColor: AppTheme.secondaryText,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.science), label: 'TEST'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'REPORT'),
          BottomNavigationBarItem(icon: Icon(Icons.timeline), label: 'SEGNALI'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'STORICO'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'SETTINGS',
          ),
        ],
      ),
    );
  }
}
