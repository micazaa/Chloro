import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../../services/network_connection.dart';

class CalendarScreen extends StatefulWidget {
  final List<Map<String, dynamic>> batchSchedules;

  const CalendarScreen({Key? key, required this.batchSchedules})
    : super(key: key);

  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime? selectedDate;
  DateTime today = DateTime.now();
  final List<String> weekDays = ["S", "M", "T", "W", "T", "F", "S"];
  final ScrollController _scrollCtrl = ScrollController();

  final List<DateTime> months = List.generate(12, (i) => DateTime(2025, i + 1));
  final List<GlobalKey> _monthKeys = List.generate(12, (_) => GlobalKey());
  List<Map<String, dynamic>> _batches = [];
  Map<String, Map<String, dynamic>>? _batchScheduleById;

  List<Map<String, dynamic>> _batchSchedules = [];
  String? _selectedBatchId;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.batchSchedules.isNotEmpty) {
        setState(() {
          _batchSchedules = widget.batchSchedules;
          _batchScheduleById = {
            for (var s in _batchSchedules) s['batch_id'] as String: s,
          };
          _selectedBatchId =
              _batchSchedules.isNotEmpty
                  ? _batchSchedules.first['batch_id'] as String?
                  : null;
        });
      }
      _jumpToCurrentMonth();
    });
  }

  void _jumpToCurrentMonth() {
    final now = DateTime.now();
    if (now.year != 2025) return;
    final idx = now.month - 1;
    final ctx = _monthKeys[idx].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final NetworkController _net = Get.find();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFEC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E9E9),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        automaticallyImplyLeading: true,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFE9E9E9),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04,
                      vertical: screenHeight * 0.001,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.04,
                    vertical: screenHeight * 0.01,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 1),
                    ),
                  ),
                  child: Row(
                    children:
                        weekDays.map((d) {
                          return Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: TextStyle(
                                  fontSize: screenHeight * 0.014,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Obx(() {
            if (_net.isOffline.value) {
              return Container(
                width: double.infinity,
                color: Colors.redAccent,
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                child: Center(
                  child: Text(
                    "No internet connection",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: screenHeight * 0.014,
                    ),
                  ),
                ),
              );
            } else {
              return const SizedBox.shrink();
            }
          }),

          // MAIN CONTENT
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  child: Column(
                    children:
                        months.map((month) {
                          final idx = months.indexOf(month);
                          return Padding(
                            key: _monthKeys[idx],
                            padding: EdgeInsets.only(
                              bottom: screenHeight * 0.05,
                            ),
                            child: _buildMonthView(
                              month,
                              screenWidth,
                              screenHeight,
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  //──────────────────────────────────  MONTH  ─────────────────────────────────

  Widget _buildMonthView(DateTime month, double sw, double sh) {
    final days = _generateMonthDays(month);
    final monthYear = DateFormat.yMMMM().format(month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            sw * 0.04,
            sh * 0.015,
            sw * 0.04,
            sh * 0.008,
          ),
          child: Text(
            monthYear,
            style: TextStyle(fontSize: sh * 0.022, fontWeight: FontWeight.bold),
          ),
        ),

        // Days grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: sh * 0.005,
            childAspectRatio: 1,
          ),
          itemCount: days.length,
          itemBuilder: (context, idx) {
            final date = days[idx];
            if (date == null) return const SizedBox.shrink();

            final isCurrentMonth = date.month == month.month;
            final isSelected =
                selectedDate != null &&
                DateUtils.isSameDay(selectedDate!, date);
            final isToday = DateUtils.isSameDay(date, today);

            final isBatchedDay = _batchSchedules.any((s) {
              if (s['isHarvested'] == true) return false;

              final plantedRaw = s['planted'];
              final predictedHarvestRaw = s['predictedHarvest'];

              if (plantedRaw == null || predictedHarvestRaw == null)
                return false;

              final planted =
                  plantedRaw is DateTime
                      ? plantedRaw
                      : parsePlanted(plantedRaw);
              final predictedHarvest =
                  predictedHarvestRaw is DateTime
                      ? predictedHarvestRaw
                      : parsePlanted(predictedHarvestRaw);

              return !date.isBefore(planted) && !date.isAfter(predictedHarvest);
            });

            final isPlantedDay = _batchSchedules.any((s) {
              if (s['isHarvested'] == true) return false;

              final plantedRaw = s['planted'];
              if (plantedRaw == null) return false;

              final planted =
                  plantedRaw is DateTime
                      ? plantedRaw
                      : parsePlanted(plantedRaw);

              return DateUtils.isSameDay(date, planted);
            });

            final isPredictedHarvestDay = _batchSchedules.any((s) {
              if (s['isHarvested'] == true) return false;

              final predictedHarvestRaw = s['predictedHarvest'];
              if (predictedHarvestRaw == null) return false;

              final predictedHarvest =
                  predictedHarvestRaw is DateTime
                      ? predictedHarvestRaw
                      : parsePlanted(predictedHarvestRaw);

              return DateUtils.isSameDay(date, predictedHarvest);
            });

            Color fillColor;
            Border? border;

            if (isPlantedDay) {
              fillColor = Colors.transparent;
              border = Border.all(color: Colors.green, width: 2.5);
            } else if (isPredictedHarvestDay) {
              fillColor = Colors.transparent;
              border = Border.all(color: Colors.redAccent, width: 2);
            } else if (isBatchedDay) {
              fillColor = const Color(0xFF9dd5d8);
            } else if (isToday) {
              fillColor = Colors.black.withOpacity(0.1);
            } else if (isSelected) {
              fillColor = const Color.fromARGB(171, 198, 198, 198);
            } else {
              fillColor = Colors.transparent;
              border = null;
            }

            final textColor =
                isCurrentMonth
                    ? (isSelected ? Colors.black : Colors.black)
                    : Colors.grey.shade400;

            return GestureDetector(
              onTap: () => _onDateSelected(date),
              child: Center(
                child: SizedBox(
                  height: sw * 0.09 + sh * 0.02,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: sh * 0.018,
                        child: Center(
                          child:
                              isToday
                                  ? Text(
                                    'TODAY',
                                    style: TextStyle(
                                      fontSize: sh * 0.012,
                                      fontFamily: 'Inter_Bold',
                                      color: Colors.black,
                                    ),
                                  )
                                  : const SizedBox.shrink(),
                        ),
                      ),
                      Container(
                        width: sw * 0.08,
                        height: sw * 0.08,
                        decoration: BoxDecoration(
                          color: fillColor,
                          shape: BoxShape.circle,
                          border:
                              isPlantedDay
                                  ? Border.all(color: Colors.green, width: 2)
                                  : isPredictedHarvestDay
                                  ? Border.all(
                                    color: Colors.redAccent,
                                    width: 2,
                                  )
                                  : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: sh * 0.016,
                            color:
                                isPredictedHarvestDay
                                    ? Colors.redAccent
                                    : textColor,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                            fontFamily:
                                isPredictedHarvestDay ? 'Inter_Bold' : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  List<DateTime?> _generateMonthDays(DateTime month) {
    int firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    int numDays = DateTime(month.year, month.month + 1, 0).day;
    List<DateTime?> days = [];
    for (int i = 0; i < firstWeekday; i++) days.add(null);
    for (int i = 1; i <= numDays; i++)
      days.add(DateTime(month.year, month.month, i));
    return days;
  }

  void _onDateSelected(DateTime date) async {
    setState(() {
      selectedDate = date;
    });

    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    var query = Supabase.instance.client
        .from('readings')
        .select('*, batches(method, is_harvested)')
        .eq('date', dateStr)
        .eq('user_id', user.id);

    if (_selectedBatchId != null && _selectedBatchId!.isNotEmpty) {
      query = query.eq('batch_id', _selectedBatchId!);
    }

    final readings = await query;

    print('Readings for $dateStr: ${readings.length}');

    // Filter out readings from harvested batches
    final filtered =
        readings.where((r) {
          final isHarvested =
              (r['batches']?['is_harvested'] ?? '').toString().toLowerCase();
          return isHarvested != 'yes';
        }).toList();

    // For each reading, add batch day info (isPlantedDay, batchAge)
    for (var r in filtered) {
      final batchId = r['batch_id'];

      // Find the matching batch schedule for this reading
      Map<String, dynamic>? plantedSchedule;
      try {
        plantedSchedule = _batchSchedules.firstWhere((s) {
          // Match by batch_id or (batch_number + method) as fallback
          return s['batch_id'] == batchId ||
              (s['batch_number'] == r['batch_number'] &&
                  s['method'] == r['batches']?['method']);
        });
      } catch (_) {
        plantedSchedule = null;
      }

      r['isPlantedDay'] = false;
      r['batchAge'] = null;

      if (plantedSchedule != null) {
        final plantedRaw = plantedSchedule['planted'];
        DateTime plantedDate;

        if (plantedRaw is DateTime) {
          plantedDate = plantedRaw;
        } else if (plantedRaw is String) {
          plantedDate = DateTime.tryParse(plantedRaw) ?? date;
        } else if (plantedRaw is int) {
          plantedDate = DateTime.fromMillisecondsSinceEpoch(plantedRaw);
        } else {
          plantedDate = date;
        }

        r['isPlantedDay'] = DateUtils.isSameDay(plantedDate, date);
        r['batchAge'] = date.difference(plantedDate).inDays + 1; // 1-based day
      }

      print(
        "Reading batch ${r['batch_number']}: isPlantedDay=${r['isPlantedDay']}, batchAge=${r['batchAge']}",
      );
    }

    // Sort readings by method and batch number
    filtered.sort((a, b) {
      final methodA = (a['batches']?['method'] ?? '').toString().toLowerCase();
      final methodB = (b['batches']?['method'] ?? '').toString().toLowerCase();
      final batchNumA = int.tryParse(a['batch_number']?.toString() ?? '') ?? 0;
      final batchNumB = int.tryParse(b['batch_number']?.toString() ?? '') ?? 0;

      final methodCompare = methodA.compareTo(methodB);
      if (methodCompare != 0) return methodCompare;
      return batchNumA.compareTo(batchNumB);
    });

    // Show the modal bottom sheet with filtered readings
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder:
          (_) => _buildReadingsSheet(
            date,
            filtered,
            sw: MediaQuery.of(context).size.width,
            sh: MediaQuery.of(context).size.height,
          ),
    );
  }

  Widget _buildReadingsSheet(
    DateTime date,
    List<dynamic> readings, {
    required double sw,
    required double sh,
  }) {
    return Padding(
      padding: EdgeInsets.all(sw * 0.04),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${DateFormat.MMMd().format(date)} Readings",
              style: TextStyle(fontSize: sh * 0.020, fontFamily: 'Inter_Bold'),
            ),
            SizedBox(height: sh * 0.02),
            if (readings.isEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(sw * 0.04),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "No readings found for this date.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: sh * 0.016),
                ),
              ),
            ...readings.map(
              (r) => Padding(
                padding: EdgeInsets.only(bottom: sh * 0.015),
                child: _buildReadingCard(
                  r['batch_number']?.toString() ?? 'Unknown',
                  r['batches']?['method']?.toString() ?? 'Unknown',
                  (r['ph'] as num?)?.toDouble() ?? 0.00,
                  (r['tds'] as num?)?.toDouble() ?? 0.00,
                  (r['temperature'] as num?)?.toDouble() ?? 0.00,
                  (r['humidity'] as num?)?.toDouble() ?? 0.00,
                  sw,
                  sh,
                  isPlantedDay: r['isPlantedDay'] ?? false,
                  batchAge: r['batchAge'] as int?,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingCard(
    String batchNumber,
    String batchMethod,
    double ph,
    double tds,
    double temp,
    double humidity,
    double sw,
    double sh, {
    bool isPlantedDay = false,
    int? batchAge,
  }) {
    String firstPart = "$batchMethod Batch $batchNumber ";
    String secondPart = "";

    if (isPlantedDay) {
      secondPart = " • Planted Day";
    } else if (batchAge != null) {
      secondPart = " • Day $batchAge";
    }

    return Container(
      padding: EdgeInsets.all(sw * 0.04),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: sh * 0.018,
                fontFamily: 'Inter_Bold',
                color: Colors.black,
              ),
              children: [
                TextSpan(text: firstPart),
                if (secondPart.isNotEmpty)
                  TextSpan(
                    text: secondPart,
                    style: TextStyle(
                      fontSize: sh * 0.018,
                      fontFamily: 'Inter_Bold',
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: sh * 0.015),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildReadingItem(ph.toStringAsFixed(2), "pH", sh),
              _buildReadingItem(tds.toStringAsFixed(2), "TDS", sh),
              _buildReadingItem(temp.toStringAsFixed(2), "Temp", sh),
              _buildReadingItem(humidity.toStringAsFixed(2), "Humid", sh),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadingItem(String value, String label, double sh) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: sh * 0.018, fontFamily: 'Inter_Bold'),
        ),
        SizedBox(height: sh * 0.005),
        Text(
          label,
          style: TextStyle(fontSize: sh * 0.016, color: Colors.black54),
        ),
      ],
    );
  }
}
