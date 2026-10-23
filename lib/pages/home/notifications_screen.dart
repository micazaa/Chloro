import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';

import '../../services/notificationService.dart';
import '../batch/batch_info.dart';
import '../../services/network_connection.dart';
import '../../helpers/offline_banner.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsState();
}

class _NotificationsState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _supabaseNotifications;

  @override
  void initState() {
    super.initState();
    _supabaseNotifications = _loadNotificationsFromSupabase();
  }

  Future<List<Map<String, dynamic>>> _loadNotificationsFromSupabase() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final response = await supabase
        .from('notifications')
        .select()
        .eq('user_id', user.id)
        .eq('sent', false)
        .order('date', ascending: false);

    if (response is List<dynamic>) {
      return List<Map<String, dynamic>>.from(response);
    } else {
      return [];
    }
  }

  void _refreshNotificationsList() {
    setState(() {
      _supabaseNotifications = _loadNotificationsFromSupabase();
    });
  }

  //──────────────────────────────────  GROUP NOTIFS BY DATE  ─────────────────────────────────

  Map<DateTime, List<Map<String, dynamic>>> _groupByDate(
    List<Map<String, dynamic>> rows,
  ) {
    final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    for (final row in rows) {
      final dateStr = row['date'] as String? ?? '';
      DateTime parsedDate;
      try {
        parsedDate = DateTime.parse(dateStr);
      } catch (_) {
        parsedDate = todayOnly;
      }
      final onlyRowDate = DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
      );

      final payload = Map<String, dynamic>.from(row['payload'] as Map);
      final String type = payload['type'] as String? ?? 'nutrient';

      DateTime groupingDate;
      if (type == 'harvest') {
        if (!onlyRowDate.isAfter(todayOnly)) {
          groupingDate = todayOnly;
        } else {
          groupingDate = onlyRowDate;
        }
      } else {
        // nutrient/recommendation: group under its own date
        groupingDate = onlyRowDate;
      }

      grouped.putIfAbsent(groupingDate, () => []).add(row);
    }

    // Sort keys descending so “today” appears first
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final Map<DateTime, List<Map<String, dynamic>>> sorted = {};
    for (final k in sortedKeys) {
      sorted[k] = grouped[k]!;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.width;
    final screenWidth = MediaQuery.of(context).size.height;
    final NetworkController _net = Get.find();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontSize: screenWidth * 0.026,
            fontFamily: 'Inter_Bold',
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromARGB(255, 225, 246, 204),
              Color.fromARGB(255, 234, 238, 201),
              Color.fromARGB(255, 238, 238, 197),
            ],
          ),
        ),
        child: SafeArea(
          child: Obx(() {
            if (_net.isOffline.value) {
              return Center(
                child: OfflineBanner(
                  onTryAgain: () => _net.checkConnectivity(),
                ),
              );
            }

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _supabaseNotifications,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/nonotif.png',
                        width: screenHeight * 0.14,
                        height: screenHeight * 0.14,
                        fit: BoxFit.contain,
                      ),
                      Text(
                        'No notifications here',
                        style: TextStyle(
                          fontSize: screenWidth * 0.020,
                          fontFamily: 'Inter_Bold',
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'No nutrient adjustments needed at the moment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenHeight * 0.014,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  );
                }

                final grouped = _groupByDate(rows);
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);

                final List<Widget> listItems = [];
                grouped.forEach((dateKey, notifsOnThatDate) {
                  final headerText =
                      (dateKey == today)
                          ? 'Today'
                          : DateFormat.MMMMd().format(dateKey);

                  // Add date header
                  listItems.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18.0, 10.0, 18.0, 2.0),
                      child: Text(
                        headerText,
                        style: TextStyle(
                          fontSize: screenWidth * 0.018,
                          fontFamily: 'Inter_Bold',
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  );

                  for (final notifRow in notifsOnThatDate) {
                    final int notifId = notifRow['id'] as int;
                    final String title = notifRow['title'] as String? ?? '';
                    final String body = notifRow['body'] as String? ?? '';
                    final Map<String, dynamic> payload =
                        Map<String, dynamic>.from(notifRow['payload'] as Map);

                    final bool isHarvestOverdue = (title == 'Harvest Overdue');

                    // red for overdue, otherwise black
                    final Color textColor =
                        isHarvestOverdue ? Colors.red : Colors.black87;

                    final String type =
                        payload['type'] as String? ?? 'nutrient';
                    Color iconBgColor;
                    IconData iconData;
                    Color iconColor;

                    if (type == 'harvest') {
                      final String? phStr =
                          payload['predictedHarvest'] as String?;

                      if (phStr != null) {
                        final predictedHarvest =
                            DateTime.parse(phStr).toLocal();
                        final todayDate = DateTime.now();
                        final harvestDate = DateTime(
                          predictedHarvest.year,
                          predictedHarvest.month,
                          predictedHarvest.day,
                        );
                        final todayOnly = DateTime(
                          todayDate.year,
                          todayDate.month,
                          todayDate.day,
                        );
                        if (harvestDate.isBefore(todayOnly)) {
                          // Overdue
                          iconBgColor = Colors.red.shade100;
                          iconColor = Colors.redAccent;
                          iconData = Icons.grass_rounded;
                        } else if (harvestDate.isAtSameMomentAs(todayOnly)) {
                          // Harvest day
                          iconBgColor = const Color.fromARGB(
                            255,
                            210,
                            233,
                            210,
                          );
                          iconColor = Colors.green;
                          iconData = Icons.grass_rounded;
                        } else {
                          iconBgColor = Colors.grey.shade200;
                          iconColor = Colors.grey;
                          iconData = Icons.grass_rounded;
                        }
                      } else {
                        iconBgColor = const Color.fromARGB(255, 210, 233, 210);
                        iconColor = Colors.green;
                        iconData = Icons.grass_rounded;
                      }
                    } else {
                      // Nutrient alert
                      iconBgColor = Colors.orange.shade100;
                      iconColor = Colors.orangeAccent;
                      iconData = Icons.warning_rounded;
                    }

                    listItems.add(
                      Card(
                        color: Colors.white,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            final String batchId = payload['batchId'] as String;
                            final batchNumberRaw = payload['batchNumber'];
                            final int batchNumber =
                                batchNumberRaw is int
                                    ? batchNumberRaw
                                    : int.tryParse(batchNumberRaw.toString()) ??
                                        0;

                            final String? method = payload['method'] as String?;
                            final String? selectedDateStr =
                                payload['date'] as String?;
                            final String? datePlantedStr =
                                payload['datePlanted'] as String?;

                            DateTime datePlanted = DateTime.now();
                            if (datePlantedStr != null) {
                              datePlanted =
                                  DateTime.parse(datePlantedStr).toLocal();
                            }
                            DateTime selectedDate = DateTime.now();
                            if (selectedDateStr != null) {
                              selectedDate =
                                  DateTime.parse(selectedDateStr).toLocal();
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => BatchInfo(
                                      batchId: batchId,
                                      batchNumber: batchNumber,
                                      selectedDate: selectedDate,
                                      method: method,
                                      datePlanted: datePlanted,
                                    ),
                              ),
                            ).then((_) {
                              _refreshNotificationsList();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: iconBgColor,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    iconData,
                                    color: iconColor,
                                    size: screenWidth * 0.026,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'No Title' : title,
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.018,
                                          fontFamily: 'Inter_Bold',
                                          color: textColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        body.isEmpty ? 'No Body' : body,
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.016,
                                          fontWeight: FontWeight.bold,
                                          color: const Color.fromARGB(
                                            158,
                                            0,
                                            0,
                                            0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                });

                return ListView(children: listItems);
              },
            );
          }),
        ),
      ),
    );
  }
}
