import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final Connectivity _connectivity = Connectivity();
  late final StreamSubscription<ConnectivityResult> _sub;

  bool _minimumElapsed = false;
  bool _isOffline = false;
  Flushbar<void>? _bottomFlushbar;

  @override
  void initState() {
    super.initState();

    _connectivity.checkConnectivity().then((r) {
      if (!mounted) return;
      setState(() => _isOffline = (r == ConnectivityResult.none));
    });

    _sub = _connectivity.onConnectivityChanged.listen((r) {
      final nowOffline = r == ConnectivityResult.none;
      if (nowOffline != _isOffline) {
        setState(() => _isOffline = nowOffline);
      }
      if (_minimumElapsed && !_isOffline) {
        _dismissBottomBanner();
        _sub.cancel();
        if (mounted) Get.offAllNamed('/login');
      }
    });

    Future.delayed(const Duration(seconds: 5)).then((_) async {
      if (!mounted) return;
      setState(() => _minimumElapsed = true);

      final result = await _connectivity.checkConnectivity();
      if (result != ConnectivityResult.none) {
        await _handleSession();
      } else {
        _showBottomBannerNotification();
      }
    });
  }

  Future<void> _handleSession() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // User is logged in, just go to home
      Get.offAllNamed('/home');
    } else {
      // No session, go to login
      Get.offAllNamed('/login');
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _dismissBottomBanner();
    super.dispose();
  }

  void _showBottomBannerNotification() {
    if (_bottomFlushbar != null) return;

    _bottomFlushbar = Flushbar<void>(
        messageText: const Text(
          'No internet connection',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        duration: const Duration(days: 1),
        backgroundColor: const Color.fromARGB(255, 213, 90, 90),
        margin: const EdgeInsets.all(12),
        borderRadius: BorderRadius.circular(12),
        flushbarPosition: FlushbarPosition.BOTTOM,
        animationDuration: const Duration(milliseconds: 300),
        icon: const Icon(Icons.wifi_off, color: Colors.white),
      )
      ..show(context).then((_) {
        _bottomFlushbar = null;
      });
  }

  void _dismissBottomBanner() {
    _bottomFlushbar?.dismiss();
    _bottomFlushbar = null;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFEC),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback:
                  (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFF95B45B),
                      Color.fromARGB(255, 124, 190, 194),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
              child: LoadingAnimationWidget.hexagonDots(
                color: Colors.white,
                size: 100,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Chloro",
              style: TextStyle(
                fontSize: screenWidth * 0.175,
                fontFamily: 'Lecker',
                color: const Color(0xFF95B45B),
              ),
            ),
            Text(
              "Manage your hydroponic lettuce!",
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                fontFamily: 'Inter_Bold',
                color: const Color(0xFF95B45B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
