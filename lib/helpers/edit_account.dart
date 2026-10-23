import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditAccount extends StatefulWidget {
  final String fullName;
  final String email;

  const EditAccount({super.key, required this.fullName, required this.email});

  @override
  State<EditAccount> createState() => _EditAccountState();
}

class _EditAccountState extends State<EditAccount> {
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;

  String _imageUrl = "assets/profile.jpg";

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _fetchUserData();
  }

  //────────────────────────  FETCHING/LAODING  ─────────────────────────
  Future<void> _fetchUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final response =
        await Supabase.instance.client
            .from('profiles')
            .select('full_name, email')
            .eq('id', user.id)
            .single();

    if (response.isNotEmpty) {
      _fullNameController.text = response['full_name'];
      _emailController.text = response['email'];
    }
  }

  //────────────────────────  CHANGES SAVED TO SUPABASE ─────────────────────────
  Future<void> _saveChanges() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No user logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your password to save changes.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Re-authentication failed');
      }

      final updates = {
        'id': user.id,
        'full_name': _fullNameController.text,
        'email': email,
      };

      await Supabase.instance.client.from('profiles').upsert(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully updated profile!')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unexpected error occurred'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool isPasswordVisible = false;

  void toggleVisibility() {
    setState(() {
      isPasswordVisible = !isPasswordVisible;
    });
  }

  Widget _buildTextField(
    String labelText,
    IconData icon,
    TextEditingController controller, {

    bool isPassword = false,
    bool isVisible = false,
    String? errorText,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA0C878), Color(0xFFF8FBE3), Color(0xFFFFFFEC)],
          stops: [0.0, 0.32, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_circle_left_rounded,
              color: Colors.white,
              size: screenHeight * 0.035,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: Text(
            "Edit Account",
            style: TextStyle(
              fontSize: screenHeight * 0.03,
              fontFamily: 'Inter_Bold',
              color: Colors.white,
            ),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final w = constraints.maxWidth;

              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.07,
                          vertical: h * 0.04,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: screenHeight * 0.01),

                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _imageUrl = 'assets/profile.jpg';
                                  });
                                },
                                child: CircleAvatar(
                                  radius: screenWidth * 0.15,
                                  backgroundImage: AssetImage(_imageUrl),
                                ),
                              ),
                            ),
                            SizedBox(height: screenHeight * 0.025),

                            _buildTextField(
                              'Full Name',
                              Icons.person_outline,
                              _fullNameController,
                            ),
                            SizedBox(height: screenHeight * 0.012),

                            _buildTextField(
                              'Email',
                              Icons.email_outlined,
                              _emailController,
                            ),
                            SizedBox(height: screenHeight * 0.012),

                            _buildTextField(
                              'Password',
                              Icons.lock,
                              _passwordController,
                              isPassword: true,
                              isVisible: isPasswordVisible,
                            ),
                            SizedBox(height: screenHeight * 0.03),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 16.0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: screenHeight * 0.056,
                      child: Container(
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
                        child: ElevatedButton(
                          onPressed: () async {
                            await _saveChanges();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            "Save Changes",
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
