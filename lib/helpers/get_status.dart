import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

List<BarChartGroupData> convertToBarGroups(List<FlSpot> spots, String type) {
  return spots.map((spot) {
    final value = spot.y;
    final status = categorizeParam(value, type);

    final barColor =
        (status == 'Healthy' || status == 'Normal')
            ? Color(0xFFACC38F)
            : Colors.red[400]!;

    return BarChartGroupData(
      x: spot.x.toInt(),
      barRods: [
        BarChartRodData(
          toY: value,
          color: barColor,
          width: 25,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }).toList();
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

Future<bool> hasMissingDays(
  String batchId,
  DateTime datePlanted,
  DateTime currentDate,
) async {
  final response = await Supabase.instance.client
      .from('readings')
      .select('date')
      .eq('batch_id', batchId);

  final existing =
      (response as List).map((e) => _ensureDateString(e['date'])).toSet();

  for (
    var d = datePlanted;
    d.isBefore(currentDate);
    d = d.add(const Duration(days: 1))
  ) {
    if (!existing.contains(DateFormat('yyyy-MM-dd').format(d))) {
      return true;
    }
  }
  return false;
}

Future<void> showCustomErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.error_outline,
  Color iconColor = Colors.red,
  String buttonText = 'OK',
  VoidCallback? onPressed,
}) {
  return showDialog(
    context: context,
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
              Icon(icon, size: 40, color: iconColor),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color.fromARGB(255, 101, 101, 101),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPressed ?? () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(buttonText),
                ),
              ),
            ],
          ),
        ),
  );
}

Map<String, dynamic> getStatusInfo({
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

  if (22 <= temp && temp <= 26) {
    statuses.add('Healthy');
  } else if (18 <= temp && temp <= 30) {
    statuses.add('Normal');
  } else if (15 <= temp && temp <= 32) {
    statuses.add('Abnormal');
  } else {
    statuses.add('Critical');
  }

  if (5.5 <= ph && ph <= 6.5) {
    statuses.add('Healthy');
  } else if (5.5 <= ph && ph <= 6.6) {
    statuses.add('Normal');
  } else if (5.0 <= ph && ph <= 7.5) {
    statuses.add('Abnormal');
  } else {
    statuses.add('Critical');
  }

  if (560 <= tds && tds <= 840) {
    statuses.add('Healthy');
  } else if (500 <= tds && tds <= 880) {
    statuses.add('Normal');
  } else if (400 <= tds && tds <= 900) {
    statuses.add('Abnormal');
  } else {
    statuses.add('Critical');
  }

  if (50 <= humidity && humidity <= 80) {
    statuses.add('Healthy');
  } else if (40 <= humidity && humidity <= 90) {
    statuses.add('Normal');
  } else if (30 <= humidity && humidity <= 95) {
    statuses.add('Abnormal');
  } else {
    statuses.add('Critical');
  }

  final counts = <String, int>{};
  for (var s in statuses) {
    counts[s] = (counts[s] ?? 0) + 1;
  }

  String value;
  String asset;
  Color stroke;

  if ((counts['Critical'] ?? 0) == 4) {
    value = 'Uncertain';
    asset = 'assets/1.png';
    stroke = const Color(0xFFFF6666);
  } else if ((counts['Critical'] ?? 0) > 0) {
    value = 'Critical';
    asset = 'assets/2.png';
    stroke = const Color.fromARGB(255, 224, 139, 105);
  } else if ((counts['Healthy'] ?? 0) == 4) {
    value = 'Healthy';
    asset = 'assets/5.png';
    stroke = const Color(0xFF95B45B);
  } else if ((counts['Abnormal'] ?? 0) >= 3) {
    value = 'Abnormal';
    asset = 'assets/3.png';
    stroke = const Color.fromARGB(255, 255, 218, 108);
  } else {
    value = 'Normal';
    asset = 'assets/4.png';
    stroke = const Color.fromARGB(255, 255, 218, 108);
  }

  return {
    'label': 'Status',
    'value': value,
    'strokeColor': stroke,
    'innerColor': Colors.transparent,
    'emojiAsset': asset,
  };
}

String categorizeParam(double value, String type) {
  switch (type) {
    case 'temp':
      if (22 <= value && value <= 26) return 'Healthy';
      if (15 <= value && value <= 30) return 'Normal';
      if (15 > value && value > 30) return 'Abnormal';
      return 'Critical';
    case 'ph':
      if (5.5 <= value && value <= 6.5) return 'Healthy';
      if (5.5 <= value && value <= 6.6) return 'Normal';
      if (5.0 <= value && value <= 7.5) return 'Abnormal';
      return 'Critical';
    case 'tds':
      if (560 <= value && value <= 840) return 'Healthy';
      if (500 <= value && value <= 880) return 'Normal';
      if (400 <= value && value <= 900) return 'Abnormal';
      return 'Critical';
    case 'humidity':
      if (50 <= value && value <= 80) return 'Healthy';
      if (40 <= value && value <= 90) return 'Normal';
      if (30 <= value && value <= 95) return 'Abnormal';
      return 'Critical';
    default:
      return 'Normal';
  }
}
