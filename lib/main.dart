import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/database/database_helper.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/providers/dashboard_provider.dart';
import 'features/notifications/presentation/dashboard_screen.dart';
import 'features/notifications/services/axio_parser.dart';
import 'features/notifications/services/dedup_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Background Isolate Callback (GUARANTEED to run even when UI is closed)
//
// This is called by Android in a SEPARATE Dart isolate.
// CANNOT access Flutter widgets, BuildContext, or Riverpod.
// Only safe operations: SQLite writes, IsolateNameServer sends.
//
// @pragma('vm:entry-point') prevents tree-shaking in release builds.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void _notificationCallback(NotificationEvent evt) {
  // Forward to the UI isolate if it's running (non-null port = app is open).
  final SendPort? sp =
      IsolateNameServer.lookupPortByName('prism_bg_to_ui_port');
  if (sp != null) {
    sp.send(evt);
  }
  // Note: Background-only DB writes are NOT done here because sqflite
  // requires the full Flutter engine. The UI isolate handles persistence.
  // If you need background persistence without UI, use a platform channel
  // with a native SQLite implementation instead.
}

// ─────────────────────────────────────────────────────────────────────────────
// App Entry Point
// ─────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize plugin BEFORE runApp so the callback is registered
  // before any notification events can arrive.
  NotificationsListener.initialize(callbackHandle: _notificationCallback);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0B0E14),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: PrismEngineApp()));
}

// ─────────────────────────────────────────────────────────────────────────────
// Root App
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Notification Listener Shell
//
// Architecture (per official plugin docs):
//   1. Plugin background isolate → _notificationCallback (always runs)
//   2. _notificationCallback → IsolateNameServer SendPort → ReceivePort here
//   3. ReceivePort.listen() → _onNotificationEvent (parses, saves, refreshes UI)
//
// Additionally, the plugin's built-in receivePort is used as a fallback:
//   NotificationsListener.receivePort.listen(_onNotificationEvent)
//   This fires when the app IS in the foreground via the platform channel.
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationListenerShell extends ConsumerStatefulWidget {
  const _NotificationListenerShell();

  @override
  ConsumerState<_NotificationListenerShell> createState() =>
      _NotificationListenerShellState();
}

class _NotificationListenerShellState
    extends ConsumerState<_NotificationListenerShell> {
  ReceivePort? _receivePort;

  // ── Package allowlist ───────────────────────────────────────────────────
  // Covers all major Indian bank SMS apps, UPI apps, and wallet apps.
  // Bank SMS arrives via the device's default messaging app package.
  static const Set<String> _allowedPackages = {
    // Default SMS / Messaging apps (bank SMS arrives here)
    'com.google.android.apps.messaging',  // Google Messages
    'com.android.mms',                    // AOSP Messages
    'com.samsung.android.messaging',      // Samsung Messages
    'com.sonyericsson.conversations',     // Xperia Messages
    'com.motorola.messaging',             // Motorola Messages
    'com.oneplus.mms',                    // OnePlus Messages
    'com.coloros.mms',                    // OPPO Messages
    'com.miui.messaging',                 // Xiaomi MIUI Messages
    'com.qti.qmmi',                       // Qualcomm SMS
    'com.android.messaging',              // Generic Android Messages
    // UPI Payment Apps
    'com.google.android.apps.nbu.paisa.user', // Google Pay
    'com.phonepe.app',                         // PhonePe
    'net.one97.paytm',                         // Paytm
    'in.org.npci.upiapp',                      // BHIM
    'com.mobikwik_new',                        // MobiKwik
    'com.freecharge.android',                  // FreeCharge
    'com.amazon.mShop.android.shopping',       // Amazon Pay
    'com.dreamplug.androidapp',                // CRED
    // Bank Mobile Apps (push notifications)
    'com.sbi.lotusintouch',                    // SBI YONO
    'com.csam.icici.bank.imobile',             // ICICI iMobile
    'com.snapwork.hdfc',                       // HDFC Mobile Banking
    'com.axis.mobile',                         // Axis Mobile
    'com.kotak.mahindra.kotak.mobile.banking', // Kotak
    'com.idbi.mobilebanking',                  // IDBI
    'com.pnb.mbanking',                        // PNB
    'com.unionbank.ecom.mobile.android',       // Union Bank
    'com.canarabank.mobility',                 // Canara Bank
    'com.infrasoft.boi',                       // Bank of India
    'com.rbl.bank.mobilebanking',              // RBL
    'com.indusind.mobile',                     // IndusInd
    'com.yesbank',                             // Yes Bank
    'com.fbl',                                 // Federal Bank
    'com.scb.breezebanking.in',                // Standard Chartered
  };

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  Future<void> _startListening() async {
    // ── STEP 1: Check notification listener permission ─────────────────
    final hasPermission = await NotificationsListener.hasPermission;
    if (hasPermission != true) {
      // Show permission banner after first frame is rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPermissionBanner();
      });
      return; // Service cannot be started without permission
    }

    // ── STEP 2: Register named port for background isolate → UI comms ──
    // Must be done BEFORE starting the service.
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping('prism_bg_to_ui_port');
    IsolateNameServer.registerPortWithName(
        _receivePort!.sendPort, 'prism_bg_to_ui_port');

    // ── STEP 3: Listen on the background-isolate bridge port ───────────
    _receivePort!.listen((evt) {
      if (evt is NotificationEvent) _onNotificationEvent(evt);
    });

    // ── STEP 4: Also listen on the plugin's built-in receivePort ───────
    // This fires via platform channel when the app IS in foreground.
    // Both listeners call the same handler so events are never missed.
    NotificationsListener.receivePort?.listen((evt) {
      if (evt is NotificationEvent) _onNotificationEvent(evt);
    });

    // ── STEP 5: Start the foreground service ────────────────────────────
    final isRunning = await NotificationsListener.isRunning;
    if (isRunning != true) {
      await NotificationsListener.startService(
        foreground: true,
        title: 'Prism Engine',
        description: 'Listening for bank & UPI notifications.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main event processing pipeline
  // Called for EVERY notification received from any source.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _onNotificationEvent(NotificationEvent event) async {
    final pkg = event.packageName ?? '';
    final title = event.title ?? '';
    final text = event.text ?? '';

    // ── 1. Package filter ─────────────────────────────────────────────
    if (!_allowedPackages.contains(pkg)) return;
    if (text.trim().isEmpty && title.trim().isEmpty) return;

    // ── 2. Parse financial data ────────────────────────────────────────
    final parsed = AxioParser.parse(text, title: title);
    if (parsed == null) return; // OTP, spam, or non-financial

    final now = DateTime.now().millisecondsSinceEpoch;

    // ── 3. Deduplication (10-minute window) ────────────────────────────
    // Prevents double-counting when both the UPI app AND bank SMS fire
    // for the same transaction within 10 minutes of each other.
    final isDup = await DedupService.isDuplicateAndReconcile(
      amount: parsed.amount,
      type: parsed.type,
      timestamp: now,
      merchant: parsed.merchant,
    );
    if (isDup) return;

    // ── 4. Persist to SQLite ───────────────────────────────────────────
    final sourceKey = '${pkg}_${parsed.type}_${parsed.amount}_$now';
    await DatabaseHelper.instance.insertNotification({
      'source_key': sourceKey,
      'package_name': pkg,
      'sender_header': null,
      'title': title.isNotEmpty ? title : null,
      'text': text,
      'timestamp': now,
      'category': 'Bank',
      'merchant': parsed.merchant,
      'amount': parsed.amount,
      'txn_type': parsed.type,
      'is_priority': 0,
    });

    // ── 5. Refresh dashboard UI ────────────────────────────────────────
    if (mounted) {
      ref.read(dashboardProvider.notifier).refresh();
    }
  }

  void _showPermissionBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFF1E2430),
        leading: const Icon(
          Icons.notifications_off_rounded,
          color: Color(0xFFF59E0B),
        ),
        content: const Text(
          'Notification Access is required to capture bank & UPI transactions automatically.',
          style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificationsListener.openPermissionSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                // Re-try starting the listener after returning from settings
                await _startListening();
              }
            },
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
    _receivePort?.close();
    IsolateNameServer.removePortNameMapping('prism_bg_to_ui_port');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const DashboardScreen();
}
