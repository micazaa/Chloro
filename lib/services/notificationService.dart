import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

import 'NotificationDataStorage.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1) Initialize timezone database
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(tz.local.name));

    // 2) Initialize the plugin with your default icon
    const androidInit = AndroidInitializationSettings('notification_icon');
    await _plugin.initialize(
      InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onResponse,
    );

    // 3) On Android, create your channel and request runtime permissions
    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      // 3a) Define the “recommendation_channel” (must match your scheduling code!)
      const recommendationChannel = AndroidNotificationChannel(
        'recommendation_channel',
        'Recommendation Alerts',
        description: 'Notifies when your parameters are out of range.',
        importance: Importance.max,
      );
      await androidPlugin?.createNotificationChannel(recommendationChannel);

      const harvestChannel = AndroidNotificationChannel(
        'harvest_channel',
        'Harvest Alerts',
        description: 'Fires when your batch is ready or overdue.',
        importance: Importance.max,
      );
      await androidPlugin?.createNotificationChannel(harvestChannel);

      // 3b) Create/register the channel on the system (API 26+); no-op on older

      // 3c) Now request “POST_NOTIFICATIONS” on Android 13+ (API 33+)
      await androidPlugin?.requestNotificationsPermission();
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  void openExactAlarmSettings() {
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
    );
    intent.launch();
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) _handleNavigation(payload);
  }

  void _handleNavigation(String payload) {
    // deep-link payload is a query string, e.g. "nutrient_alert?batchId=…"
    Get.toNamed('/notifications_screen');
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() =>
      _plugin.pendingNotificationRequests();

  Future<void> scheduleRecommendationNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required Map<String, dynamic> payloadMap,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    // Extract the batch_id and date from payload
    final batchId = payloadMap['batchId'] as String?;
    final dateString = payloadMap['date'] as String?;
    final type = payloadMap['type'] as String? ?? 'nutrient';
    if (batchId == null || dateString == null) {
      throw Exception('Missing batchId or date in payload');
    }

    final upsertPayload = {
      'id': id,
      'user_id': user.id,
      'batch_id': batchId,
      'date': dateString,
      'type': type,
      'title': title,
      'body': body,
      'payload': payloadMap,
      'scheduled_at': scheduledDate.toIso8601String(),
      'sent': false,
    };

    try {
      await supabase.from('notifications').upsert([
        upsertPayload,
      ], onConflict: 'batch_id,date, type');
    } catch (e) {
      print('Upsert error: $e');
      rethrow;
    }

    // ─── schedule the local mobile notification ───
    final androidDetails = AndroidNotificationDetails(
      'recommendation_channel',
      'Recommendation Alerts',
      channelDescription: 'Notifies when your parameters are out of range.',
      importance: Importance.max,
      priority: Priority.high,
    );
    final platformDetails = NotificationDetails(android: androidDetails);
    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzDate,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
        payload: '',
      );
    } on PlatformException catch (e) {
      print("Error scheduling notification: ${e.message}");
    }

    await NotificationDataStorage.savePayload(id, payloadMap);
  }

  Future<void> scheduleHarvestNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required Map<String, dynamic> payloadMap,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final batchId = payloadMap['batchId'] as String? ?? '';
    final predictedHarvestIso = payloadMap['predictedHarvest'] as String? ?? '';
    final datePlantedIso = payloadMap['datePlanted'] as String?;
    final type = payloadMap['type'] as String? ?? 'harvest';

    if (batchId.isEmpty ||
        predictedHarvestIso.isEmpty ||
        datePlantedIso == null) {
      throw Exception(
        'Missing batchId, datePlanted, or predictedHarvest in payloadMap',
      );
    }

    final predictedHarvestDate = DateTime.parse(predictedHarvestIso).toLocal();
    final dateOnlyString = DateFormat(
      'yyyy-MM-dd',
    ).format(predictedHarvestDate);

    final upsertPayload = <String, Object?>{
      'id': id,
      'user_id': user.id,
      'batch_id': batchId,
      'date': dateOnlyString,
      'type': type,
      'title': title,
      'body': body,
      'payload': <String, dynamic>{
        'userId': payloadMap['userId'],
        'batchId': batchId,
        'batchNumber': payloadMap['batchNumber'],
        'datePlanted': datePlantedIso,
        'date': dateOnlyString,
        'predictedHarvest': predictedHarvestIso,
        'type': 'harvest',
      },
      'scheduled_at': scheduledDate.toIso8601String(),
      'sent': false,
    };

    try {
      await supabase.from('notifications').upsert([
        upsertPayload,
      ], onConflict: 'batch_id,type').select();
    } catch (e) {
      print('Error upserting harvest notification: $e');
      rethrow;
    }
    print(
      "Upserting notification for batch $batchId on $dateOnlyString (${predictedHarvestDate.toIso8601String()})",
    );

    final androidDetails = AndroidNotificationDetails(
      'harvest_channel',
      'Harvest Alerts',
      channelDescription: 'Fires when your batch is ready or overdue.',
      importance: Importance.max,
      priority: Priority.high,
    );
    final platformDetails = NotificationDetails(android: androidDetails);
    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDate,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
      payload: '',
    );

    await NotificationDataStorage.savePayload(
      id,
      upsertPayload['payload'] as Map<String, dynamic>,
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
    await NotificationDataStorage.removePayload(id);
  }
}
