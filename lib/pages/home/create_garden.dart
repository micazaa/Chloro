import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

import 'home_screen.dart';
import '../../services/network_connection.dart';
import '../../helpers/offline_banner.dart';

class CreateGarden extends StatefulWidget {
  const CreateGarden({super.key});

  @override
  State<CreateGarden> createState() => _CreateGardenState();
}

class _CreateGardenState extends State<CreateGarden> {
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _plantsController = TextEditingController();
  String selectedMethod = "NFT";

  @override
  void initState() {
    super.initState();
    _dateController.text = "Select Date";
    _plantsController.text = "";
  }

  //──────────────────────────────────  INPUTS  ─────────────────────────────────
  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _dateController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  Widget _label(String text, double h) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: h * 0.016,
      fontWeight: FontWeight.bold,
      color: const Color(0xFFB4B4B4),
    ),
  );

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required double w,
    required double h,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _label(label, h),
        SizedBox(height: h * 0.008),
        Center(
          child: Container(
            height: h * 0.06,
            width: w * 0.7,
            child: DropdownButtonFormField<String>(
              value: selectedMethod,
              items:
                  ["NFT", "Kratky"]
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Center(child: Text(m)),
                        ),
                      )
                      .toList(),
              onChanged: (v) => setState(() => selectedMethod = v!),
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: Colors.grey),
                contentPadding: EdgeInsets.symmetric(vertical: h * 0.015),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFFB4B4B4),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: h * 0.03),
      ],
    );
  }

  Widget _buildDateInput({
    required String label,
    required IconData icon,
    required double w,
    required double h,
  }) {
    return Column(
      children: [
        _label(label, h),
        SizedBox(height: h * 0.008),
        Center(
          child: Container(
            height: h * 0.06,
            width: w * 0.7,
            child: TextField(
              controller: _dateController,
              readOnly: true,
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, color: Colors.grey),
                  onPressed: () => _selectDate(context),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: h * 0.015),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFFB4B4B4),
                    width: 1.5,
                  ),
                ),
              ),
              onTap: () => _selectDate(context),
            ),
          ),
        ),

        SizedBox(height: h * 0.03),
      ],
    );
  }

  Widget _buildTextInput({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required double w,
    required double h,
  }) {
    return Column(
      children: [
        _label(label, h),
        SizedBox(height: h * 0.008),
        Center(
          child: Container(
            height: h * 0.06,
            width: w * 0.7,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: controller.clear,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: h * 0.015),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFFB4B4B4),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: h * 0.03),
      ],
    );
  }

  //──────────────────────────────────  HELPERS/FUNCTIONS  ─────────────────────────────────
  Future<int> _nextBatchNumber(String method) async {
    try {
      final res =
          await Supabase.instance.client
              .from('batches')
              .select('batch_number')
              .eq('method', method)
              .order('batch_number', ascending: false)
              .limit(1)
              .maybeSingle();

      if (res == null || res.isEmpty) return 1;
      return (res['batch_number'] as int) + 1;
    } catch (e) {
      debugPrint('Error fetching batch number');
      return 1;
    }
  }

  Future<void> _createBatch() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No user logged in')));
      return;
    }

    final dateText = _dateController.text;
    final plants =
        _plantsController.text.isNotEmpty
            ? int.tryParse(_plantsController.text)
            : null;
    if (dateText == 'Select Date') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly.')),
      );
      return;
    }

    final parts = dateText.split('/');
    final date = DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );

    final batchNumber = await _nextBatchNumber(selectedMethod);

    try {
      await Supabase.instance.client.from('batches').insert({
        'user_id': user.id,
        'batch_number': batchNumber,
        'method': selectedMethod,
        'date_planted': date.toIso8601String(),
        'num_of_plants': plants,
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final NetworkController _net = Get.find();
    RxBool isLoadingOffline = true.obs;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFFFBE6),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;

            return Column(
              children: [
                AppBar(
                  backgroundColor: const Color(0xFFFFFBE6),
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      size: screenHeight * 0.036,
                      color: Colors.black,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                Expanded(
                  child: Obx(() {
                    if (_net.isOffline.value) {
                      return Center(
                        child: OfflineBanner(
                          onTryAgain: () => _net.checkConnectivity(),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth * 0.08,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Chloro',
                                    style: TextStyle(
                                      fontFamily: 'Lecker',
                                      fontSize: screenHeight * 0.072,
                                      color: const Color(0xFF95B45B),
                                    ),
                                  ),
                                  Text(
                                    'Create a Garden',
                                    style: TextStyle(
                                      fontSize: screenHeight * 0.032,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF95B45B),
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.05),

                                  _buildDropdownField(
                                    label: 'Choose a Hydroponic Method',
                                    icon: Icons.water_drop,
                                    w: screenWidth,
                                    h: screenHeight,
                                  ),
                                  _buildDateInput(
                                    label: 'Select Transplant Date:',
                                    icon: Icons.calendar_today,
                                    w: screenWidth,
                                    h: screenHeight,
                                  ),
                                  _buildTextInput(
                                    label: 'Number of Plants',
                                    icon: Icons.tag,
                                    controller: _plantsController,
                                    w: screenWidth,
                                    h: screenHeight,
                                  ),

                                  SizedBox(height: screenHeight * 0.05),
                                  SizedBox(
                                    width: screenWidth * 0.7,
                                    height: screenHeight * 0.056,
                                    child: DecoratedBox(
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
                                        onPressed: _createBatch,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          'Create',
                                          style: TextStyle(
                                            fontSize: screenHeight * 0.018,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.02),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
