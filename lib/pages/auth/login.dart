import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

import 'signup.dart';
import '../home/home_screen.dart';
import '../../services/network_connection.dart';
import '../../helpers/offline_banner.dart';

class LogIn extends StatefulWidget {
  const LogIn({super.key});

  @override
  State<LogIn> createState() => _LogInState();
}

class _LogInState extends State<LogIn> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final NetworkController _networkController = Get.put(NetworkController());

  String? _emailError;
  String? _passwordError;
  bool isLoading = false;
  bool _isPasswordVisible = false;

  // Inside your LogIn widget class
  // Modified sendPasswordResetEmail to not require context param (you have it)
  // In your LogIn widget class
  // Deep link listener setup — call this once e.g. in initState of your main widget or login screen

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    bool isValid = true;

    if (!emailRegex.hasMatch(email)) {
      _emailError = "Please enter a valid email address";
      isValid = false;
    }
    if (password.isEmpty) {
      _passwordError = "Please enter your password";
      isValid = false;
    }
    if (!isValid) {
      setState(() {});
      return;
    }

    setState(() => isLoading = true);

    try {
      // Step 1: Check if email exists in `profiles` table (adjust table name as needed)
      final response =
          await Supabase.instance.client
              .from('profiles')
              .select('email')
              .eq('email', email)
              .maybeSingle();

      if (response == null || response.isEmpty) {
        setState(() {
          _emailError = "This email is not registered.";
          isLoading = false;
        });
        return;
      }

      // Step 2: Attempt login
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        Platform.isIOS
            ? CupertinoPageRoute(builder: (_) => const HomeScreen())
            : MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      final err = e.toString().toLowerCase();
      print("Login error: $e");

      setState(() {
        if (err.contains("invalid login credentials") ||
            err.contains("wrong password")) {
          _passwordError = "Incorrect password.";
        } else if (err.contains("user not found") || err.contains("no user")) {
          _emailError = "This email is not registered.";
        } else if (err.contains("failed host lookup") ||
            err.contains("socketexception") ||
            err.contains("timeout")) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Network error. Please check your connection."),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Login failed: ${e.toString()}"),
              backgroundColor: Colors.red,
            ),
          );
        }
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final NetworkController _net = Get.find();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFFFFEC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final size = MediaQuery.of(context).size;
            final width = size.width;
            final height = size.height;

            // ✨ Scale text and padding based on screen width
            double baseWidth = 375; // reference iPhone 11 width
            double scale = width / baseWidth;
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ─── Logo Section ───────────────────────────
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: h * 0.075,
                      ), // Adjust padding as needed
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Chloro",
                              style: TextStyle(
                                fontSize: scale * 90,
                                fontFamily: 'Lecker',
                                color: const Color(0xFF95B45B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: scale * 0.005),

                    // ─── Form Section ───────────────────────────
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Welcome Back!",
                            style: TextStyle(
                              fontSize: scale * 32,
                              fontFamily: 'Inter_Bold',
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF95B45B),
                            ),
                          ),
                          Text(
                            "Login back to your account!",
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: scale * 12,
                            ),
                          ),
                          SizedBox(height: scale * 24),

                          _buildTextField(
                            context,
                            Icons.person,
                            "Enter you email",
                            controller: _emailController,
                            errorText: _emailError,
                          ),
                          SizedBox(height: scale * 16),

                          _buildTextField(
                            context,
                            Icons.lock,
                            'Enter your password',
                            controller: _passwordController,
                            isPassword: true,
                            isVisible: _isPasswordVisible,
                            toggleVisibility: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                            errorText: _passwordError,
                          ),
                          SizedBox(height: scale * 16),

                          SizedBox(
                            width: double.infinity,
                            height: height * 0.056,
                            child: ElevatedButton(
                              onPressed: isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: EdgeInsets.zero,
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
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Center(
                                  child:
                                      isLoading
                                          ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                          : Text(
                                            "Login",
                                            style: TextStyle(
                                              fontSize: scale * 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                ),
                              ),
                            ),
                          ),

                          /*Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  isLoading ? null : sendPasswordResetEmail,
                              child: Text(
                                "Forgot Password?",
                                style: TextStyle(
                                  fontSize: screenHeight * 0.016,
                                  color: const Color(0xFF667B5E),
                                ),
                              ),
                            ),
                          ),*/
                        ],
                      ),
                    ),
                    SizedBox(height: scale * 80),

                    // ─── Footer Section ─────────────────────────
                    Padding(
                      padding: EdgeInsets.only(top: h * 0.03),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              fontSize: scale * 14,
                              color: Color(0xFF667B5E),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                Platform.isIOS
                                    ? CupertinoPageRoute(
                                      builder: (_) => const SignUp(),
                                    )
                                    : MaterialPageRoute(
                                      builder: (_) => const SignUp(),
                                    ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              "Create an Account",
                              style: TextStyle(
                                fontSize: scale * 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context,
    IconData icon,
    String hintText, {
    required TextEditingController controller,
    String? errorText,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? toggleVisibility,
  }) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    // ✨ Scale text and padding based on screen width
    double baseWidth = 375; // reference iPhone 11 width
    double scale = width / baseWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: isPassword && !isVisible,
          decoration: InputDecoration(
            prefixIcon: Icon(
              icon,
              size: scale * 18, // adjust this to your desired size
              color: Colors.grey[700], // optional: change color
            ),
            suffixIcon:
                isPassword
                    ? IconButton(
                      icon: Icon(
                        isVisible ? Icons.visibility : Icons.visibility_off,
                        size: scale * 18,
                        color: Colors.grey,
                      ),
                      onPressed: toggleVisibility,
                    )
                    : null,
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: scale * 14,
              color: Colors.grey.withOpacity(0.6),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(
              vertical: scale * 14,
              horizontal: scale * 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(
                color: errorText != null ? Colors.red : Colors.grey.shade300,
                width: 2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(
                color: errorText != null ? Colors.red : Colors.grey.shade400,
                width: 2,
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 4.0),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
