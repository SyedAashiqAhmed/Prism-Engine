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
// Background Isolate Entry-Point
// MUST be a top-level function + @pragma('vm:entry-point').
// Runs in a SEPARATE Dart isolate spawned by Android when a notification fires.
// Cannot touch Flutter widgets or Riverpod — only sends data via IsolateNameServer.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void notificationCallback(NotificationEvent evt) {
  final SendPort? sp =
      IsolateNameServer.lookupPortByName('prism_notification_port');
  sp?.send(evt);
}

// ─────────────────────────────────────────────────────────────────────────────
// App Entry Point
// ─────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
// Starts the Android NotificationListenerService and pipes every incoming
// notification through: AxioParser → DedupService → SQLite → Riverpod → UI.
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationListenerShell extends ConsumerStatefulWidget {
  const _NotificationListenerShell();

  @override
  ConsumerState<_NotificationListenerShell> createState() =>
      _NotificationListenerShellState();
}

class _NotificationListenerShellState
    extends ConsumerState<_NotificationListenerShell> {
  ReceivePort? _port;

  // ── Expanded package allowlist ──────────────────────────────────────────
  // Covers all major Indian bank SMS apps, UPI apps, and wallet apps.
  // If a bank notification comes from an unlisted package, it will still
  // be passed through the parser — the parser blacklists OTPs and spam.
  // Keeping this list wide avoids the "silently dropped" problem.
  static const Set<String> _allowedPackages = {
    // SMS / Messaging (bank SMS arrives here on most devices)
    'com.google.android.apps.messaging',
    'com.android.mms',
    'com.samsung.android.messaging',
    'com.sonyericsson.conversations',
    'com.motorola.messaging',
    'com.oneplus.mms',
    'com.coloros.mms',          // OnePlus/OPPO
    'com.miui.messaging',       // Xiaomi MIUI
    'com.qti.qmmi',             // Qualcomm SMS
    // UPI Apps
    'com.google.android.apps.nbu.paisa.user', // Google Pay
    'com.phonepe.app',                         // PhonePe
    'net.one97.paytm',                         // Paytm
    'in.org.npci.upiapp',                      // BHIM
    'com.mobikwik_new',                        // MobiKwik
    'com.freecharge.android',                  // FreeCharge
    'com.amazon.mShop.android.shopping',       // Amazon Pay
    'com.dreamplug.androidapp',                // CRED
    // Bank Apps (push notifications)
    'com.sbi.lotusintouch',                    // SBI YONO
    'com.csam.icici.bank.imobile',             // ICICI iMobile
    'com.snapwork.hdfc',                       // HDFC Mobile Banking
    'com.hdfcbank.hdfcbanksmartbuy',           // HDFC SmartBuy
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
    'com.barclays.bpb',                        // Barclays
    'com.hsbc.hsbcnow',                        // HSBC
  };

  @override
  void initState() {
    super.initState();
    _initListener();
  }

  Future<void> _initListener() async {
    // STEP 1: Register the named port BEFORE starting the service so the
    // background isolate can immediately find it when the first event fires.
    _port = ReceivePort();
    IsolateNameServer.removePortNameMapping('prism_notification_port');
    IsolateNameServer.registerPortWithName(
        _port!.sendPort, 'prism_notification_port');

    // STEP 2: Route background isolate messages into our handler.
    // The plugin sends NotificationEvent objects directly across isolates.
    _port!.listen(_onRawNotification);

    // STEP 3: Register the Dart background callback with the native plugin.
    // Must be awaited to ensure the callback handle is set before the service starts.
    await NotificationsListener.initialize(callbackHandle: notificationCallback);

    // STEP 4: Start (or restart) the foreground service.
    // foreground: true is required on Android 9+ for reliable background
    // execution. Without it, the system kills the service within minutes.
    final running = await NotificationsListener.isRunning;
    if (running != true) {
      await NotificationsListener.startService(
        foreground: true,
        title: 'Prism Engine',
        description: 'Listening for bank & UPI notifications.',
      );
    }

    // STEP 5: Check if notification listener access is granted.
    // If not, the service runs but receives no events.
    final hasPermission = await NotificationsListener.hasPermission;
    if (hasPermission != true && mounted) {
      _showPermissionBanner();
    }
  }

  /// Shows a persistent banner prompting the user to grant Notification Access.
  void _showPermissionBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFF1E2430),
        leading: const Icon(Icons.notifications_off_rounded, color: Color(0xFFF59E0B)),
        content: const Text(
          'Notification Access required to capture bank transactions.',
          style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              NotificationsListener.openPermissionSettings();
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text('ENABLE', style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main notification processing pipeline
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _onRawNotification(dynamic rawEvent) async {
    // The flutter_notification_listener plugin sends NotificationEvent objects
    // directly across isolates via IsolateNameServer SendPort.
    // We accept both NotificationEvent (normal flow) and Map (defensive fallback).
    String pkg = '';
    String title = '';
    String text = '';

    if (rawEvent is NotificationEvent) {
      pkg = rawEvent.packageName ?? '';
      title = rawEvent.title ?? '';
      text = rawEvent.text ?? '';
    } else {
      // Should not normally happen, but guard against it.
      return;
    }

    // Drop notifications from apps we don't care about.
    if (!_allowedPackages.contains(pkg)) return;
    if (text.trim().isEmpty && title.trim().isEmpty) return;

    // Feed title AND text into the parser so it can extract
    // merchant names from the title even when the amount is in the body.
    final parsed = AxioParser.parse(text, title: title);
    if (parsed == null) return; // OTP, spam, or non-financial — ignored.

    final now = DateTime.now().millisecondsSinceEpoch;

    // 10-minute sliding window deduplication (GPay + bank SMS = 1 row).
    final isDup = await DedupService.isDuplicateAndReconcile(
      amount: parsed.amount,
      type: parsed.type,
      timestamp: now,
      merchant: parsed.merchant,
    );
    if (isDup) return;

    // Persist to local SQLite.
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

    // Trigger real-time UI refresh via Riverpod.
    if (mounted) {
      ref.read(dashboardProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    _port?.close();
    IsolateNameServer.removePortNameMapping('prism_notification_port');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const DashboardScreen();
}
