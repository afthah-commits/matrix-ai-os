import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/features/ai_brain/presentation/providers/ai_brain_providers.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/controllers/chat_controller.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/assistant_chat_screen.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/dashboard_screen.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/wake_word_bridge_service.dart';

/// Root shell with bottom navigation between Core System Dashboard and AI Assistant Chat.
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;
  StreamSubscription<WakeWordEvent>? _wakeSub;

  final List<Widget> _screens = const [
    DashboardScreen(),
    AssistantChatScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bridge = ref.read(wakeWordBridgeServiceProvider);
      _wakeSub = bridge.wakeWordEvents.listen(_handleWakeEvent);
    });
  }

  void _handleWakeEvent(WakeWordEvent event) {
    if (!mounted) return;
    setState(() {
      _currentIndex = 1;
    });

    final query = event.initialQuery?.trim();
    if (query != null && query.isNotEmpty) {
      ref.read(chatControllerProvider.notifier).sendMessage(query);
    } else {
      final voice = ref.read(voiceAssistantServiceProvider);
      voice.startListening(
        onResult: (text) {
          if (text.trim().isNotEmpty) {
            ref.read(chatControllerProvider.notifier).sendMessage(text);
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _wakeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Automatically pause/resume native wake-word service during active STT mic usage
    ref.listen(voiceAssistantServiceProvider, (prev, next) {
      if (prev?.isListening != next.isListening) {
        final bridge = ref.read(wakeWordBridgeServiceProvider);
        if (next.isListening) {
          bridge.notifyVoiceStarted();
        } else {
          bridge.notifyVoiceStopped();
        }
      }
    });

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
