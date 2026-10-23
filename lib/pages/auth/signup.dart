import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:another_flushbar/flushbar.dart';
import 'dart:io';

import 'login.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  bool isChecked = false;
  bool isLoading = false;
  final _fullnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _fullnameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _fullnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final fullname = _fullnameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    setState(() {
      _fullnameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    final emailRegex = RegExp(
      r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
    );

    bool isValid = true;

    if (fullname.isEmpty) {
      _fullnameError = "Please enter your name";
      isValid = false;
    }

    if (!emailRegex.hasMatch(email)) {
      _emailError = "Please enter a valid email address";
      isValid = false;
    }

    if (password.isEmpty) {
      _passwordError = "Please enter a password";
      isValid = false;
    } else if (password.length < 6) {
      _passwordError = "Password must be at least 6 characters";
      isValid = false;
    }

    if (confirmPassword.isEmpty) {
      _confirmPasswordError = "Please confirm your password";
      isValid = false;
    } else if (password != confirmPassword) {
      _confirmPasswordError = "Passwords do not match";
      isValid = false;
    }

    if (!isValid) {
      setState(() {});
      return;
    }

    void showErrorSnackBar(String message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    try {
      setState(() => isLoading = true);

      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullname, 'email': email},
      );

      setState(() => isLoading = false);

      if (res.user != null) {
        Flushbar(
          message: "Account Created Successfully",
          messageSize: 16,
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
          flushbarPosition: FlushbarPosition.BOTTOM,
          margin: const EdgeInsets.all(12),
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.check_circle, color: Colors.white),
        ).show(context);

        Navigator.pushReplacement(
          context,
          Platform.isIOS
              ? CupertinoPageRoute(builder: (_) => const LogIn())
              : MaterialPageRoute(builder: (_) => const LogIn()),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);

      final err = e.toString().toLowerCase();

      if (err.contains("user") && err.contains("already")) {
        _emailError = "Email already in use";
      } else if (err.contains("password") && err.contains("6 characters")) {
        _passwordError = "Password must be at least 6 characters";
      } else if (err.contains("invalid email")) {
        _emailError = "Invalid email address";
      } else if (err.contains("network")) {
        showErrorSnackBar("Network error. Please check your connection.");
      } else {
        showErrorSnackBar("Something went wrong. Please try again.");
      }

      setState(() {});
    }
  }

  Widget _buildLabeledTextField(
    BuildContext context,
    String labelText,
    IconData icon,
    TextEditingController controller, {
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? toggleVisibility,
    String? errorText,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: screenWidth * 0.04),
          child: Text(
            labelText,
            style: TextStyle(
              fontSize: screenHeight * 0.016,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF667B5E),
            ),
          ),
        ),
        SizedBox(height: screenHeight * 0.004),

        TextField(
          controller: controller,
          obscureText: isPassword && !isVisible,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: screenWidth * 0.05),
            suffixIcon:
                isPassword
                    ? IconButton(
                      icon: Icon(
                        isVisible ? Icons.visibility : Icons.visibility_off,
                        size: screenWidth * 0.04,
                        color: Colors.grey,
                      ),
                      onPressed: toggleVisibility,
                    )
                    : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(
              vertical: screenHeight * 0.016,
              horizontal: screenWidth * 0.06,
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

        SizedBox(height: screenHeight * 0.015),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFFFFEC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;
            final screenHeight = MediaQuery.of(context).size.height;
            final screenWidth = MediaQuery.of(context).size.width;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.07,
                    vertical: h * 0.04,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Register",
                          style: TextStyle(
                            fontSize: screenHeight * 0.034,
                            fontFamily: 'Inter_Bold',
                            color: Color(0xFF95B45B),
                          ),
                        ),
                        Text(
                          "Create a new account!",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: screenHeight * 0.014,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.05),
                        _buildLabeledTextField(
                          context,
                          "Username",
                          Icons.person_outline,
                          _fullnameController,
                          errorText: _fullnameError,
                        ),

                        _buildLabeledTextField(
                          context,
                          "Email",
                          Icons.email_outlined,
                          _emailController,
                          errorText: _emailError,
                        ),
                        _buildLabeledTextField(
                          context,
                          "Password",
                          Icons.lock,
                          _passwordController,
                          isPassword: true,
                          isVisible: _showPassword,
                          toggleVisibility: () {
                            setState(() {
                              _showPassword = !_showPassword;
                            });
                          },
                          errorText: _passwordError,
                        ),

                        _buildLabeledTextField(
                          context,
                          "Confirm Password",
                          Icons.lock_outline,
                          _confirmPasswordController,
                          isPassword: true,
                          isVisible: _showConfirmPassword,
                          toggleVisibility: () {
                            setState(() {
                              _showConfirmPassword = !_showConfirmPassword;
                            });
                          },
                          errorText: _confirmPasswordError,
                        ),

                        SizedBox(height: h * 0.04),

                        SizedBox(
                          width: double.infinity,
                          height: screenHeight * 0.056,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _signUp,
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
                                          "Register",
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

                        Padding(
                          padding: EdgeInsets.only(top: screenHeight * 0.08),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Already have an account? ",
                                style: TextStyle(
                                  fontSize: screenHeight * 0.016,
                                  color: Color(0xFF667B5E),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    Platform.isIOS
                                        ? CupertinoPageRoute(
                                          builder: (_) => const LogIn(),
                                        )
                                        : MaterialPageRoute(
                                          builder: (_) => const LogIn(),
                                        ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  "Log In",
                                  style: TextStyle(
                                    fontSize: screenHeight * 0.016,
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
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
