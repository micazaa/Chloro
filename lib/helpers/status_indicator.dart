import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class StatusIndicator extends StatelessWidget {
  final String label;
  final String value;
  final Color strokeColor;
  final Color innerColor;
  final double size;
  final double? progress;
  final bool isPredictedValue;
  final bool phAbnormal;
  final bool tdsAbnormal;
  final String? emojiAsset;
  final bool isLoading;
  final bool showCheck;

  const StatusIndicator({
    Key? key,
    required this.label,
    required this.value,
    required this.strokeColor,
    required this.innerColor,
    required this.size,
    this.progress,
    this.isPredictedValue = false,
    this.phAbnormal = false,
    this.tdsAbnormal = false,
    this.emojiAsset,
    this.isLoading = false,
    this.showCheck = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget centerContent;
    if (showCheck) {
      // 1️⃣ Show check icon
      centerContent = Icon(
        Icons.check_circle_rounded,
        size: size * 0.4,
        color: Colors.white,
      );
    } else if (isLoading) {
      // 2️⃣ Show waveDots while predicting
      centerContent = LoadingAnimationWidget.waveDots(
        color: Colors.white,
        size: size * 0.3,
      );
    } else if (label.isEmpty && value.isNotEmpty) {
      centerContent = Center(
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size * 0.16,
            fontFamily: 'Inter_Bold',
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 0.9,
          ),
        ),
      );
    } else if (emojiAsset != null) {
      centerContent = Container(
        width: size * 0.75,
        height: size * 0.75,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: ClipOval(child: Image.asset(emojiAsset!, fit: BoxFit.fill)),
      );
    } else {
      centerContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              style: TextStyle(fontSize: size * 0.1, color: Colors.white),
            ),
          Text(
            value.isEmpty ? '...' : value,
            style: TextStyle(
              fontSize: isPredictedValue ? size * 0.20 : size * 0.1,
              fontFamily: 'Inter_Bold',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: 1,
                strokeWidth: size * 0.06,
                color: Colors.grey.shade300,
              ),
            ),
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: isLoading ? 0.0 : (progress ?? 0.0),
                strokeWidth: size * 0.06,
                color: strokeColor,
              ),
            ),
            Container(
              width: size * 0.84,
              height: size * 0.84,
              decoration: BoxDecoration(
                color: innerColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: centerContent,
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showPredictionDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(blurRadius: 8, color: Colors.black26),
                ],
              ),
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Predicting…',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'Inter',
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}
