import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/notifications/presentation/dashboard_screen.dart';
import 'features/notifications/providers/dashboard_provider.dart';

const _notificationAccessChannel = MethodChannel(
  'com.prism.engine/notification_access',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0E14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: PrismEngineApp()));
}

class PrismEngineApp extends StatelessWidget {
  const PrismEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prism Engine',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _NotificationListenerShell(),
    );
  }
}

class _NotificationListenerShell extends ConsumerStatefulWidget {
  const _NotificationListenerShell();

  @override
  ConsumerState<_NotificationListenerShell> createState() =>
      _NotificationListenerShellState();
}

class _NotificationListenerShellState
    extends ConsumerState<_NotificationListenerShell>
    with WidgetsBindingObserver {
  bool _listenerReady = false;
  bool _starting = false;
  bool _permissionBannerShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startListening();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_listenerReady) {
        _startListening();
      } else {
        ref.read(dashboardProvider.notifier).refresh();
      }
    }
  }

  Future<void> _startListening() async {
    if (_starting || _listenerReady) return;
    _starting = true;
    try {
      final hasPermission = await _notificationAccessChannel.invokeMethod<bool>(
        'hasPermission',
      );
      if (!mounted) return;
      if (hasPermission != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showPermissionBanner();
        });
        return;
      }

      if (_permissionBannerShown) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        _permissionBannerShown = false;
      }

      _listenerReady = true;
    } finally {
      _starting = false;
    }
  }

  void _showPermissionBanner() {
    if (!mounted || _permissionBannerShown) return;
    _permissionBannerShown = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFF1E2430),
        leading: const Icon(
          Icons.notifications_off_rounded,
          color: Color(0xFFF59E0B),
        ),
        content: const Text(
          'Notification Access is required to classify and capture notifications.',
          style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                _notificationAccessChannel.invokeMethod<void>('openSettings'),
            child: const Text(
              'GRANT ACCESS',
              style: TextStyle(
                color: Color(0xFF7C3AED),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const DashboardScreen();
}
