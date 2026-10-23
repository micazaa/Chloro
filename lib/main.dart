import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/NotificationDataStorage.dart';
import 'services/network_connection.dart';
import 'helpers/offline_banner.dart';
import 'services/dependency_controller.dart';
import 'pages/auth/login.dart';
import 'pages/auth/signup.dart';
import 'pages/splash_page.dart';
import 'services/auto_batch_services.dart';
import 'dart:developer' as dev;
import 'pages/home/home_screen.dart';
import 'pages/home/notifications_screen.dart';
import 'services/notificationService.dart';
import 'package:flutter/services.dart';
import 'package:background_fetch/background_fetch.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init the plugin
  try {
    await NotificationService().init();
  } catch (e, st) {
    print('🔴 NotificationService.init() failed: $e\n$st');
  }

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize Supabase AFTER Flutter has shown the initial frame
  await Supabase.initialize(
    url: 'https://mqtzhdbgieuppbttzbfp.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1xdHpoZGJnaWV1cHBidHR6YmZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU2NzY0NDMsImV4cCI6MjA2MTI1MjQ0M30.a9xuO29_44byQHyCarnq1D4XOUxBY5o9Ey4_0MhtXQE',
  );
  await _syncRemoteNotifications();

  // 2️⃣ subscribe to real-time inserts
  _subscribeRemoteNotifications();

  // lock orientation
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);

  runApp(const MyApp());

  // instantiate network controller
  Get.put(NetworkController());
}

void backgroundFetchHeadlessTask(HeadlessTask task) async {
  WidgetsFlutterBinding.ensureInitialized();

  print('💜 headless task fired (${task.taskId})');
  if (task.timeout) {
    print('⏰ Headless TIMEOUT  →  ${task.taskId}');
    BackgroundFetch.finish(task.taskId);
    return;
  }
  print('🤖 Headless fetch trigger  →  ${task.taskId}');
  await AutoBatchServices.run(origin: 'headless');
  BackgroundFetch.finish(task.taskId);
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

Future<void> _syncRemoteNotifications() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final nowIso = DateTime.now().toIso8601String();
  // ↓ select() + filters ⇒ returns List<Map<String,dynamic>>
  final rows = await supabase
      .from('notifications')
      .select()
      .eq('user_id', user.id)
      .eq('sent', false)
      .gte('scheduled_at', nowIso);

  for (final raw in rows) {
    final row = Map<String, dynamic>.from(raw);
    final id = row['id'] as int;
    if (NotificationDataStorage.getPayload(id) != null) continue;

    final title = row['title'] as String;
    final body = row['body'] as String;
    final scheduledAt = DateTime.parse(row['scheduled_at'] as String);
    final payloadMap = Map<String, dynamic>.from(row['payload']);

    await NotificationService().scheduleRecommendationNotification(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledAt,
      payloadMap: payloadMap,
    );
  }
}

/// Real-time listener
void _subscribeRemoteNotifications() {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return;

  // Cast the query as PostgrestFilterBuilder before calling .stream()
  final query = supabase
      .from('notifications')
      .select()
      .eq('user_id', user.id)
      .eq('sent', false);

  // Then start the stream
  query.asStream().listen((response) {
    final rows = response as List<Map<String, dynamic>>;
    for (final row in rows) {
      final id = row['id'] as int;
      if (NotificationDataStorage.getPayload(id) != null) continue;

      final title = row['title'] as String;
      final body = row['body'] as String;
      final scheduledAt = DateTime.parse(row['scheduled_at'] as String);
      final payloadMap = Map<String, dynamic>.from(row['payload']);

      NotificationService().scheduleRecommendationNotification(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledAt,
        payloadMap: payloadMap,
      );
    }
  });
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter'),
      useInheritedMediaQuery: !kReleaseMode,

      initialRoute: '/',
      routes: {
        '/': (c) => const SplashScreen(),
        '/login': (c) => const LogIn(),
        '/signup': (c) => const SignUp(),
        '/home': (c) => const HomeScreen(),
        '/notifications_screen': (c) => const NotificationsScreen(),
      },
      navigatorObservers: [routeObserver],
    );
  }
}
