import 'package:siz/core/ui/room_navigation_bar.dart';
import 'package:siz/features/barbers/presentation/screens/barbers_screen.dart';
import 'package:siz/features/clients/presentation/screens/clients_screen.dart';
import 'package:siz/features/finance/presentation/screens/finance_screen.dart';
import 'package:siz/features/floor_plan/presentation/screens/floor_plan_screen.dart';
import 'package:siz/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  static const _floorIndex = 2;

  int _currentIndex = _floorIndex;

  static const List<Widget> _screens = [
    SettingsScreen(),
    FinanceScreen(),
    FloorPlanScreen(),
    BarbersScreen(),
    ClientsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: RoomNavigationBar(
        items: const [
          RoomNavItem(Icons.settings_outlined, Icons.settings, 'Settings'),
          RoomNavItem(
            Icons.monetization_on_outlined,
            Icons.monetization_on,
            'Finance',
          ),
          RoomNavItem(Icons.chair_outlined, Icons.chair_outlined, 'Floor'),
          RoomNavItem(Icons.groups_outlined, Icons.groups, 'Team'),
          RoomNavItem(Icons.badge_outlined, Icons.badge, 'Clients'),
        ],
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
