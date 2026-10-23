import 'dart:convert';
import 'dart:async';
import 'dart:developer' as dev;
import 'package:background_fetch/background_fetch.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AutoBatchServices {
  static Future<void> run({String origin = 'headless'}) async {
    dev.log('🔥 AutoBatchServices.run() [$origin] at ${DateTime.now()}');

    // ── 0. Preferences – is AUTO enabled? ─────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final String? batchId = prefs.getString('auto_batch_id');
    final String? userEmail = prefs.getString('auto_user_email');
    if (batchId == null || userEmail == null) return;

    final supabase = Supabase.instance.client;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // ── 1. Latest 10 raw sensor rows ──────────────────────────────
    final rows = await supabase
        .from('sensor_logs')
        .select('temperature,humidity,tds,ph')
        .eq('date', dateStr)
        .eq('gmail', userEmail)
        .order('time', ascending: false)
        .limit(10);

    dev.log('Rows fetched: ${rows.length}');
    if (rows.isEmpty) return;

    // ── 2. Mean-aggregate today’s readings ────────────────────────
    double t = 0, h = 0, td = 0, p = 0;
    for (final r in rows) {
      t += (r['temperature'] ?? 0).toDouble();
      h += (r['humidity'] ?? 0).toDouble();
      td += (r['tds'] ?? 0).toDouble();
      p += (r['ph'] ?? 0).toDouble();
    }
    final n = rows.length;
    final agg = {
      'temperature': t / n,
      'humidity': h / n,
      'tds': td / n,
      'ph': p / n,
    };

    // ── 3. Fetch batch metadata once (number + method) ────────────
    final batchMeta =
        await supabase
            .from('batches')
            .select('batch_number, method')
            .eq('id', batchId)
            .maybeSingle();

    final int? batchNumber = (batchMeta?['batch_number'] as num?)?.toInt();
    final String? method = batchMeta?['method']?.toString();

    // ── 4. Upsert the reading for TODAY ───────────────────────────
    await supabase.from('readings').upsert({
      'batch_id': batchId,
      'batch_number': batchNumber,
      'method': method,
      'date': dateStr,
      ...agg,
      'source': 'auto',
    }, onConflict: 'batch_id,date');

    // ── 5. Predict harvest day via your API ───────────────────────
    final resp = await http.post(
      Uri.parse(
        'https://modelrailway-production-e9cf.up.railway.app/predict-harvest',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode([
        {'date': dateStr, ...agg},
      ]),
    );
    if (resp.statusCode != 200) return;

    final int predDay =
        (jsonDecode(resp.body)['predicted_harvest_day'] as num).toInt();

    // ── 6. Compute days-left relative to planting date ────────────
    final plantDate = DateTime.parse(
      prefs.getString('auto_start_date') ?? dateStr,
    );
    final daysLeft = (predDay - now.difference(plantDate).inDays).clamp(
      0,
      predDay,
    );

    dev.log('Prediction: predDay=$predDay  daysLeft=$daysLeft');

    // ── 7. Write prediction back (ID + DATE) ──────────────────────
    await supabase
        .from('readings')
        .update({
          'predicted_harvest_day': predDay,
          'days_until_harvest': daysLeft,
          if (batchNumber != null) 'batch_number': batchNumber,
          if (method != null) 'method': method,
        })
        .eq('batch_id', batchId)
        .eq('date', dateStr);
  }
}

//──────────────────────────────────  SCHEDULER  ─────────────────────────────────

class AutoBatchScheduler {
  static Timer? _fastTimer;
  static int _userInterval = 15;

  static Future<void> configure({required int intervalMinutes}) async {
    _userInterval = intervalMinutes;

    final bgInterval = intervalMinutes < 15 ? 15 : intervalMinutes;

    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: bgInterval,
        stopOnTerminate: false,
        enableHeadless: true,
        startOnBoot: true,
        requiredNetworkType: NetworkType.ANY,
      ),
      _onForegroundFetch,
      (taskId) async => BackgroundFetch.finish(taskId),
    );

    _fastTimer?.cancel();
    if (intervalMinutes < 15) {
      _fastTimer = Timer.periodic(
        Duration(minutes: intervalMinutes),
        (_) => AutoBatchServices.run(origin: 'fast_timer'),
      );
    }
  }

  static Future<void> start() => BackgroundFetch.start();

  static Future<void> stop() async {
    _fastTimer?.cancel();
    _fastTimer = null;
    await BackgroundFetch.stop();
  }

  static void _onForegroundFetch(String taskId) async {
    await AutoBatchServices.run(origin: 'background_fetch');
    BackgroundFetch.finish(taskId);
  }
}
