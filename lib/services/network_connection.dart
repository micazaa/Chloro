import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

class NetworkController extends GetxController {
  final Connectivity _connectivity = Connectivity();

  /// true when there's NO internet
  final RxBool isOffline = false.obs;

  /// true while checking connectivity
  final RxBool isChecking = false.obs;

  @override
  void onInit() {
    super.onInit();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    checkConnectivity();
  }

  void checkConnectivity() async {
    isChecking.value = true;
    final start = DateTime.now();
    final result = await _connectivity.checkConnectivity();
    final elapsed = DateTime.now().difference(start);
    if (elapsed < const Duration(milliseconds: 10)) {
      await Future.delayed(const Duration(milliseconds: 10) - elapsed);
    }
    await _updateConnectionStatus(result);
    isChecking.value = false;
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    if (result == ConnectivityResult.none) {
      isOffline.value = true;
    } else {
      // verify actual Internet
      final hasInternet = await _checkInternetViaHttp(
        timeout: const Duration(seconds: 2),
      );
      isOffline.value = !hasInternet;
    }
  }

  Future<bool> _checkInternetViaHttp({required Duration timeout}) async {
    try {
      final uri = Uri.parse('https://www.gstatic.com/generate_204');
      final request = await HttpClient().getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      return response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }
}
