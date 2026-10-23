import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:get/get.dart';

import 'create_garden.dart';
import '../../services/network_connection.dart';
import '../../helpers/offline_banner.dart';
import 'calendar_screen.dart';
import 'userguide_screen.dart';
import 'notifications_screen.dart';
import 'account_screen.dart';
import '../../services/notificationService.dart';
import '../batch/batch_info.dart';
import '../../helpers/status_indicator.dart';
import '../../helpers/get_status.dart';
import 'package:chloro/main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  List<Map<String, dynamic>> _batches = [];
  DateTime startOfCurrentWeek = DateTime.now().subtract(
    Duration(days: DateTime.now().weekday % 7),
  );
  DateTime? selectedDate = DateTime.now();
  final PageController _pageController = PageController(initialPage: 1000);
  double? currentTemp;
  List<Map<String, dynamic>> _batchSchedules = [];

  final NetworkController _net = Get.find();
  RxBool isLoadingOffline = true.obs;
  RxBool isLoadingBatches = false.obs;
  RxString selectedMethod = 'Batches'.obs;

  DateTime parsePlanted(dynamic rawPl) {
    if (rawPl is String && rawPl.contains('-')) {
      return DateTime.parse(rawPl);
    }
    if (rawPl is int) {
      if (rawPl > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(rawPl);
      }
      return DateTime.fromMillisecondsSinceEpoch(rawPl * 1000);
    }
    return DateTime.now();
  }

  /*────────────────────────  INIT  ─────────────────────────*/
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    print('[ROUTE] didPush called');
    _loadBatches();
  }

  @override
  void didPopNext() {
    print('[ROUTE] didPopNext called');
    _loadBatches();
  }

  //──────────────────────────────────  DELETE/HARVEST BATCH  ─────────────────────────────────
  Future<void> _deleteBatch(String batchId) async {
    try {
      await Supabase.instance.client
          .from('readings')
          .delete()
          .eq('batch_id', batchId);

      // 2) Delete any notifications for that batch
      await Supabase.instance.client
          .from('notifications')
          .delete()
          .eq('batch_id', batchId);

      // 3) Delete from `batches` itself
      final deleted =
          await Supabase.instance.client
              .from('batches')
              .delete()
              .eq('id', batchId)
              .select();

      // If RLS blocked the deletion, `deleted` will be empty
      if (deleted.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete blocked by RLS')),
          );
        }
        return;
      }

      // 4) Remove from our RxList _batches; no setState needed
      _batches.removeWhere((b) => b['id'] == batchId);

      // 5) After removing from `_batches`, fix the dropdown if needed
      final uniqueBatches = _batches.toSet().toList();
      final dropdownValues = [
        'Batches',
        ...uniqueBatches.map((b) => "${b['method']}: ${b['batch_number']}"),
      ];
      if (!dropdownValues.contains(selectedMethod.value)) {
        selectedMethod.value = dropdownValues.first;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting batch: $e')));
      }
    }
  }

  Future<void> _harvestBatch(String batchId) async {
    final supabase = Supabase.instance.client;
    final currentDate = DateTime.now().toIso8601String();
    final user = supabase.auth.currentUser;

    if (user == null) {
      print("User is not logged in");
      return;
    }

    try {
      final updates = {'is_harvested': 'yes', 'date_harvested': currentDate};
      final response = await supabase
          .from('batches')
          .update(updates)
          .eq('id', batchId)
          .eq('user_id', user.id);

      await supabase.from('notifications').delete().eq('batch_id', batchId);

      if (!mounted) return;
      setState(() {
        _batches.removeWhere((batch) => batch['id'] == batchId);
      });

      print(
        'Batch harvested, notifications deleted, and removed from list: $response',
      );
    } catch (e) {
      print('Exception during harvest: $e');
    }
  }

  Map<String, dynamic> getStatusInfoForBatch({
    required String tempText,
    required String phText,
    required String tdsText,
    required String humidityText,
  }) {
    final hasReading =
        tempText.isNotEmpty &&
        phText.isNotEmpty &&
        tdsText.isNotEmpty &&
        humidityText.isNotEmpty;

    if (!hasReading) {
      return {
        'label': 'Status',
        'value': '...',
        'strokeColor': Colors.grey.shade300,
        'innerColor': Colors.transparent,
        'emojiAsset': null,
      };
    }

    final temp = double.tryParse(tempText) ?? double.nan;
    final ph = double.tryParse(phText) ?? double.nan;
    final tds = double.tryParse(tdsText) ?? double.nan;
    final humidity = double.tryParse(humidityText) ?? double.nan;

    final statuses = <String>[];

    if (22 <= temp && temp <= 26)
      statuses.add('Healthy');
    else if (18 <= temp && temp <= 30)
      statuses.add('Normal');
    else if (15 <= temp && temp <= 32)
      statuses.add('Abnormal');
    else
      statuses.add('Critical');

    if (5.5 <= ph && ph <= 6.5)
      statuses.add('Healthy');
    else if (5.5 <= ph && ph <= 6.6)
      statuses.add('Normal');
    else if (5.0 <= ph && ph <= 7.5)
      statuses.add('Abnormal');
    else
      statuses.add('Critical');

    if (560 <= tds && tds <= 840)
      statuses.add('Healthy');
    else if (500 <= tds && tds <= 880)
      statuses.add('Normal');
    else if (400 <= tds && tds <= 900)
      statuses.add('Abnormal');
    else
      statuses.add('Critical');

    if (50 <= humidity && humidity <= 80)
      statuses.add('Healthy');
    else if (40 <= humidity && humidity <= 90)
      statuses.add('Normal');
    else if (30 <= humidity && humidity <= 95)
      statuses.add('Abnormal');
    else
      statuses.add('Critical');

    final counts = <String, int>{};
    for (var s in statuses) counts[s] = (counts[s] ?? 0) + 1;

    String value, asset;
    Color stroke;
    if (counts['Critical'] == 4) {
      value = 'Uncertain';
      asset = 'assets/1.png';
      stroke = Color(0xFFFF6666);
    } else if ((counts['Critical'] ?? 0) > 0) {
      value = 'Critical';
      asset = 'assets/2.png';
      stroke = Colors.red;
    } else if ((counts['Healthy'] ?? 0) == 4) {
      value = 'Healthy';
      asset = 'assets/5.png';
      stroke = const Color(0xFF95B45B);
    } else if ((counts['Abnormal'] ?? 0) >= 3) {
      value = 'Abnormal';
      asset = 'assets/3.png';
      stroke = Color(0xFFFFDA6C);
    } else {
      value = 'Normal';
      asset = 'assets/4.png';
      stroke = Color(0xFFFFDA6C);
    }

    return {
      'label': 'Status',
      'value': value,
      'strokeColor': stroke,
      'innerColor': Colors.transparent,
      'emojiAsset': asset,
    };
  }

  //────────────────────────────────── LOADING/FETCHING ─────────────────────────────────
  Future<void> _loadBatches() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    isLoadingBatches.value = true;
    if (user == null) return;

    try {
      // a) load batch list (only unharvested)
      final batchData = await supa
          .from('batches')
          .select()
          .eq('user_id', user.id)
          .or('is_harvested.is.null,is_harvested.eq.no');
      final rawBatches = List<Map<String, dynamic>>.from(batchData);

      // b) fetch today’s readings (to get days_until_harvest)
      final dateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(selectedDate ?? DateTime.now());
      final readingData = await supa
          .from('readings')
          .select(
            'batch_id, date, days_until_harvest, temperature, humidity, tds, ph',
          )
          .eq('date', dateStr);
      final readings = (readingData as List).cast<Map<String, dynamic>>();

      // c) map out raw values per batch
      final harvestMap = <String, int>{};
      final tempMap = <String, double>{};
      final humidityMap = <String, double>{};
      final tdsMap = <String, double>{};
      final phMap = <String, double>{};

      for (final r in readings) {
        final id = r['batch_id'] as String;
        if (r['days_until_harvest'] is num) {
          harvestMap[id] = (r['days_until_harvest'] as num).toInt();
        }
        tempMap[id] = (r['temperature'] as num?)?.toDouble() ?? double.nan;
        humidityMap[id] = (r['humidity'] as num?)?.toDouble() ?? double.nan;
        tdsMap[id] = (r['tds'] as num?)?.toDouble() ?? double.nan;
        phMap[id] = (r['ph'] as num?)?.toDouble() ?? double.nan;
      }

      // d) back‐fill missing readings
      for (final b in rawBatches) {
        final id = b['id'] as String;
        if (harvestMap.containsKey(id)) continue;

        final prev =
            await supa
                .from('readings')
                .select(
                  'date, days_until_harvest, temperature, humidity, tds, ph',
                )
                .eq('batch_id', id)
                .lte('date', dateStr)
                .order('date', ascending: false)
                .limit(1)
                .maybeSingle();

        if (prev != null) {
          final rd = DateTime.parse(prev['date'] as String);
          final prevDays =
              int.tryParse(prev['days_until_harvest'].toString()) ?? 0;
          final elapsed =
              (selectedDate ?? DateTime.now()).difference(rd).inDays;
          harvestMap[id] = (prevDays - elapsed).clamp(-1000, 1000);
          tempMap[id] = (prev['temperature'] as num?)?.toDouble() ?? double.nan;
          humidityMap[id] =
              (prev['humidity'] as num?)?.toDouble() ?? double.nan;
          tdsMap[id] = (prev['tds'] as num?)?.toDouble() ?? double.nan;
          phMap[id] = (prev['ph'] as num?)?.toDouble() ?? double.nan;
        }
      }

      // e) rebuild calendar schedules (unchanged)
      final newSchedules = <Map<String, dynamic>>[];
      for (final b in rawBatches) {
        final id = b['id'] as String;
        final planted = parsePlanted(b['date_planted']);
        final isHarvested =
            (b['is_harvested'] as String?)?.toLowerCase() == 'yes';
        final int? daysLeft =
            harvestMap.containsKey(id) ? harvestMap[id] : null;

        final DateTime? predictedHarvest = await fetchLatestPredictedHarvestDay(
          batchId: id,
          plantedDate: planted,
        );

        newSchedules.add({
          'batch_id': id,
          'method': b['method'] as String,
          'batch_number': b['batch_number'],
          'planted': planted,
          'daysLeft': daysLeft,
          'predictedHarvest': predictedHarvest,
          'isHarvested': isHarvested,
        });
      }
      _batchSchedules = newSchedules;
      _notifyHarvestReady(user.id);
      final withAdjustments =
          rawBatches.map((b) {
              final id = b['id'] as String;
              final daysLeft = harvestMap[id];
              final t = tempMap[id]?.toStringAsFixed(1) ?? '';
              final h = humidityMap[id]?.toStringAsFixed(1) ?? '';
              final d = tdsMap[id]?.toStringAsFixed(0) ?? '';
              final p = phMap[id]?.toStringAsFixed(2) ?? '';

              final statusInfo = getStatusInfoForBatch(
                tempText: t,
                phText: p,
                tdsText: d,
                humidityText: h,
              );
              statusInfo['phAbnormal'] = false;
              statusInfo['tdsAbnormal'] = false;

              return <String, dynamic>{
                ...b,
                'days_until_harvest': daysLeft,
                'temperature': t,
                'humidity': h,
                'tds': d,
                'ph': p,
                'status': statusInfo,
              };
            }).toList()
            ..sort((a, b) {
              final da =
                  DateTime.tryParse(a['date_planted'] ?? '') ?? DateTime.now();
              final db =
                  DateTime.tryParse(b['date_planted'] ?? '') ?? DateTime.now();
              return da.compareTo(db);
            });

      _batches.assignAll(withAdjustments);

      final uniqueBatches = _batches.toSet().toList();
      final dropdownValues = [
        'Batches',
        ...uniqueBatches.map((b) => "${b['method']}: ${b['batch_number']}"),
      ];
      if (!dropdownValues.contains(selectedMethod.value)) {
        selectedMethod.value = dropdownValues.first;
      }
    } catch (e) {
      debugPrint('Error loading batches: $e');
    } finally {
      isLoadingBatches.value = false;
    }
  }

  Future<void> _notifyHarvestReady(String userId) async {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    for (final s in _batchSchedules) {
      final DateTime? predictedHarvest = s['predictedHarvest'] as DateTime?;
      final bool isHarvestedFlag = (s['isHarvested'] as bool?) ?? false;

      if (predictedHarvest == null ||
          predictedHarvest.year < 2020 ||
          predictedHarvest.isBefore(DateTime(2021)) ||
          isHarvestedFlag) {
        continue;
      }

      final DateTime harvestDateOnly = DateTime(
        predictedHarvest.year,
        predictedHarvest.month,
        predictedHarvest.day,
      );

      if (harvestDateOnly.isAfter(todayDate)) continue;

      final String batchId = s['batch_id'] as String;
      final int batchNumber = s['batch_number'] as int;

      final bool isExactToday = harvestDateOnly == todayDate;
      final int daysLate = todayDate.difference(harvestDateOnly).inDays;

      final String title = isExactToday ? '🌱 Harvest Day!' : 'Harvest Overdue';
      final String body =
          isExactToday
              ? 'Your batch $batchNumber planted on '
                  '${DateFormat.yMMMd().format(s['planted'] as DateTime)} is ready TODAY!'
              : 'Your batch $batchNumber planted on '
                  '${DateFormat.yMMMd().format(s['planted'] as DateTime)} '
                  'is $daysLate day(s) overdue.';

      final String datePlantedIso =
          (s['planted'] as DateTime).toIso8601String();
      final Map<String, dynamic> payloadMap = {
        'userId': userId,
        'batchId': batchId,
        'batchNumber': batchNumber,
        'datePlanted': datePlantedIso,
        'predictedHarvest': harvestDateOnly.toIso8601String(),
        'type': 'harvest',
      };

      final int notifId =
          '$batchId-harvest-${harvestDateOnly.toIso8601String()}'.hashCode;

      await NotificationService().scheduleHarvestNotification(
        id: notifId,
        title: title,
        body: body,
        scheduledDate: DateTime.now().add(const Duration(seconds: 1)),
        payloadMap: payloadMap,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFA0C878),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.06,
                vertical: screenHeight * 0.01,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(screenWidth, screenHeight),
                  SizedBox(height: screenHeight * 0.016),
                  _buildWeatherAndCalendar(screenWidth, screenHeight),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildDraggableBottom(
                screenWidth,
                screenHeight,
                screenHeight - screenHeight * 0.1 - screenHeight * 0.16,
              ),
            ),
            Align(alignment: Alignment.bottomCenter, child: _buildNavBar()),
          ],
        ),
      ),
    );
  }

  /*────────────────────  HEADER  ────────────────────*/
  Widget _buildHeader(double screenWidth, double screenHeight) {
    final user = Supabase.instance.client.auth.currentUser;
    final fullName = user?.userMetadata?['full_name'] ?? 'Garden';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "${fullName}’s Garden",
          style: TextStyle(
            fontSize: screenWidth * 0.056,
            fontFamily: 'Inter_Bold',
            color: Colors.white,
          ),
        ),
        GestureDetector(
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => Account()),
              ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: EdgeInsets.all(screenHeight * 0.003),
            child: CircleAvatar(
              radius: screenWidth * 0.050,
              backgroundImage: const AssetImage('assets/profile.jpg'),
            ),
          ),
        ),
      ],
    );
  }

  Future<DateTime?> fetchLatestPredictedHarvestDay({
    required String batchId,
    required DateTime plantedDate,
  }) async {
    final latestReading =
        await Supabase.instance.client
            .from('readings')
            .select('days_until_harvest, date')
            .eq('batch_id', batchId)
            .order('date', ascending: false)
            .limit(1)
            .maybeSingle();

    if (latestReading != null) {
      final daysUntilHarvest =
          (latestReading['days_until_harvest'] as num?)?.toInt();
      final readingDateStr = latestReading['date'] as String?;
      if (daysUntilHarvest != null && readingDateStr != null) {
        final readingDate = DateTime.parse(readingDateStr);
        return readingDate.add(Duration(days: daysUntilHarvest));
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _getFilteredSchedules() {
    String? selectedBatchId;

    if (selectedMethod.value != 'Batches') {
      final parts = selectedMethod.value.split(': ');
      if (parts.length == 2) {
        final method = parts[0];
        final batchNumber = parts[1];
        final match = _batches.firstWhere(
          (b) =>
              b['method'] == method &&
              b['batch_number'].toString() == batchNumber,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          selectedBatchId = match['id'] as String?;
        }
      }
    }

    return selectedBatchId == null
        ? _batchSchedules
        : _batchSchedules
            .where((s) => s['batch_id'] == selectedBatchId)
            .toList();
  }

  /*──────── WEATHER + MONTH/YEAR + WEEK CALENDAR ─────────*/
  Widget _buildWeatherAndCalendar(double screenWidth, double screenHeight) {
    final filteredSchedules = _getFilteredSchedules();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('MMMM yyyy').format(startOfCurrentWeek),
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth * 0.052,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.calendar_month_rounded,
                size: screenWidth * 0.070,
                color: Colors.white,
              ),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) =>
                              CalendarScreen(batchSchedules: filteredSchedules),
                    ),
                  ),
            ),
          ],
        ),
        _buildWeeklyCalendar(screenWidth, screenHeight),
      ],
    );
  }

  void _jumpToBatchWeek(String batchId) {
    final batch = _batchSchedules.firstWhere((s) => s['batch_id'] == batchId);
    final planted = batch['planted'] as DateTime;

    final targetWeekStart = planted.subtract(
      Duration(days: planted.weekday % 7),
    );

    final now = DateTime.now();
    final baseWeekStart = now.subtract(Duration(days: now.weekday % 7));

    final weekDiff = targetWeekStart.difference(baseWeekStart).inDays ~/ 7;
    final targetPage = 1000 + weekDiff;

    _pageController.jumpToPage(targetPage);
    setState(() {
      startOfCurrentWeek = targetWeekStart;
      selectedDate = planted;
    });
  }

  Widget _buildWeeklyCalendar(double screenWidth, double screenHeight) {
    String? selectedBatchId;
    if (selectedMethod.value != 'Batches') {
      final parts = selectedMethod.value.split(': ');
      if (parts.length == 2) {
        final method = parts[0];
        final batchNumber = parts[1];
        final match = _batches.firstWhere(
          (b) =>
              b['method'] == method &&
              b['batch_number'].toString() == batchNumber,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          selectedBatchId = match['id'] as String?;
        }
      }
    }

    final filteredSchedules =
        selectedBatchId == null
            ? _batchSchedules
            : _batchSchedules
                .where((s) => s['batch_id'] == selectedBatchId)
                .toList();

    return Column(
      children: [
        // ─── Weekday Labels ─────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (i) {
            final weekDay = startOfCurrentWeek.add(Duration(days: i));
            final isToday = DateUtils.isSameDay(weekDay, DateTime.now());
            return SizedBox(
              width: screenWidth * 0.12,
              child: Text(
                isToday ? 'TODAY' : ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize:
                      isToday ? screenHeight * 0.014 : screenHeight * 0.016,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: Colors.white,
                ),
              ),
            );
          }),
        ),

        // ─── Day Circles ────────────────────────────────────────────────
        SizedBox(
          height: screenHeight * 0.065,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (page) {
              final newStart = DateTime.now()
                  .subtract(Duration(days: DateTime.now().weekday % 7))
                  .add(Duration(days: (page - 1000) * 7));

              setState(() {
                startOfCurrentWeek = newStart;
                selectedDate = newStart;
              });

              // Immediately refresh the data for the newly visible date:
              _loadBatches();
            },

            itemBuilder: (_, idx) {
              final weekStart = DateTime.now()
                  .subtract(Duration(days: DateTime.now().weekday % 7))
                  .add(Duration(days: (idx - 1000) * 7));

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (dIdx) {
                  final day = weekStart.add(Duration(days: dIdx));
                  final isToday = DateUtils.isSameDay(day, DateTime.now());
                  final isSelected =
                      selectedDate != null &&
                      DateUtils.isSameDay(day, selectedDate!);

                  final isPlantedDay = filteredSchedules.any(
                    (s) => DateUtils.isSameDay(day, s['planted'] as DateTime),
                  );

                  final List<Map<String, dynamic>> withPrediction =
                      filteredSchedules
                          .where((s) => s['predictedHarvest'] != null)
                          .toList();

                  final isScheduledDay = withPrediction.any((s) {
                    final p = s['planted'] as DateTime;
                    final ph = s['predictedHarvest'] as DateTime;
                    return day.isAfter(p) && day.isBefore(ph);
                  });

                  final isPredictedHarvestDay = withPrediction.any(
                    (s) => DateUtils.isSameDay(
                      day,
                      s['predictedHarvest'] as DateTime,
                    ),
                  );

                  Color bgColor;
                  if (isPlantedDay) {
                    bgColor = Colors.transparent;
                  } else if (isScheduledDay) {
                    bgColor = const Color(0xFF9dd5d8);
                  } else if (isToday) {
                    bgColor = Colors.black.withOpacity(0.1);
                  } else if (isSelected) {
                    bgColor = const Color.fromARGB(171, 198, 198, 198);
                  } else {
                    bgColor = Colors.transparent;
                  }

                  Widget circleWidget = Container(
                    width: screenWidth * 0.09,
                    height: screenWidth * 0.09,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bgColor,
                      border:
                          isPredictedHarvestDay
                              ? Border.all(color: Colors.red, width: 2.5)
                              : null,
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color:
                              isPlantedDay
                                  ? Colors.white
                                  : isPredictedHarvestDay
                                  ? Colors.redAccent
                                  : Colors.white,
                          fontSize: screenHeight * 0.02,
                          fontFamily: isToday ? 'Inter_Bold' : null,
                          fontWeight:
                              isPlantedDay || isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                    ),
                  );

                  if (isPlantedDay) {
                    circleWidget = DottedBorder(
                      borderType: BorderType.Circle,
                      color: const Color.fromARGB(255, 78, 169, 81),
                      dashPattern: [6, 3],
                      strokeWidth: 3,
                      padding: EdgeInsets.zero,
                      child: circleWidget,
                    );
                  }

                  if (isSelected) {
                    circleWidget = Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: 1.25,
                          child: Container(
                            width: screenWidth * 0.09,
                            height: screenWidth * 0.09,
                            decoration: const BoxDecoration(
                              color: Color.fromARGB(171, 198, 198, 198),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        circleWidget,
                      ],
                    );
                  }

                  return GestureDetector(
                    onTap: () async {
                      setState(() => selectedDate = day);
                      await _loadBatches();
                    },

                    child: SizedBox(
                      width: screenWidth * 0.086,
                      height: screenWidth * 0.086,
                      child: circleWidget,
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNavBar() {
    return Padding(
      padding: EdgeInsets.all(30.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 180,
            height: 55,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: null,
                    child: Icon(Icons.home, color: Color(0xFF9dd5d8), size: 36),
                  ),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationsScreen(),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.notifications_rounded,
                      color: Color(0xFFacacac),
                      size: 36,
                    ),
                  ),
                  SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => UserGuide()),
                      );
                    },
                    child: Icon(Icons.info, color: Color(0xFFacacac), size: 36),
                  ),
                ],
              ),
            ),
          ),
          FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateGarden()),
              );
            },
            backgroundColor: Colors.white,
            child: Icon(Icons.add, color: Color(0xFFacacac), size: 40),
          ),
        ],
      ),
    );
  }

  Widget _navIcon(
    IconData icon,
    VoidCallback onTap, {
    required bool isActive,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: size,
        color:
            isActive
                ? const Color.fromARGB(255, 61, 61, 61)
                : const Color(0xFFacacac),
      ),
    );
  }

  Widget _buildDraggableBottom(double w, double h, double availableH) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.72,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFF8FBE3),
                Color.fromARGB(255, 189, 216, 161),
              ],
              stops: [0.0, 0.82, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(60)),
          ),
          child: Column(
            children: [
              SizedBox(height: h * 0.02),
              Container(
                width: w * 0.15,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SizedBox(height: h * 0.02),

              /// DROPDOWN
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: w * 0.4),
                  child: SizedBox(
                    height: 35,
                    child: Obx(() {
                      final uniqueBatches = _batches.toSet().toList();

                      // Sort alphabetically by "method: batch_number"
                      uniqueBatches.sort((a, b) {
                        final aLabel =
                            "${a['method']}: ${a['batch_number']}"
                                .toLowerCase();
                        final bLabel =
                            "${b['method']}: ${b['batch_number']}"
                                .toLowerCase();
                        return aLabel.compareTo(bLabel);
                      });

                      final dropdownValues = [
                        'Batches',
                        ...uniqueBatches.map(
                          (b) => "${b['method']}: ${b['batch_number']}",
                        ),
                      ];

                      final currentValue =
                          dropdownValues.contains(selectedMethod.value)
                              ? selectedMethod.value
                              : dropdownValues.first;

                      return DropdownButtonHideUnderline(
                        child: DropdownButton2<String>(
                          isExpanded: true,
                          buttonStyleData: ButtonStyleData(
                            width: double.infinity,
                            height: 35,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9D9D9),
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),

                          // Popup‐menu styling
                          dropdownStyleData: DropdownStyleData(
                            width: w * 0.4,
                            maxHeight: 42 * 5,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            offset: const Offset(0, 0),
                          ),

                          menuItemStyleData: const MenuItemStyleData(
                            height: 42,
                            padding: EdgeInsets.zero,
                          ),

                          // Items
                          items:
                              dropdownValues.map((value) {
                                final isSelected =
                                    (value == selectedMethod.value);
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: SizedBox(
                                    width: w * 0.6,
                                    child: Container(
                                      margin: EdgeInsets.symmetric(
                                        horizontal: w * 0.015,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            isSelected
                                                ? const Color(0xFFD9D9D9)
                                                : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        value,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),

                          value: currentValue,

                          onChanged: (v) {
                            if (v == null) return;
                            selectedMethod.value = v;
                            if (v != 'Batches') {
                              final match = _batches.firstWhere(
                                (b) =>
                                    "${b['method']}: ${b['batch_number']}" == v,
                                orElse: () => <String, dynamic>{},
                              );
                              if (match.isNotEmpty) {
                                _jumpToBatchWeek(match['id'] as String);
                              }
                            }
                          },

                          iconStyleData: const IconStyleData(
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: Colors.black,
                            ),
                          ),

                          style: TextStyle(
                            color: Colors.black,
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              SizedBox(height: h * 0.015),

              Expanded(
                child: Obx(() {
                  if (_net.isOffline.value) {
                    if (isLoadingOffline.value) {
                      Future.delayed(const Duration(milliseconds: 1500), () {
                        isLoadingOffline.value = false;
                      });
                      return const Center(child: CircularProgressIndicator());
                    } else {
                      return Center(
                        child: OfflineBanner(
                          onTryAgain: () {
                            final networkController =
                                Get.find<NetworkController>();
                            networkController.checkConnectivity();
                          },
                        ),
                      );
                    }
                  }
                  if (isLoadingBatches.value) {}

                  if (!isLoadingOffline.value) {
                    isLoadingOffline.value = true;
                  }

                  final filteredBatches =
                      _batches.where((batch) {
                        final batchIdStr =
                            "${batch['method']}: ${batch['batch_number']}";
                        final matchesMethod =
                            selectedMethod.value == 'Batches' ||
                            selectedMethod.value == batchIdStr;

                        final datePlanted = DateTime.tryParse(
                          batch['date_planted'] ?? '',
                        );
                        final matchesDate =
                            selectedDate == null ||
                            (datePlanted != null &&
                                !datePlanted.isAfter(selectedDate!));

                        return matchesMethod && matchesDate;
                      }).toList();

                  filteredBatches.sort((a, b) {
                    final aDate =
                        DateTime.tryParse(a['date_planted'] ?? '') ??
                        DateTime(1900);
                    final bDate =
                        DateTime.tryParse(b['date_planted'] ?? '') ??
                        DateTime(1900);
                    return aDate.compareTo(bDate);
                  });

                  return RefreshIndicator(
                    onRefresh: () async => _loadBatches(),
                    child:
                        filteredBatches.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Start Planting!',
                                    style: TextStyle(
                                      fontSize: h * 0.022,
                                      fontFamily: 'Inter_Bold',
                                      color: const Color(0xFF95B45B),
                                    ),
                                  ),
                                  Text(
                                    'You currently have no batch.\nClick + sign to add a batch',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: h * 0.018,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : ListView.builder(
                              controller: scrollController,
                              itemCount: filteredBatches.length,
                              padding: EdgeInsets.symmetric(
                                horizontal: w * 0.04,
                              ),
                              itemBuilder:
                                  (ctx, index) => KeyedSubtree(
                                    key: ValueKey(filteredBatches[index]['id']),
                                    child: _buildCard(
                                      filteredBatches[index],
                                      w,
                                      h,
                                    ),
                                  ),
                            ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> batch, double w, double h) {
    final batchId = batch['id'] ?? '';
    final rawBatchNum = batch['batch_number'];
    final batchNumber =
        rawBatchNum is int
            ? rawBatchNum
            : int.tryParse(rawBatchNum?.toString() ?? '') ?? 0;

    final method = batch['method'];
    final datePlanted =
        DateTime.tryParse(batch['date_planted'] ?? '') ?? DateTime.now();
    final numOfPlants =
        batch['num_of_plants'] is int
            ? batch['num_of_plants'] as int
            : int.tryParse(batch['num_of_plants']?.toString() ?? '');

    final int? predictedHarvestDay =
        (batch['days_until_harvest'] as num?)?.toInt();
    final currentDate = selectedDate ?? DateTime.now();

    final daysSinceSelected = currentDate.difference(datePlanted).inDays;
    final harvestProgress =
        (predictedHarvestDay != null &&
                predictedHarvestDay + daysSinceSelected > 0)
            ? daysSinceSelected / (daysSinceSelected + predictedHarvestDay)
            : 0.0;

    final bool isHarvested =
        (batch['is_harvested'] as String?)?.toLowerCase() == 'yes';

    final predictedHarvestDate = currentDate.add(
      Duration(days: predictedHarvestDay ?? 0),
    );

    final bool isPastHarvestDayAndNotHarvested =
        predictedHarvestDay != null &&
        currentDate.isAfter(predictedHarvestDate) &&
        !isHarvested;

    final Color harvestStrokeColor =
        isPastHarvestDayAndNotHarvested ? Colors.red : const Color(0xff61A3BA);
    final Color harvestInnerColor =
        isPastHarvestDayAndNotHarvested
            ? const Color.fromARGB(255, 238, 130, 139)
            : const Color(0xFF9DD5D8);

    final batchStatus = batch['status'] as Map<String, dynamic>? ?? {};
    final tempText = (batch['temperature'] as String?) ?? '';
    final humText = (batch['humidity'] as String?) ?? '';
    final tdsText = (batch['tds'] as String?) ?? '';
    final phText = (batch['ph'] as String?) ?? '';

    final bool noReadings =
        tempText.isEmpty &&
        humText.isEmpty &&
        tdsText.isEmpty &&
        phText.isEmpty;

    final Color statusStrokeColor =
        batchStatus['strokeColor'] as Color? ?? Colors.grey;
    final String statusValue = batchStatus['value'] as String? ?? '...';

    return Padding(
      padding: EdgeInsets.only(bottom: h * 0.002),
      child: Slidable(
        key: ValueKey(batchId),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.4,
          children: [
            CustomSlidableAction(
              onPressed:
                  (context) => _showHarvestConfirmation(batchId, datePlanted),
              backgroundColor: Colors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, size: 20, color: Colors.white),
                ],
              ),
            ),
            CustomSlidableAction(
              onPressed: (context) => _showDeleteConfirmation(batchId),
              backgroundColor: Colors.red,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outlined, size: 20, color: Colors.white),
                ],
              ),
            ),
          ],
        ),

        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (selectedDate != null && selectedDate!.isAfter(DateTime.now())) {
              Flushbar(
                message: "Cannot open batch for future dates.",
                duration: Duration(seconds: 3),
                flushbarPosition: FlushbarPosition.BOTTOM,
                backgroundColor: Colors.redAccent,
                margin: EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(12),
                icon: Icon(Icons.warning_rounded, color: Colors.white),
              ).show(context);
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => BatchInfo(
                      batchId: batchId,
                      batchNumber: batchNumber,
                      datePlanted: datePlanted,
                      numOfPlants: numOfPlants,
                      selectedDate: selectedDate,
                      method: method,
                    ),
              ),
            );
          },
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            color: Colors.white.withOpacity(0.75),
            child: Padding(
              padding: EdgeInsets.all(w * 0.04),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: w * 0.22,
                        height: w * 0.28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFEC),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              method,
                              style: TextStyle(
                                fontSize: w * 0.04,
                                fontFamily: 'Inter_Bold',
                              ),
                            ),
                            Text(
                              '$batchNumber',
                              style: TextStyle(
                                fontSize: w * 0.08,
                                fontFamily: 'Inter_Bold',
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Color(0xFFACC38F),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                DateFormat('MMM d').format(datePlanted),
                                style: TextStyle(
                                  fontSize: w * 0.028,
                                  fontFamily: 'Inter_Bold',
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: w * 0.04),
                      FutureBuilder(
                        future: Future.delayed(
                          const Duration(milliseconds: 800),
                        ),
                        builder: (context, snapshot) {
                          final isLoading =
                              snapshot.connectionState != ConnectionState.done;

                          return Padding(
                            padding: EdgeInsets.zero,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                StatusIndicator(
                                  label:
                                      (predictedHarvestDay == 0 ||
                                              (predictedHarvestDay != null &&
                                                  predictedHarvestDay < 0))
                                          ? ''
                                          : 'Harvest in',
                                  value:
                                      (predictedHarvestDay != null &&
                                              predictedHarvestDay == 0)
                                          ? (batch['predictedHarvest'] == null
                                              ? ''
                                              : 'Harvest\nDay!')
                                          : (predictedHarvestDay != null
                                              ? (predictedHarvestDay < 0
                                                  ? '${-predictedHarvestDay} days\nlate!'
                                                  : '$predictedHarvestDay days')
                                              : ''),

                                  strokeColor: harvestStrokeColor,
                                  innerColor: harvestInnerColor,
                                  size: w * 0.25,
                                  progress:
                                      isLoading
                                          ? 0.0
                                          : (predictedHarvestDay != null
                                              ? harvestProgress
                                              : 0.0),
                                  isPredictedValue: predictedHarvestDay != null,
                                  isLoading: isLoading,
                                ),
                                SizedBox(width: w * 0.04),
                                StatusIndicator(
                                  label: 'Status',
                                  value: statusValue,
                                  strokeColor: statusStrokeColor,
                                  innerColor:
                                      noReadings || isLoading
                                          ? const Color(0xFFACC38F)
                                          : batchStatus['innerColor']
                                                  as Color? ??
                                              Colors.transparent,
                                  size: w * 0.25,
                                  progress:
                                      isLoading
                                          ? 0.0
                                          : (predictedHarvestDay != null
                                              ? harvestProgress
                                              : 0.0),
                                  isLoading: isLoading,
                                  phAbnormal:
                                      (batchStatus['phAbnormal'] as bool?) ??
                                      false,
                                  tdsAbnormal:
                                      (batchStatus['tdsAbnormal'] as bool?) ??
                                      false,
                                  emojiAsset:
                                      batchStatus['emojiAsset'] as String?,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  //──────────────────────────────────  DELETE/HARVEST UI LAYOUT  ─────────────────────────────────
  void _showDeleteConfirmation(String batchId) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.all(20),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_rounded, size: 40, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(
                  'Delete Batch',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.040,
                    fontFamily: 'Inter_Bold',
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: screenHeight * 0.010),
                Text(
                  'Are you sure you want to delete this batch? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.036,
                    color: Color.fromARGB(255, 85, 85, 85),
                  ),
                ),
                SizedBox(height: screenHeight * 0.024),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    SizedBox(width: screenHeight * 0.014),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _deleteBatch(batchId);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  void _showHarvestConfirmation(String batchId, DateTime datePlanted) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final int daysPlanted = DateTime.now().difference(datePlanted).inDays;
    if (daysPlanted < 3) {
      showCustomErrorDialog(
        context,
        title: 'Too Early to Harvest',
        message:
            'This batch has only been planted for $daysPlanted day${daysPlanted == 1 ? '' : 's'}. Please wait a few more days before harvesting.',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.all(20),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 40, color: Colors.green),
                SizedBox(height: screenHeight * 0.012),
                Text(
                  'Harvest Batch',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.04,
                    fontFamily: 'Inter_Bold',
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: screenHeight * 0.010),
                Text(
                  'Are you sure you want to mark this batch as harvested? This action cannot be undone.\n\n',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.036,
                    color: Color.fromARGB(255, 85, 85, 85),
                  ),
                ),
                Text(
                  'Note: This batch has only been planted for $daysPlanted day${daysPlanted == 1 ? '' : 's'}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.036,
                    color: Color.fromARGB(255, 85, 85, 85),
                    fontFamily: 'Inter_Bold',
                  ),
                ),
                SizedBox(height: screenHeight * 0.024),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    SizedBox(width: screenHeight * 0.014),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _harvestBatch(batchId);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}
