import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/network_connection.dart';

class OfflineBanner extends StatelessWidget {
  final VoidCallback onTryAgain;

  const OfflineBanner({Key? key, required this.onTryAgain}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final NetworkController networkController = Get.find();

    return Obx(() {
      if (networkController.isChecking.value) {
        // Show loading indicator while checking
        return SizedBox(
          height: screenHeight * 0.2,
          child: Center(child: CircularProgressIndicator()),
        );
      }

      // Otherwise show offline message and Try Again button
      return IgnorePointer(
        ignoring: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/no_internet.png',
              width: screenHeight * 0.080,
              height: screenHeight * 0.080,
              fit: BoxFit.contain,
            ),
            SizedBox(height: screenHeight * 0.01),
            Text(
              'You\'re offline',
              style: TextStyle(
                fontSize: screenHeight * 0.018,
                fontFamily: 'Inter_Bold',
                color: Colors.black87,
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            SizedBox(
              width: screenWidth * 0.6,
              child: Text(
                'Please check your network connection and try again.',
                style: TextStyle(
                  fontSize: screenHeight * 0.016,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: screenHeight * 0.015),
            ElevatedButton(
              onPressed: onTryAgain,
              child: Text(
                'Try again',
                style: TextStyle(
                  fontSize: screenHeight * 0.018,
                  fontFamily: 'Inter_Bold',
                  color: Colors.white,
                ),
              ),
              style: ButtonStyle(
                elevation: MaterialStateProperty.all(0),
                backgroundColor: MaterialStateProperty.resolveWith<Color>((
                  states,
                ) {
                  if (states.contains(MaterialState.pressed)) {
                    return const Color(0xFF6CA3A6);
                  }
                  return const Color(0xFF9DD5D8);
                }),
                padding: MaterialStateProperty.all(
                  EdgeInsets.symmetric(
                    horizontal: screenHeight * 0.025,
                    vertical: screenHeight * 0.01,
                  ),
                ),
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
