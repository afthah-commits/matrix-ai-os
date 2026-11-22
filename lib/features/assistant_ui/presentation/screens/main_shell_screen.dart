import 'package:flutter/material.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/assistant_chat_screen.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/dashboard_screen.dart';

/// Root shell with bottom navigation between Core System Dashboard and AI Assistant Chat.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    AssistantChatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    const primaryEmerald = Color(0xFF10B981);
    const surfaceCard = Color(0xFF0F172A);
    const borderColor = Color(0xFF1F2937);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: surfaceCard,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: surfaceCard,
          indicatorColor: primaryEmerald.withValues(alpha: 0.2),
          elevation: 0,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, color: Colors.white60),
              selectedIcon: Icon(Icons.dashboard, color: primaryEmerald),
              label: 'Core Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined, color: Colors.white60),
              selectedIcon: Icon(Icons.auto_awesome, color: primaryEmerald),
              label: 'AI Assistant',
            ),
          ],
        ),
      ),
    );
  }
}
