import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../helpers/get_status.dart';
import '../../services/notificationService.dart';
import '../../helpers/status_indicator.dart';
import '../../services/auto_batch_services.dart';

class BatchInfo extends StatefulWidget {
  final String batchId;
  final int batchNumber;
  final DateTime datePlanted;
  final int? numOfPlants;
  final DateTime? selectedDate;
  final String? method;

  const BatchInfo({
    super.key,
    required this.batchId,
    required this.batchNumber,
    required this.datePlanted,
    this.numOfPlants,
    this.selectedDate,
    this.method,
  });

  static final GlobalKey<_BatchInfoState> activeKey =
      GlobalKey<_BatchInfoState>();

  @override
  State<BatchInfo> createState() => _BatchInfoState();
}

class _BatchInfoState extends State<BatchInfo> {
  bool _isCurrentScreen = true;
  bool _justPredicted = false;
  bool _hasUpdated = false;
  DateTime? latestInputDate;

  // ──────────────────── STATE ────────────────────
  bool isManualMode = true;
  late final String selectedBatchId;
  int? predictedHarvestDay;
  bool _isLoading = false;
  bool _hasReading = false;
  bool _isPredictingHarvest = false;
  bool _isPredictingNutrient = false;
  Flushbar<void>? _bottomFlushbar;
  bool isEditMode = false;

  // Text‑controllers
  final _tempC = TextEditingController();
  final _humC = TextEditingController();
  final _tdsC = TextEditingController();
  final _phC = TextEditingController();

  String? phAdjustment;
  String? tdsAdjustment;
  String? temperatureStatus;
  String? humidityStatus;
  bool get isAbnormal => (phAdjustment != null) || (tdsAdjustment != null);
  bool _predictionPending = false;
  SharedPreferences? _prefs;

  List<Map<String, String>> _insightList = [];

  String _pendingKey(String batchId, DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return 'prediction_pending_${batchId}_$dateStr';
  }

  @override
  void initState() {
    super.initState();
    selectedBatchId = widget.batchId;
    _loadPrefs();
    loadBatchInfo();
    checkUserExit();
    _isCurrentScreen = true;
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();

    bool? savedManualMode = _prefs?.getBool('batch_mode_${widget.batchId}');
    if (savedManualMode != null) {
      setState(() {
        isManualMode = savedManualMode;
      });
    }

    final key = _pendingKey(
      selectedBatchId,
      widget.selectedDate ?? DateTime.now(),
    );
    final pending = _prefs?.getBool(key) ?? false;

    if (pending) {
      setState(() {
        _predictionPending = true;
      });
    }
  }

  Future<void> _saveMode(bool manualMode) async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    await _prefs!.setBool('batch_mode_${widget.batchId}', manualMode);
  }

  @override
  void dispose() {
    _tempC.dispose();
    _humC.dispose();
    _tdsC.dispose();
    _phC.dispose();
    hasUserExited = true;
    final dateKey = DateFormat(
      'yyyy-MM-dd',
    ).format(widget.selectedDate ?? DateTime.now());
    _prefs!.setBool('hasUserExited_$dateKey', true);

    _isCurrentScreen = false;
    super.dispose();
  }

  static const Map<String, String> _detailInsight = {
    'Low pH':
        'pH below optimal range reduces nutrient solubility and stresses roots.',
    'High pH':
        'pH above optimal alkalizes solution, precipitating essential minerals.',
    'Low Temperature':
        'Cool temperatures slow metabolic and enzymatic activity.',
    'High Temperature':
        'Warm temperatures increase transpiration and risk of heat stress.',
    'Low Humidity':
        'Low humidity causes stomatal closure, limiting gas exchange.',
    'High Humidity':
        'High humidity fosters fungal growth and poor root aeration.',
    'Low TDS':
        'Low nutrient concentration leads to deficiency and stunted growth.',
    'High TDS':
        'High nutrient levels can cause osmotic stress and nutrient lockout.',
    'Early':
        'Parameters are optimal but harvest is early. This might be caused by past fluctuations in nutrient levels that causes for it to mature early.',
    'Good':
        'All parameters are within optimal ranges; harvest timing is ideal.',
    'Late':
        'Parameters are optimal but harvest is late. This might be caused by past fluctuations in temperature, pH, or nutrient levels that causes for it to mature late.',
  };
  static const Map<String, String> _detailAction = {
    'Low pH': 'Add pH Up solution to raise to 5.8–6.2.',
    'High pH':
        'Add pH Down solution to lower to 5.8–6.2 or dilute the reservoir.',
    'Low Temperature':
        'Increase ambient temperature by moving the system to a warmer area or add a layer of insulation around the reservoir to retain heat.',
    'High Temperature':
        'Add shade around the plants or move the system to a cooler spot with better airflow to reduce excessive heat buildup or add ice packs to reservoir briefly.',
    'Low Humidity': 'Increase humidity by lightly misting the plants.',
    'High Humidity': 'Increase airflow around roots.',
    'Low TDS': 'Add more nutrient solution to the reservoir.',
    'High TDS': 'Dilute the reservoir.',
    'Early':
        'Examine historical data for parameter fluctuations that may have caused stress, resulting in premature harvest.',
    'Good':
        'Maintain current hydroponic settings; continue routine nutrient checks.',
    'Late':
        'Examine historical data for parameter fluctuations that may have delayed growth; adjust nutrient schedule accordingly.',
  };
  static const Map<String, String> _detailWarn = {
    'High pH': 'Consider reservoir dilution as alternative.',
    'Low Temperature': 'Insulate reservoir to retain heat.',
    'High Temperature': 'Add ice-packs briefly to reservoir.',
    'Early': 'No immediate warnings; monitor for signs of premature bolting.',
    'Good': 'No warnings; monitor parameters regularly.',
    'Late':
        'No immediate warnings; consider optimizing temperature and humidity management.',
  };
  static const Map<String, String> _detailRisk = {
    'Low pH':
        'Risk of nutrient deficiencies, root damage, resulting in stunted growth and yellow leaves.',
    'High pH':
        'Risk of nutrient lockout, resulting in stunted growth and yellow leaves.',
    'Low Temperature':
        'Risk of slow growth, root damage, and poor nutrient absorption.',
    'High Temperature':
        'Risk of heat stress, increased transpiration, and nutrient loss.',
    'Low Humidity':
        'Risk of dehydration, poor growth, and hindered nutrient absorption.',
    'High Humidity': 'Risk of mold, root rot, and fungal diseases.',
    'Low TDS':
        'Risk of nutrient deficiencies, leading to slow or stunted growth.',
    'High TDS': 'Risk of osmotic stress, nutrient burn, and plant dehydration.',
    'Early': 'Risk of prematurely bolting.',
    'Good': 'Plants are growing within ideal conditions.',
    'Late': 'Risk of bolting and increase exposure to diseases.',
  };

  String _computeHarvestStatus(int daysSinceSelected, int daysLeft) {
    final absoluteHarvestDay = daysSinceSelected + daysLeft;
    print('Absolute Harvest Day: $absoluteHarvestDay');
    if (absoluteHarvestDay >= 39 && absoluteHarvestDay <= 42) {
      return 'Early';
    } else if (absoluteHarvestDay >= 43 && absoluteHarvestDay <= 45) {
      return 'Good';
    } else {
      return 'Late';
    }
  }

  // ──────────────────────  HELPERS  ──────────────────────────
  String _calcDetailedStatus(double val, String kind) {
    switch (kind) {
      case 'pH':
        if (val < 5.5) return 'Low pH';
        if (val > 6.6) return 'High pH';
        return 'OK';
      case 'T':
        if (val < 15) return 'Low Temperature';
        if (val > 30) return 'High Temperature';
        return 'OK';
      case 'H':
        if (val < 50) return 'Low Humidity';
        if (val > 80) return 'High Humidity';
        return 'OK';
      case 'TDS':
        if (val < 400) return 'Low TDS';
        if (val > 900) return 'High TDS';
        return 'OK';
      default:
        return 'OK';
    }
  }

  //──────────────────────────────────  SUGGESTIONS/CHARTS  ─────────────────────────────────

  Widget _contentBox({
    required String title,
    required String content,
    required IconData icon,
    required Color bgColor,
    required double w,
    required double h,
    required String labelType,
  }) {
    Color getLabelColor(String type) {
      if (title == 'Good') {
        return const Color.fromARGB(255, 82, 157, 85).withOpacity(0.8);
      }
      switch (type) {
        case 'warning':
          return const Color.fromARGB(255, 212, 140, 32)!.withOpacity(0.8);
        case 'risk':
          return const Color.fromARGB(255, 212, 140, 32)!.withOpacity(0.8);

        case 'insight' || 'action':
          return const Color.fromARGB(255, 180, 60, 58)!.withOpacity(0.8);
        default:
          return Colors.grey.withOpacity(0.8);
      }
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: h * 0.006),
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: h * 0.03),
              SizedBox(width: w * 0.03),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.03,
                  vertical: h * 0.004,
                ),
                decoration: BoxDecoration(
                  color: getLabelColor(labelType),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: h * 0.018,
                    color: Colors.white,
                    fontFamily: 'Inter_Bold',
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(left: w * 0.09),
            child: Text(
              content,
              style: TextStyle(
                fontSize: h * 0.016,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _suggestionsExpanded = false;

  Widget _buildInsightContainer(double w, double h) {
    if (_insightList.isEmpty) return const SizedBox.shrink();

    final headerStyle = TextStyle(
      fontSize: h * 0.02,
      fontFamily: 'Inter_Bold',
      color: Colors.black87,
    );

    final labelStyle = TextStyle(
      fontSize: h * 0.018,
      fontFamily: 'Inter_Bold',
      color: Colors.black87,
    );

    List<Map<String, dynamic>> insightsList = [];
    List<Map<String, dynamic>> actionsList = [];
    List<Map<String, dynamic>> warningsList = [];
    List<Map<String, dynamic>> risksList = [];

    final Map<String, IconData> iconMap = {
      'pH': Icons.science_outlined,
      'TDS': Icons.water_drop_outlined,
      'T': Icons.thermostat,
      'H': Icons.opacity_outlined,
    };

    IconData _getIcon(String? kind) {
      final key = kind?.trim() ?? '';
      final icon = iconMap[key];
      if (icon == null) print('Fallback icon used for: "$key"');
      return icon ?? Icons.info_outline;
    }

    for (final data in _insightList) {
      print('kind: ${data['kind']}');
      final icon = _getIcon(data['kind'] ?? '');

      if (data['insight'] != null && data['insight']!.isNotEmpty) {
        insightsList.add({
          'title': data['title'],
          'text': data['insight'],
          'icon': icon,
        });
      }
      if (data['action'] != null && data['action']!.isNotEmpty) {
        actionsList.add({
          'title': data['title'],
          'text': data['action'],
          'icon': icon,
        });
      }
      if (data['warning'] != null && data['warning']!.isNotEmpty) {
        warningsList.add({
          'title': data['title'],
          'text': data['warning'],
          'icon': icon,
        });
      }
      if (data['risk'] != null && data['risk']!.isNotEmpty) {
        risksList.add({
          'title': data['title'],
          'text': data['risk'],
          'icon': icon,
        });
      }
    }

    List<Widget> _buildSuggestionSections() {
      List<Widget> sections = [];

      void addSection(
        String title,
        List<Map<String, dynamic>> items,
        Color containerColor,
        Color boxColor,
        String labelType,
      ) {
        if (items.isEmpty) return;
        sections.add(
          Container(
            padding: EdgeInsets.all(w * 0.04),
            margin: EdgeInsets.only(bottom: h * 0.01),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: labelStyle),
                ...items.map(
                  (item) => _contentBox(
                    title: item['title'],
                    content: item['text'],
                    icon: item['icon'],
                    bgColor: boxColor,
                    w: w,
                    h: h,
                    labelType: labelType,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final isAllGood =
          _insightList.length == 1 && _insightList.first['title'] == 'Good';

      addSection(
        'INSIGHTS',
        _insightList
            .where((e) => e['insight'] != null && e['insight']!.isNotEmpty)
            .map(
              (e) => {
                'title': e['title'],
                'text': e['insight'],
                'icon': _getIcon(e['kind']),
              },
            )
            .toList(),
        isAllGood
            ? const Color.fromARGB(255, 228, 243, 209)
            : const Color.fromARGB(255, 234, 201, 201),
        isAllGood ? Color(0xFFA0C878) : Colors.red[400]!,
        'insight',
      );

      addSection(
        'RECOMMENDED ACTION',
        _insightList
            .where((e) => e['action'] != null && e['action']!.isNotEmpty)
            .map(
              (e) => {
                'title': e['title'],
                'text': e['action'],
                'icon': _getIcon(e['kind']),
              },
            )
            .toList(),
        isAllGood
            ? const Color.fromARGB(255, 228, 243, 209)
            : const Color.fromARGB(255, 234, 201, 201),
        isAllGood ? Color(0xFFA0C878) : Colors.red[400]!,
        'action',
      );

      addSection(
        'WARNING',
        _insightList
            .where((e) => e['warning'] != null && e['warning']!.isNotEmpty)
            .map(
              (e) => {
                'title': e['title'],
                'text': e['warning'],
                'icon': _getIcon(e['kind']),
              },
            )
            .toList(),
        isAllGood
            ? const Color.fromARGB(255, 228, 243, 209)
            : const Color.fromARGB(255, 246, 220, 179),
        isAllGood ? Color(0xFFA0C878) : Colors.orange[400]!,
        'warning',
      );

      addSection(
        'RISK',
        _insightList
            .where((e) => e['risk'] != null && e['risk']!.isNotEmpty)
            .map(
              (e) => {
                'title': e['title'],
                'text': e['risk'],
                'icon': _getIcon(e['kind']),
              },
            )
            .toList(),
        isAllGood
            ? const Color.fromARGB(255, 228, 243, 209)
            : const Color.fromARGB(255, 246, 220, 179),
        isAllGood ? Color(0xFFA0C878) : Colors.orange[400]!,
        'risk',
      );

      return sections;
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: h * 0.02),
      padding: EdgeInsets.all(w * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _suggestionsExpanded = !_suggestionsExpanded;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SUGGESTIONS', style: headerStyle),
                const SizedBox(width: 8),
                Icon(
                  _suggestionsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: h * 0.03,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState:
                _suggestionsExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
            firstChild: Column(children: _buildSuggestionSections()),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _setInsights(
    double p,
    double tds,
    double t,
    double h,
    String harvestStatus,
    int daysToHarvest,
  ) {
    final pairs = {'pH': p, 'TDS': tds, 'T': t, 'H': h};

    _insightList.clear();

    pairs.forEach((kind, value) {
      final issue = _calcDetailedStatus(value, kind);
      if (issue != 'OK') {
        _insightList.add({
          'kind': kind,
          'insight': _detailInsight[issue] ?? '',
          'action': _detailAction[issue] ?? '',
          'warning': _detailWarn[issue] ?? '',
          'risk': _detailRisk[issue] ?? '',
          'title': issue,
        });
      }
    });

    if (_insightList.isEmpty) {
      final title = harvestStatus;
      final insight = _detailInsight[title]!;
      final action = _detailAction[title]!;
      final warning = _detailWarn[title]!;
      final risk = _detailRisk[title]!;

      final daysMsg = insight.replaceAll('{days}', '$daysToHarvest');

      _insightList.add({
        'kind': 'Harvest',
        'title': title,
        'insight': daysMsg,
        'action': action,
        'warning': warning,
        'risk': risk,
      });
    }
    setState(() {});
  }

  Widget buildWeightAndSize() {
    return FutureBuilder<Map<String, double>>(
      future: fetchReadingForDate(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || snap.data == null) {
          return SizedBox.shrink();
        }

        final selDate = widget.selectedDate ?? DateTime.now();
        int dayIndex = selDate.difference(widget.datePlanted).inDays;
        if (dayIndex < 0) dayIndex = 0;
        final plantAge = dayIndex + 1;

        final r = snap.data!;
        final temp = r['temperature']!;
        final ph = r['ph']!;
        final tds = r['tds']!;
        final humid = r['humidity']!;
        String status;
        if (22 <= temp &&
            temp <= 26 &&
            5.5 <= ph &&
            ph <= 6.5 &&
            560 <= tds &&
            tds <= 840 &&
            50 <= humid &&
            humid <= 80) {
          status = 'Healthy';
        } else if (18 <= temp &&
            temp <= 30 &&
            5.5 <= ph &&
            ph <= 6.6 &&
            500 <= tds &&
            tds <= 880 &&
            40 <= humid &&
            humid <= 90) {
          status = 'Normal';
        } else if (15 <= temp &&
            temp <= 32 &&
            5.0 <= ph &&
            ph <= 7.5 &&
            400 <= tds &&
            tds <= 900 &&
            30 <= humid &&
            humid <= 95) {
          status = 'Abnormal';
        } else {
          status = 'Critical';
        }

        String growthImage;
        if (plantAge < 4)
          growthImage = 'assets/growthstage1.png';
        else if (plantAge < 15)
          growthImage = 'assets/growthstage2.png';
        else if (plantAge < 36)
          growthImage = 'assets/growthstage3.png';
        else
          growthImage = 'assets/growthstage4.png';

        final fullIncW = List<double>.generate(45, (i) {
          final d = i + 1;
          if (d <= 10)
            return 2 + (d - 1) * (13 / 9);
          else if (d <= 30)
            return 25;
          else
            return 25 - (d - 31) * (20 / 14);
        });
        final fullIncL = List<double>.generate(45, (i) {
          final d = i + 1;
          if (d <= 10)
            return 0.5 + (d - 1) * (1.5 / 9);
          else if (d <= 30)
            return 1.0;
          else
            return 1.0 - (d - 31) * (0.8 / 14);
        });
        final fullSumW = fullIncW.fold<double>(0, (s, v) => s + v);
        final fullSumL = fullIncL.fold<double>(0, (s, v) => s + v);

        final wScale = 300 / fullSumW;
        final lScale = 30 / fullSumL;

        final partialW = fullIncW.take(plantAge).toList();
        final partialL = fullIncL.take(plantAge).toList();
        final factor =
            {
              'Healthy': 1.0,
              'Normal': 0.8,
              'Abnormal': 0.5,
              'Critical': 0.2,
            }[status]!;

        final cumW = partialW.fold<double>(
          0,
          (sum, v) => sum + v * wScale * factor,
        );
        final cumL = partialL.fold<double>(
          0,
          (sum, v) => sum + v * lScale * factor,
        );

        final fmt = DateFormat.yMMMd();
        final item = Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  Container(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 18, color: Colors.white),
                        children: [
                          TextSpan(text: 'Weight: '),
                          TextSpan(
                            text: '${cumW.toStringAsFixed(1)} g',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  Container(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 18, color: Colors.white),
                        children: [
                          TextSpan(text: 'Leaf Size: '),
                          TextSpan(
                            text: '${cumL.toStringAsFixed(1)} cm',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Image.asset(
              growthImage,
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
          ],
        );

        final h = MediaQuery.of(context).size.height;
        final w = MediaQuery.of(context).size.width;
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(top: h * 0.02),
          padding: EdgeInsets.all(w * 0.05),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap:
                    () => setState(
                      () => _weightleafExpanded = !_weightleafExpanded,
                    ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'WEIGHT & LEAF SIZE',
                      style: TextStyle(
                        fontSize: h * 0.02,
                        fontFamily: 'Inter_Bold',
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _weightleafExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: h * 0.03,
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState:
                    _weightleafExpanded
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                firstChild: item,
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> formatDates(List<FlSpot> spots) {
    final startDate = widget.datePlanted;
    return List.generate(spots.length, (i) {
      final date = startDate.add(Duration(days: i));
      return DateFormat('M/d').format(date);
    });
  }

  Widget buildChart({
    required String title,
    required List<FlSpot> spots,
    required double maxY,
    required List<String> dateLabels,
    required double screenWidth,
    required double screenHeight,
    double? interval,
    required String paramType,
  }) {
    final barGroups = convertToBarGroups(spots, paramType);
    final barWidth = 40.0;
    final chartWidth = barGroups.length * barWidth;

    final startDate = widget.datePlanted;
    final selectedDate = widget.selectedDate ?? DateTime.now();
    final selectedIndex = selectedDate.difference(startDate).inDays;

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.01),
      padding: EdgeInsets.all(screenWidth * 0.03),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromARGB(255, 195, 224, 166),
            Color(0xFFF8FBE3),
            Color(0xFFFFFFEC),
          ],
          stops: [0.0, 0.15, 1.0],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: screenHeight * 0.018,
              fontFamily: 'Inter_Bold',
              color: Colors.black87,
            ),
          ),
          SizedBox(height: screenHeight * 0.02),
          SizedBox(
            height: screenHeight * 0.25,
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: List.generate(
                      (maxY / (interval ?? 5)).ceil() + 1,
                      (i) {
                        double yVal = maxY - i * (interval ?? 5);
                        return Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Text(
                              yVal.toInt().toString(),
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartWidth,
                      child: BarChart(
                        BarChartData(
                          maxY: maxY,
                          minY: 0,
                          alignment: BarChartAlignment.spaceAround,
                          barGroups: barGroups,
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (value, meta) {
                                  int index = value.toInt();
                                  if (index >= 0 && index < dateLabels.length) {
                                    final isSelected = index == selectedIndex;
                                    return Text(
                                      dateLabels[index],
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                        color:
                                            isSelected
                                                ? Colors.black
                                                : Colors.grey,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            drawHorizontalLine: true,
                            horizontalInterval: interval ?? 5,
                            getDrawingHorizontalLine: (value) {
                              final normalRanges = getNormalRanges();
                              final range = normalRanges[paramType];

                              Color lineColor = Colors.grey.withOpacity(0.4);

                              if (range != null &&
                                  (value == range[0] || value == range[1])) {
                                lineColor = Colors.green;
                              }

                              return FlLine(color: lineColor, strokeWidth: 1.2);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<double>> getNormalRanges() {
    return {
      'ph': [5.5, 6.6],
      'tds': [500, 880],
      'humidity': [30, 70],
      'temperature': [18, 30],
    };
  }

  Widget buildAllCharts(double screenWidth, double screenHeight) {
    return FutureBuilder<Map<String, List<FlSpot>>>(
      future: fetchChartData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          return const Text('Error fetching readings');
        }

        final dataMap = snapshot.data;
        if (dataMap == null || dataMap.isEmpty) {
          return const SizedBox.shrink();
        }

        final dateLabels = formatDates(dataMap['ph']!);

        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(top: screenHeight * 0.025),
          padding: EdgeInsets.all(screenWidth * 0.05),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _chartsExpanded = !_chartsExpanded;
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 8),
                    Text(
                      'READINGS OVERVIEW',
                      style: TextStyle(
                        fontSize: screenHeight * 0.02,
                        fontFamily: 'Inter_Bold',
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _chartsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: screenHeight * 0.03,
                    ),
                  ],
                ),
              ),

              // Expand/collapse chart content
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState:
                    _chartsExpanded
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    SizedBox(height: screenHeight * 0.015),
                    buildChart(
                      title: 'PH LEVEL',
                      spots: dataMap['ph']!,
                      maxY: 10,
                      dateLabels: dateLabels,
                      screenWidth: screenWidth,
                      screenHeight: screenHeight,
                      interval: 2,
                      paramType: 'ph',
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    buildChart(
                      title: 'TDS (ppm)',
                      spots: dataMap['tds']!,
                      maxY: 1000,
                      dateLabels: dateLabels,
                      screenWidth: screenWidth,
                      screenHeight: screenHeight,
                      interval: 200,
                      paramType: 'tds',
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    buildChart(
                      title: 'TEMPERATURE',
                      spots: dataMap['temperature']!,
                      maxY: 50,
                      dateLabels: dateLabels,
                      screenWidth: screenWidth,
                      screenHeight: screenHeight,
                      interval: 10,
                      paramType: 'temp',
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    buildChart(
                      title: 'HUMIDITY',
                      spots: dataMap['humidity']!,
                      maxY: 100,
                      dateLabels: dateLabels,
                      screenWidth: screenWidth,
                      screenHeight: screenHeight,
                      interval: 20,
                      paramType: 'humidity',
                    ),
                  ],
                ),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  //──────────────────────────────────  ERROR HANDLING  ─────────────────────────────────

  Future<void> checkUserExit() async {
    final prefs = await SharedPreferences.getInstance();
    hasUserExited =
        prefs.getBool(
          'hasUserExited_${widget.selectedDate ?? DateTime.now()}',
        ) ??
        false;
    setState(() {});
  }

  bool get isHarvestDay {
    if (predictedHarvestDay == null) return false;
    return predictedHarvestDay == 0;
  }

  bool hasUserExited = false;

  bool get isDateEditable {
    if (!isManualMode || hasUserExited) return false;

    if (predictedHarvestDay != null && predictedHarvestDay! < 0) return false;

    if (isHarvestDay) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected =
        widget.selectedDate != null
            ? DateTime(
              widget.selectedDate!.year,
              widget.selectedDate!.month,
              widget.selectedDate!.day,
            )
            : today;

    if (selected == today) return true;

    if (selected.isAfter(today)) return false;

    if (latestInputDate != null) {
      final plantingDate = DateTime(2024, 4, 5);
      if (selected.isAfter(plantingDate) &&
          selected.isBefore(latestInputDate!)) {
        return false;
      }
    }

    if (isEditMode) return true;

    final allFieldsFilled =
        _tempC.text.isNotEmpty &&
        _humC.text.isNotEmpty &&
        _tdsC.text.isNotEmpty &&
        _phC.text.isNotEmpty;

    return true;
  }

  bool get canPressUpdate {
    final allFilled =
        _tempC.text.isNotEmpty &&
        _humC.text.isNotEmpty &&
        _tdsC.text.isNotEmpty &&
        _phC.text.isNotEmpty;

    final isPredicting =
        _isPredictingHarvest || _isPredictingNutrient || _predictionPending;

    return !isPredicting && isDateEditable;
  }

  String _ensureDateString(dynamic raw) {
    DateTime dt;
    if (raw is DateTime) {
      dt = raw;
    } else {
      dt = DateTime.parse(raw.toString());
    }
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  //──────────────────────────────────  LOADING AND FETCHING STATES  ─────────────────────────────────

  //────────────────────────  PREDICT HARVEST DAY  ───────────────────────
  Future<int> predictHarvestDay(String batchId) async {
    final selectedDateStr = DateFormat(
      'yyyy-MM-dd',
    ).format(widget.selectedDate ?? DateTime.now());

    final raw = await Supabase.instance.client
        .from('readings')
        .select('date, temperature, humidity, tds, ph')
        .eq('batch_id', batchId)
        .lte('date', selectedDateStr)
        .order('date', ascending: true);

    final rows = (raw as List).cast<Map<String, dynamic>>();

    if (rows.isEmpty) {
      debugPrint(
        '⚠️ No readings found for batch $batchId — skipping harvest prediction.',
      );
      return -1;
    }

    final payload =
        rows
            .map(
              (r) => {
                'date': _ensureDateString(r['date']),
                'temperature': r['temperature'],
                'humidity': r['humidity'],
                'tds': r['tds'],
                'ph': r['ph'],
              },
            )
            .toList();

    try {
      final apiResp = await http.post(
        Uri.parse(
          'https://gcodemodelrailway-production.up.railway.app/predict-harvest',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (apiResp.statusCode != 200) {
        debugPrint('❌ Prediction API failed: ${apiResp.body}');
        return -1;
      }

      final result = jsonDecode(apiResp.body) as Map<String, dynamic>;
      final predicted = result['predicted_harvest_day'];

      if (predicted == null) {
        debugPrint('⚠️ API returned null predicted_harvest_day.');
        return -1;
      }

      return (predicted as num).toInt();
    } catch (e) {
      debugPrint('❌ Error during prediction: $e');
      return -1;
    }
  }

  //────────────────────────  UPDATE NUTRIENT STATUS  ───────────────────────
  Future<void> updateStatusAndAdjustmentInSupabase(
    String batchId,
    String selectedDateStr,
    Map<String, dynamic> results,
  ) async {
    final overallStatus =
        results.values.every((v) => v?['status'] == 'Normal')
            ? 'Normal'
            : 'Out of Range';

    final phAdjustment = results['pH Level']?['adjustment'];
    final tdsAdjustment = results['TDS Value (ppm)']?['adjustment'];

    final temperatureStatus = results['Temperature (°C)']?['status'];
    final humidityStatus = results['Humidity (%)']?['status'];

    final payload = <String, dynamic>{
      'batch_id': batchId,
      'date': selectedDateStr,
      'status': overallStatus,
      'ph_adjustment': phAdjustment,
      'tds_adjustment': tdsAdjustment,
      'temperature_status': temperatureStatus,
      'humidity_status': humidityStatus,
    };

    try {
      final result =
          await Supabase.instance.client
              .from('readings')
              .upsert(payload, onConflict: 'batch_id,date')
              .select();

      debugPrint('Supabase upsert result: $result');
    } catch (e) {
      debugPrint('Supabase upsert threw → $e');
      await _showDialog(title: 'Error', msg: '');
    }
  }

  Future<void> fetchAndUpdateAutoReadings() async {
    final supabase = Supabase.instance.client;
    final date = widget.selectedDate ?? DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final user = supabase.auth.currentUser;

    if (user == null) {
      print('No logged in user');
      return;
    }

    final currentEmail = user.email ?? '';

    final startDateTime = DateTime(date.year, date.month, date.day, 8, 0, 0);
    final startDateTimeStr = DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(startDateTime);

    final response = await supabase
        .from('sensor_logs')
        .select('date, temperature, humidity, tds, ph')
        .eq('date', dateStr)
        .gte('time', startDateTimeStr)
        .eq('email', currentEmail)
        .order('time', ascending: true)
        .limit(10);

    final readings = (response as List<dynamic>?);

    if (readings == null || readings.isEmpty) {
      if (mounted) {
        _showDialog(
          title: 'No readings found.',
          msg: 'Make sure that the Arduino is connected!',
        );
      }
      return;
    }

    double totalTemp = 0, totalHumidity = 0, totalTds = 0, totalPh = 0;
    for (final r in readings) {
      totalTemp += (r['temperature'] ?? 0).toDouble();
      totalHumidity += (r['humidity'] ?? 0).toDouble();
      totalTds += (r['tds'] ?? 0).toDouble();
      totalPh += (r['ph'] ?? 0).toDouble();
    }

    final count = readings.length;
    final finalTemp = totalTemp / count;
    final finalHumidity = totalHumidity / count;
    final finalTds = totalTds / count;
    final finalPh = totalPh / count;

    if (mounted) {
      setState(() {
        _phC.text = finalPh.toStringAsFixed(2);
        _tdsC.text = finalTds.toStringAsFixed(2);
        _tempC.text = finalTemp.toStringAsFixed(2);
        _humC.text = finalHumidity.toStringAsFixed(2);
        _isPredictingHarvest = true;
        _isPredictingNutrient = true;
      });
    }

    await supabase.from('readings').upsert({
      'batch_id': selectedBatchId,
      'batch_number': widget.batchNumber,
      'method': widget.method,
      'date': dateStr,
      'temperature': finalTemp,
      'humidity': finalHumidity,
      'tds': finalTds,
      'ph': finalPh,
      'source': 'auto',
      'predicted_harvest_day': null,
      'days_until_harvest': null,
    }, onConflict: 'batch_id,date');

    String phAdj = '';
    String tdsAdj = '';
    if (finalPh > 6.5) {
      final diff = (finalPh - 6.5).toStringAsFixed(2);
      phAdj = '→ pH is high by $diff: add pH Down.';
    } else if (finalPh < 5.5) {
      final diff = (5.5 - finalPh).toStringAsFixed(2);
      phAdj = '→ pH is low by $diff: add pH Up.';
    }

    if (finalTds < 560) {
      final diff = (560 - finalTds).toStringAsFixed(1);
      tdsAdj = '→ TDS is low by $diff ppm: add nutrients.';
    } else if (finalTds > 840) {
      final diff = (finalTds - 840).toStringAsFixed(1);
      tdsAdj = '→ TDS is high by $diff ppm: add water.';
    }

    final day = await predictHarvestDay(selectedBatchId);
    if (day != -1) {
      final batchAgeDays = date.difference(widget.datePlanted).inDays + 1;
      final daysLeft = (day - batchAgeDays).clamp(0, day);

      await supabase
          .from('readings')
          .update({
            'days_until_harvest': daysLeft,
            'predicted_harvest_day': day,
          })
          .eq('batch_id', selectedBatchId)
          .eq('date', dateStr);

      if (mounted) {
        setState(() {
          predictedHarvestDay = daysLeft;
          _isPredictingHarvest = false;
          _isPredictingNutrient = false;
        });
      }
      final daysSinceSelected = date.difference(widget.datePlanted).inDays;
      final harvestStatus = _computeHarvestStatus(daysSinceSelected, daysLeft);
      _setInsights(
        finalPh,
        finalTds,
        finalTemp,
        finalHumidity,
        harvestStatus,
        daysLeft,
      );
    }

    final recommendationMsg = [
      phAdj,
      tdsAdj,
    ].where((s) => s.isNotEmpty).join('\n');

    final rawKey = '${selectedBatchId}-nutrient-$dateStr';
    final notifId = rawKey.hashCode;

    if (recommendationMsg.isNotEmpty) {
      await NotificationService().cancel(notifId);

      final payloadMap = <String, dynamic>{
        'userId': user.id,
        'batchId': selectedBatchId,
        'method': widget.method,
        'batchNumber': widget.batchNumber,
        'date': dateStr,
        'datePlanted': widget.datePlanted.toIso8601String(),
        'type': 'nutrient',
        'pHAdjustment': phAdj,
        'TDSAdjustment': tdsAdj,
      };

      await NotificationService().scheduleRecommendationNotification(
        id: notifId,
        title:
            'Nutrient Alert for ${widget.method} Batch ${widget.batchNumber}',
        body: recommendationMsg,
        scheduledDate: DateTime.now().add(const Duration(seconds: 1)),
        payloadMap: payloadMap,
      );
    } else {
      await NotificationService().cancel(notifId);

      await Supabase.instance.client
          .from('notifications')
          .delete()
          .eq('id', notifId);
    }
  }

  //────────────────────────  SUBMIT MANUAL  ───────────────────────
  Future<void> submitReadings({
    required String source,
    double? temp,
    double? humidity,
    double? tds,
    double? ph,
  }) async {
    if (source == 'auto') {
      await fetchAndUpdateAutoReadings();
      return;
    }

    if (_tempC.text.isEmpty ||
        _humC.text.isEmpty ||
        _tdsC.text.isEmpty ||
        _phC.text.isEmpty) {
      await showCustomErrorDialog(
        context,
        title: 'Missing Fields',
        message: 'You must input all parameters.',
      );
      return;
    }

    double finalTemp, finalHumidity, finalTds, finalPh;
    try {
      finalTemp = double.parse(_tempC.text);
      finalHumidity = double.parse(_humC.text);
      finalTds = double.parse(_tdsC.text);
      finalPh = double.parse(_phC.text);
    } catch (_) {
      await _showDialog(
        title: 'Invalid Input',
        msg: 'Please enter valid numbers.',
      );
      return;
    }

    if (finalTemp <= 0 || finalHumidity <= 0 || finalTds <= 0 || finalPh <= 0) {
      await showCustomErrorDialog(
        context,
        title: 'Invalid Input',
        message:
            'Temperature, Humidity, TDS, and pH values must be greater than 0.',
      );
      return;
    }

    showPredictionDialog(context);

    setState(() {
      _isPredictingHarvest = true;
      _isPredictingNutrient = true;
      _justPredicted = false;
    });

    try {
      final supabase = Supabase.instance.client;
      final date = widget.selectedDate ?? DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      String phAdj = '';
      String tdsAdj = '';
      if (finalPh > 6.5) {
        final diff = (finalPh - 6.5).toStringAsFixed(2);
        phAdj = '→ pH is high by $diff: add pH Down to lower it.';
      } else if (finalPh < 5.5) {
        final diff = (5.5 - finalPh).toStringAsFixed(2);
        phAdj = '→ pH is low by $diff: add pH Up to increase it.';
      }

      if (finalTds < 560) {
        final diff = (560 - finalTds).toStringAsFixed(1);
        tdsAdj = '→ TDS is low by $diff ppm: add nutrient solution.';
      } else if (finalTds > 840) {
        final diff = (finalTds - 840).toStringAsFixed(1);
        tdsAdj =
            '→ TDS is high by $diff ppm: top-up with fresh water to dilute.';
      }

      await supabase.from('readings').upsert({
        'batch_id': selectedBatchId,
        'batch_number': widget.batchNumber,
        'method': widget.method,
        'date': dateStr,
        'temperature': finalTemp,
        'humidity': finalHumidity,
        'tds': finalTds,
        'ph': finalPh,
        'ph_adjustment': phAdj,
        'tds_adjustment': tdsAdj,
        'source': 'manual',
        'predicted_harvest_day': null,
        'days_until_harvest': null,
      }, onConflict: 'batch_id,date');

      final key = _pendingKey(selectedBatchId, date);
      await _prefs?.setBool(key, true);
      setState(() => _predictionPending = true);

      final rawDay = await predictHarvestDay(selectedBatchId);
      final batchAgeDays = date.difference(widget.datePlanted).inDays + 1;
      final daysLeft = (rawDay - batchAgeDays).clamp(0, rawDay);

      await supabase
          .from('readings')
          .update({
            'days_until_harvest': daysLeft,
            'predicted_harvest_day': rawDay,
          })
          .eq('batch_id', selectedBatchId)
          .eq('date', dateStr);

      await _prefs?.setBool(key, false);

      if (mounted) {
        setState(() {
          _predictionPending = false;
          predictedHarvestDay = daysLeft;
          _justPredicted = true;
          _isPredictingHarvest = false;
          _isPredictingNutrient = false;
        });
      }

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _justPredicted = false;
          _hasUpdated = true;
        });
      }

      final daysSinceSelected = date.difference(widget.datePlanted).inDays + 1;
      final harvestStatus = _computeHarvestStatus(daysSinceSelected, daysLeft);
      print('Days Since Selected: $daysSinceSelected');
      _setInsights(
        finalPh,
        finalTds,
        finalTemp,
        finalHumidity,
        harvestStatus,
        daysLeft,
      );
      print('Harvest Status: $harvestStatus');

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      final userId = user.id;

      final recommendationMsg = [
        phAdj,
        tdsAdj,
      ].where((s) => s.isNotEmpty).join('\n');

      final notifTitle =
          'Nutrient Alert for ${widget.method} Batch ${widget.batchNumber}';
      final notifBody = '$recommendationMsg';
      final payloadMap = <String, dynamic>{
        'userId': user.id,
        'batchId': selectedBatchId,
        'method': widget.method,
        'batchNumber': widget.batchNumber,
        'date': dateStr,
        'datePlanted': widget.datePlanted.toIso8601String(),
        'type': 'nutrient',
      };

      final rawKey = '${selectedBatchId}-nutrient-$dateStr';
      final notifId = rawKey.hashCode;

      if (recommendationMsg.isNotEmpty) {
        await NotificationService().cancel(notifId);
        final payloadMap = <String, dynamic>{
          'userId': user.id,
          'batchId': selectedBatchId,
          'method': widget.method,
          'batchNumber': widget.batchNumber,
          'date': dateStr,
          'datePlanted': widget.datePlanted.toIso8601String(),
          'type': 'nutrient',
          'pHAdjustment': phAdj,
          'TDSAdjustment': tdsAdj,
        };
        await NotificationService().scheduleRecommendationNotification(
          id: notifId,
          title:
              'Nutrient Alert for ${widget.method} Batch ${widget.batchNumber}',
          body: '$recommendationMsg',
          scheduledDate: DateTime.now().add(const Duration(seconds: 1)),
          payloadMap: payloadMap,
        );
      } else {
        await NotificationService().cancel(notifId);

        await Supabase.instance.client
            .from('notifications')
            .delete()
            .eq('id', notifId);
      }
    } catch (e) {
      print('Prediction error: $e');
      if (mounted) {
        await _showDialog(
          title: 'Error',
          msg: 'Error loading predictions. Please try again.',
        );
      }
    } finally {
      Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        setState(() {
          _isPredictingHarvest = false;
          _isPredictingNutrient = false;
        });
      }
    }
  }

  //────────────────────────  LOAD BATCHES  ───────────────────────
  Future<void> loadBatchInfo() async {
    final date = widget.selectedDate ?? DateTime.now();
    final key = _pendingKey(widget.batchId, date);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    final pending = _prefs?.getBool(key) ?? false;
    if (pending) {
      if (mounted) {
        setState(() {
          _predictionPending = true;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final readings =
          await Supabase.instance.client
              .from('readings')
              .select(
                'temperature, humidity, tds, ph, days_until_harvest, ph_adjustment, tds_adjustment, temperature_status, humidity_status',
              )
              .eq('batch_id', widget.batchId)
              .eq('date', dateStr)
              .maybeSingle();

      if (readings != null) {
        _tempC.text = readings['temperature'].toString();
        _humC.text = readings['humidity'].toString();
        _tdsC.text = readings['tds'].toString();
        _phC.text = readings['ph'].toString();
        predictedHarvestDay = (readings['days_until_harvest'] as num?)?.toInt();
        phAdjustment = readings['ph_adjustment'] as String?;
        tdsAdjustment = readings['tds_adjustment'] as String?;
        temperatureStatus = readings['temperature_status'] as String?;
        humidityStatus = readings['humidity_status'] as String?;

        final ph = (readings['ph'] as num).toDouble();
        final tds = (readings['tds'] as num).toDouble();
        final temp = (readings['temperature'] as num).toDouble();
        final hum = (readings['humidity'] as num).toDouble();

        final daysSinceSelected = date.difference(widget.datePlanted).inDays;
        final daysLeft = (readings['days_until_harvest'] as num?)?.toInt() ?? 0;
        final harvestStatus = _computeHarvestStatus(
          daysSinceSelected,
          daysLeft,
        );

        _setInsights(ph, tds, temp, hum, harvestStatus, daysLeft);
        print('Harvest Status: $harvestStatus');

        final latestFromSupabase =
            await Supabase.instance.client
                .from('readings')
                .select('date')
                .eq('batch_id', widget.batchId)
                .order('date', ascending: false)
                .limit(1)
                .maybeSingle();

        if (latestFromSupabase != null) {
          final latestDateStr = latestFromSupabase['date'] as String?;
          final latestDate =
              latestDateStr != null ? DateTime.tryParse(latestDateStr) : null;

          if (latestDate != null &&
              (latestInputDate == null ||
                  latestDate.isAfter(latestInputDate!))) {
            latestInputDate = latestDate;
            await _prefs?.setString(
              'latest_input_date_${widget.batchId}',
              latestDate.toIso8601String(),
            );
            print('✅ Saved latestInputDate from Supabase: $latestInputDate');
          }
        }
      } else {
        final previousReading =
            await Supabase.instance.client
                .from('readings')
                .select(
                  'temperature, humidity, tds, ph, days_until_harvest, ph_adjustment, tds_adjustment, date',
                )
                .eq('batch_id', widget.batchId)
                .lt('date', dateStr)
                .order('date', ascending: false)
                .limit(1)
                .maybeSingle();

        _tempC.clear();
        _humC.clear();
        _tdsC.clear();
        _phC.clear();

        if (previousReading != null) {
          final currentDate = widget.selectedDate ?? DateTime.now();
          final prevReadingDate = DateTime.parse(
            previousReading['date'] as String,
          );
          final prevDaysUntilHarvest =
              (previousReading['days_until_harvest'] as num?)?.toInt() ?? 0;

          final daysBetween = currentDate.difference(prevReadingDate).inDays;
          final calcDay = prevDaysUntilHarvest - daysBetween;
          predictedHarvestDay = calcDay.clamp(-1000, 1000);
        } else {
          predictedHarvestDay = null;
          phAdjustment = null;
          tdsAdjustment = null;
        }
      }

      final latestStr = _prefs?.getString(
        'latest_input_date_${widget.batchId}',
      );
      if (latestStr != null) {
        latestInputDate = DateTime.tryParse(latestStr);
        print('📦 Loaded latestInputDate from prefs: $latestInputDate');
      }

      await _prefs?.setBool(key, false);
      if (mounted) _predictionPending = false;
    } catch (e, stack) {
      print('❌ Error loading readings: $e');
      print(stack);
      _snack('Failed to load readings');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _chartsExpanded = false;

  Future<Map<String, List<FlSpot>>> fetchChartData() async {
    final dateStr = DateFormat(
      'yyyy-MM-dd',
    ).format(widget.selectedDate ?? DateTime.now());

    final response = await Supabase.instance.client
        .from('readings')
        .select('date, ph, tds, temperature, humidity')
        .eq('batch_id', widget.batchId)
        .lte('date', dateStr)
        .order('date', ascending: true);

    final rows = (response as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return {};

    final lastDate = DateTime.parse(rows.last['date']);
    final startDate = widget.datePlanted;

    Map<String, double> phMap = {};
    Map<String, double> tdsMap = {};
    Map<String, double> tempMap = {};
    Map<String, double> humidityMap = {};

    for (var row in rows) {
      final date = row['date'];
      phMap[date] = (row['ph'] ?? 0).toDouble();
      tdsMap[date] = (row['tds'] ?? 0).toDouble();
      tempMap[date] = (row['temperature'] ?? 0).toDouble();
      humidityMap[date] = (row['humidity'] ?? 0).toDouble();
    }

    List<FlSpot> generateSpots(Map<String, double> map) {
      List<FlSpot> spots = [];
      DateTime current = startDate;
      int index = 0;

      while (!current.isAfter(lastDate)) {
        final dateKey = DateFormat('yyyy-MM-dd').format(current);
        final value = map[dateKey] ?? 0.0;
        spots.add(FlSpot(index.toDouble(), value));
        index++;
        current = current.add(Duration(days: 1));
      }

      return spots;
    }

    return {
      'ph': generateSpots(phMap),
      'tds': generateSpots(tdsMap),
      'temperature': generateSpots(tempMap),
      'humidity': generateSpots(humidityMap),
    };
  }

  bool _weightleafExpanded = false;

  Future<Map<String, double>> fetchReadingForDate() async {
    final dateStr = DateFormat(
      'yyyy-MM-dd',
    ).format(widget.selectedDate ?? DateTime.now());

    final response =
        await Supabase.instance.client
            .from('readings')
            .select('ph,tds,temperature,humidity')
            .eq('batch_id', widget.batchId)
            .eq('date', dateStr)
            .single();

    if (response == null) {
      return {'ph': 0, 'tds': 0, 'temperature': 0, 'humidity': 0};
    }
    return {
      'ph': (response['ph'] ?? 0).toDouble(),
      'tds': (response['tds'] ?? 0).toDouble(),
      'temperature': (response['temperature'] ?? 0).toDouble(),
      'humidity': (response['humidity'] ?? 0).toDouble(),
    };
  }

  // ──────────────────── UTILITIES ────────────────────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showDialog({required String title, required String msg}) async {
    if (!mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.all(0),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: Column(
            children: [
              const SizedBox(height: 16),
              const Icon(
                CupertinoIcons.info_circle_fill,
                color: Colors.redAccent,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
          content: Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),

          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white, // <- Text color here
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('OK'),
              ),
            ),
          ],
        );
      },
    );
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

      print('Batch harvested: $response');
      await supabase.from('notifications').delete().eq('batch_id', batchId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch marked as harvested')),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Exception during harvest: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error marking batch as harvested')),
        );
      }
    }
  }

  void _showHarvestConfirmation(String batchId) {
    final screenHeight = MediaQuery.of(context).size.height;
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
                    fontSize: screenHeight * 0.020,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: screenHeight * 0.010),
                Text(
                  'Are you sure you want to mark this batch as harvested? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenHeight * 0.016,
                    color: const Color.fromARGB(255, 85, 85, 85),
                  ),
                ),
                SizedBox(height: screenHeight * 0.024),
                Row(
                  children: [
                    // CANCEL BUTTON
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
                    // CONFIRM BUTTON
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close the dialog first
                          _harvestBatch(batchId); // Then perform the harvest
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

  /*───────────────────────────────────────────────────────────*/
  /*                             UI                            */
  /*───────────────────────────────────────────────────────────*/

  @override
  Widget build(BuildContext context) {
    String formattedDate =
        widget.selectedDate != null
            ? DateFormat('MMM d').format(widget.selectedDate!)
            : DateFormat('MMM d').format(DateTime.now());

    final int day = predictedHarvestDay ?? 0;
    final currentDate = widget.selectedDate ?? DateTime.now();
    final daysSinceSelected = currentDate.difference(widget.datePlanted).inDays;
    final daysUntilHarvest = predictedHarvestDay ?? 0;
    final totalCycle = daysSinceSelected + daysUntilHarvest;
    final harvestProgress =
        totalCycle > 0 ? daysSinceSelected / totalCycle : 0.0;
    final daysSincePlanted = daysSinceSelected + 1;

    final bool isHarvestDayNegative = day != null && day < 0;

    final Color harvestStrokeColor =
        isHarvestDayNegative ? Colors.red : const Color(0xff61A3BA);
    final Color harvestInnerColor =
        isHarvestDayNegative
            ? const Color.fromARGB(255, 238, 130, 139)
            : const Color(0xFF9DD5D8);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final noInput = [
      _tempC.text,
      _phC.text,
      _tdsC.text,
      _humC.text,
    ].every((s) => s.trim().isEmpty);

    final statusInfo = getStatusInfo(
      tempText: _tempC.text,
      phText: _phC.text,
      tdsText: _tdsC.text,
      humidityText: _humC.text,
    );

    final bool predicting = _isPredictingHarvest || _justPredicted;

    final Color statusStroke =
        noInput
            ? const Color(0xFF95B45B)
            : predicting
            ? const Color.fromARGB(255, 164, 189, 132)
            : (statusInfo['strokeColor'] as Color? ?? Colors.grey);

    final Color statusInner =
        noInput || predicting
            ? const Color(0xFFACC38F) // green
            : statusInfo['innerColor'] as Color? ?? Colors.transparent;

    final bool statusLoading = predicting && !noInput;

    final bool tempEmpty = _tempC.text.trim().isEmpty;
    final tempColor =
        tempEmpty
            ? const Color(0xFFACC38F)
            : getStatusColor(
              categorizeParam(
                double.tryParse(_tempC.text) ?? double.nan,
                'temp',
              ),
            );
    final phEmpty = _phC.text.trim().isEmpty;
    final phColor =
        phEmpty
            ? const Color(0xFFACC38F)
            : getStatusColor(
              categorizeParam(double.tryParse(_phC.text) ?? double.nan, 'ph'),
            );

    final tdsEmpty = _tdsC.text.trim().isEmpty;
    final tdsColor =
        tdsEmpty
            ? const Color(0xFFACC38F)
            : getStatusColor(
              categorizeParam(double.tryParse(_tdsC.text) ?? double.nan, 'tds'),
            );

    final humEmpty = _humC.text.trim().isEmpty;
    final humidityColor =
        humEmpty
            ? const Color(0xFFACC38F)
            : getStatusColor(
              categorizeParam(
                double.tryParse(_humC.text) ?? double.nan,
                'humidity',
              ),
            );

    final bool isHarvestOrOverdue =
        predictedHarvestDay != null && predictedHarvestDay! <= 0;

    final bool buttonEnabled = isHarvestOrOverdue || canPressUpdate;

    final String buttonLabel = isHarvestOrOverdue ? 'Harvest' : 'Update';

    Future<void> onButtonPressed() async {
      if (isHarvestOrOverdue) {
        _showHarvestConfirmation(widget.batchId);
      } else {
        // Normal “Update” logic
        if (isManualMode) {
          await submitReadings(source: 'manual');
        } else {
          await submitReadings(source: 'auto');
        }
        if (mounted) {
          setState(() => _hasUpdated = true);
        }
      }
    }

    String growthImage;
    if (daysSincePlanted < 4) {
      growthImage = 'assets/growthstage1.png';
    } else if (daysSincePlanted < 15) {
      growthImage = 'assets/growthstage2.png';
    } else if (daysSincePlanted < 36) {
      growthImage = 'assets/growthstage3.png';
    } else {
      growthImage = 'assets/growthstage4.png';
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Color(0xFFFFFFEC),
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.06,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.02,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.arrow_circle_left_rounded,
                                    color: Color(0xFF667B5E),
                                  ),
                                  iconSize: screenHeight * 0.04,
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Batch ${widget.batchNumber}',
                                    style: TextStyle(
                                      fontFamily: 'Inter_Bold',
                                      fontSize: screenHeight * 0.04,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF667B5E),
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.005),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: screenWidth * 0.04,
                                      vertical: screenHeight * 0.005,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '$daysSincePlanted ${daysSincePlanted == 1 ? 'day' : 'days'}',
                                      style: TextStyle(
                                        fontFamily: 'Inter_Bold',
                                        fontSize: screenHeight * 0.026,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF95B45B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: screenHeight * 0.02),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: Image.asset(
                                      growthImage,
                                      width: double.infinity,
                                      height: screenHeight * 0.3,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  SizedBox(width: screenWidth * 0.01),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        StatusIndicator(
                                          label:
                                              (predictedHarvestDay == 0 ||
                                                      (predictedHarvestDay !=
                                                              null &&
                                                          predictedHarvestDay! <
                                                              0))
                                                  ? ''
                                                  : 'Harvest in',
                                          value:
                                              _isPredictingHarvest
                                                  ? ''
                                                  : (_justPredicted
                                                      ? ''
                                                      : (predictedHarvestDay ==
                                                              0
                                                          ? 'Harvest\nDay!'
                                                          : (predictedHarvestDay !=
                                                                  null
                                                              ? (predictedHarvestDay! <
                                                                      0
                                                                  ? '${-predictedHarvestDay!} days\nlate!'
                                                                  : '$predictedHarvestDay days')
                                                              : ''))),
                                          strokeColor: harvestStrokeColor,
                                          innerColor: harvestInnerColor,
                                          size: screenHeight * 0.14,
                                          progress:
                                              predictedHarvestDay != null
                                                  ? harvestProgress
                                                  : 0.0,
                                          isPredictedValue:
                                              predictedHarvestDay != null,
                                          isLoading: _isPredictingHarvest,
                                          showCheck: _justPredicted,
                                        ),

                                        SizedBox(height: screenHeight * 0.02),
                                        StatusIndicator(
                                          label: 'Status',
                                          value: statusInfo['value'] as String,
                                          strokeColor: statusStroke,
                                          innerColor: statusInner,
                                          size: screenHeight * 0.14,
                                          progress:
                                              predictedHarvestDay != null
                                                  ? harvestProgress
                                                  : 0.0,
                                          isLoading: statusLoading,
                                          showCheck: _justPredicted,
                                          emojiAsset:
                                              statusInfo['emojiAsset']
                                                  as String?,
                                        ),
                                        SizedBox(height: screenHeight * 0.02),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: screenWidth * 0.03,
                                            vertical: screenHeight * 0.006,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade600
                                                .withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            'Plants: ${widget.numOfPlants ?? 'No Input'}',
                                            style: TextStyle(
                                              fontSize: screenWidth * 0.032,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: screenHeight * 0.02),

                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: screenWidth * 0.02,
                                  vertical: screenHeight * 0.01,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                      offset: Offset(0, 0),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: screenHeight * 0.02,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "$formattedDate Readings",
                                            style: TextStyle(
                                              fontSize: screenHeight * 0.020,
                                              fontFamily: "Inter_Bold",
                                              color: const Color.fromARGB(
                                                255,
                                                59,
                                                59,
                                                59,
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: screenHeight * 0.01),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              GestureDetector(
                                                onTap: () async {
                                                  setState(
                                                    () =>
                                                        isManualMode =
                                                            !isManualMode,
                                                  );
                                                  await _saveMode(isManualMode);

                                                  final prefs =
                                                      await SharedPreferences.getInstance();
                                                  if (!isManualMode) {
                                                    final choice = await showDialog<
                                                      int
                                                    >(
                                                      context: context,
                                                      builder:
                                                          (ctx) => AlertDialog(
                                                            backgroundColor:
                                                                Colors.white,
                                                            title: const Text(
                                                              'Fetch interval',
                                                            ),
                                                            content: const Text(
                                                              'How often should we fetch new data?',
                                                            ),
                                                            actions: [
                                                              for (final mins
                                                                  in [
                                                                    1,
                                                                    5,
                                                                    10,
                                                                    15,
                                                                    30,
                                                                  ])
                                                                TextButton(
                                                                  onPressed:
                                                                      () =>
                                                                          Navigator.of(
                                                                            ctx,
                                                                          ).pop(
                                                                            mins,
                                                                          ),
                                                                  child: Text(
                                                                    '$mins minutes',
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                    );

                                                    final interval =
                                                        choice ?? 15;
                                                    await prefs
                                                      ..setString(
                                                        'auto_batch_id',
                                                        widget.batchId,
                                                      )
                                                      ..setString(
                                                        'auto_user_email',
                                                        Supabase
                                                                .instance
                                                                .client
                                                                .auth
                                                                .currentUser
                                                                ?.email ??
                                                            '',
                                                      )
                                                      ..setString(
                                                        'auto_start_date',
                                                        DateFormat(
                                                          'yyyy-MM-dd',
                                                        ).format(
                                                          widget.datePlanted,
                                                        ),
                                                      )
                                                      ..setInt(
                                                        'auto_fetch_interval',
                                                        interval,
                                                      );

                                                    await AutoBatchScheduler.configure(
                                                      intervalMinutes: interval,
                                                    );
                                                    await AutoBatchScheduler.start();
                                                  } else {
                                                    await prefs
                                                      ..remove('auto_batch_id')
                                                      ..remove(
                                                        'auto_user_email',
                                                      )
                                                      ..remove(
                                                        'auto_start_date',
                                                      )
                                                      ..remove(
                                                        'auto_fetch_interval',
                                                      );
                                                    await AutoBatchScheduler.stop();
                                                  }
                                                },

                                                child: Container(
                                                  width: 130,
                                                  height: 36,
                                                  padding: EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          30,
                                                        ),
                                                    color: Colors.grey[300],
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: AnimatedContainer(
                                                          duration: Duration(
                                                            milliseconds: 250,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                isManualMode
                                                                    ? Colors
                                                                        .black
                                                                    : Colors
                                                                        .transparent,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  25,
                                                                ),
                                                          ),
                                                          alignment:
                                                              Alignment.center,
                                                          child: Text(
                                                            'Manual',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  screenWidth *
                                                                  0.036,
                                                              color:
                                                                  isManualMode
                                                                      ? Colors
                                                                          .white
                                                                      : Colors
                                                                          .grey[600],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: AnimatedContainer(
                                                          duration: Duration(
                                                            milliseconds: 250,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                !isManualMode
                                                                    ? Colors
                                                                        .black
                                                                    : Colors
                                                                        .transparent,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  25,
                                                                ),
                                                          ),
                                                          alignment:
                                                              Alignment.center,
                                                          child: Text(
                                                            'Auto',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  screenWidth *
                                                                  0.036,
                                                              color:
                                                                  !isManualMode
                                                                      ? Colors
                                                                          .white
                                                                      : Colors
                                                                          .grey[600],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: screenHeight * 0.01),
                                    Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _buildInfoBox(
                                              'pH Level',
                                              _phC,
                                              isDateEditable,
                                              screenWidth,
                                              screenHeight,
                                              phColor,
                                            ),
                                            _buildInfoBox(
                                              'TDS (ppm)',
                                              _tdsC,
                                              isDateEditable,
                                              screenWidth,
                                              screenHeight,
                                              tdsColor,
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: screenHeight * 0.015),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _buildInfoBox(
                                              'Temp (°C)',
                                              _tempC,
                                              isDateEditable,
                                              screenWidth,
                                              screenHeight,
                                              tempColor,
                                            ),
                                            _buildInfoBox(
                                              'Humidity (%)',
                                              _humC,
                                              isDateEditable,
                                              screenWidth,
                                              screenHeight,
                                              humidityColor,
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: screenHeight * 0.02),
                                      ],
                                    ),

                                    Center(
                                      child: SizedBox(
                                        width: screenWidth * 0.8,
                                        height: screenHeight * 0.056,
                                        child: ElevatedButton(
                                          onPressed:
                                              buttonEnabled
                                                  ? onButtonPressed
                                                  : null,
                                          style: ElevatedButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                          ),
                                          child: Ink(
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFFACC38F),
                                                  Color(0xFF95B45B),
                                                  Color(0xFF779559),
                                                ],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            child: Center(
                                              child: Text(
                                                buttonLabel,
                                                style: TextStyle(
                                                  fontSize: screenWidth * 0.042,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.005),
                              buildWeightAndSize(),
                              SizedBox(height: screenHeight * 0.005),
                              _buildInsightContainer(screenWidth, screenHeight),
                              SizedBox(height: screenHeight * 0.005),
                              buildAllCharts(screenWidth, screenHeight),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFACC38F),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color getStatusColor(String? status) {
  if (status == null || status.trim().isEmpty || status == '...') {
    return const Color(0xFFACC38F);
  }

  if (status == 'Healthy' || status == 'Normal') {
    return const Color(0xFFACC38F);
  } else {
    return Colors.redAccent;
  }
}

// ──────────────────── HELPERS ────────────────────
Widget _buildInfoBox(
  String label,
  TextEditingController controller,
  bool editable,
  double w,
  double h,
  Color backgroundColor,
) {
  return Container(
    width: w * 0.36,
    height: h * 0.1,
    padding: EdgeInsets.all(w * 0.02),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(25),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: w * 0.036,
            fontFamily: 'Inter_Bold',
            color: Colors.white,
          ),
        ),
        TextField(
          controller: controller,
          readOnly: !editable,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: w * 0.076,
            color: Colors.white,
            fontFamily: 'Inter_Bold',
          ),
          cursorColor: editable ? Colors.white : Colors.transparent,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ),
  );
}
