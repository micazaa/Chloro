import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import 'package:chloro/pages/batch/batches_overview.dart';
import 'package:chloro/pages/auth/login.dart';
import 'package:chloro/helpers/edit_account.dart';
import '../../services/network_connection.dart';
import '../../helpers/offline_banner.dart';

class Account extends StatefulWidget {
  const Account({super.key});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> {
  late Future<Map<String, dynamic>> _userData;
  int _harvestedCount = 0;
  int _harvestedNFTCount = 0;
  int _harvestedKratkyCount = 0;
  bool _isLoadingHarvest = true;

  @override
  void initState() {
    super.initState();
    _userData = fetchUserData();
    _loadHarvestCounts();
    _loadCurrentlyPlantedCounts();
    fetchLifeCycleData();
  }

  Future<void> _loadCurrentlyPlantedCounts() async {
    setState(() => _isLoadingHarvest = true);

    try {
      final response = await Supabase.instance.client
          .from('batches')
          .select('method, num_of_plants')
          .filter('is_harvested', 'is', null);

      if (response is List) {
        final rows = response.cast<Map<String, dynamic>>();

        // Compute total plants for each method
        final nftTotal = rows
            .where((row) => row['method']?.toString().toLowerCase() == 'nft')
            .fold<int>(
              0,
              (sum, row) =>
                  sum + (int.tryParse(row['num_of_plants'].toString()) ?? 0),
            );

        final kratkyTotal = rows
            .where((row) => row['method']?.toString().toLowerCase() == 'kratky')
            .fold<int>(
              0,
              (sum, row) =>
                  sum + (int.tryParse(row['num_of_plants'].toString()) ?? 0),
            );

        setState(() {
          _harvestedNFTCount = nftTotal;
          _harvestedKratkyCount = kratkyTotal;
        });
      } else {
        print('🔴 Unexpected response type: ${response.runtimeType}');
      }
    } catch (e) {
      print('🔴 Error loading currently planted counts: $e');
    } finally {
      setState(() => _isLoadingHarvest = false);
    }
  }

  Future<void> _loadHarvestCounts() async {
    setState(() => _isLoadingHarvest = true);

    try {
      final response = await Supabase.instance.client
          .from('batches')
          .select('method, num_of_plants')
          .eq('is_harvested', 'yes');

      if (response is List) {
        final rows = response.cast<Map<String, dynamic>>();

        final nftTotal = rows
            .where((row) => row['method']?.toString().toLowerCase() == 'nft')
            .fold<int>(
              0,
              (sum, row) =>
                  sum + (int.tryParse(row['num_of_plants'].toString()) ?? 0),
            );

        final kratkyTotal = rows
            .where((row) => row['method']?.toString().toLowerCase() == 'kratky')
            .fold<int>(
              0,
              (sum, row) =>
                  sum + (int.tryParse(row['num_of_plants'].toString()) ?? 0),
            );

        final total = nftTotal + kratkyTotal;

        setState(() {
          _harvestedNFTCount = nftTotal;
          _harvestedKratkyCount = kratkyTotal;
          _harvestedCount = total;
        });
      } else {
        print('🔴 Unexpected response: ${response.runtimeType}');
      }
    } catch (e) {
      print('🔴 Error loading harvest counts: $e');
    } finally {
      setState(() => _isLoadingHarvest = false);
    }
  }

  Future<Map<String, dynamic>> fetchUserData() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      final response =
          await Supabase.instance.client
              .from('profiles')
              .select('full_name, email')
              .eq('id', user.id)
              .single();

      if (response != null) {
        return {
          'full_name': response['full_name'] ?? 'No Name',
          'email': response['email'] ?? 'No Email',
        };
      } else {
        throw Exception('No data found');
      }
    } catch (e) {
      throw Exception('Error fetching user data');
    }
  }

  Widget buildLifeCycleCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchLifeCycleData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/no_batch.png',
                  width: screenHeight * 0.14,
                  height: screenHeight * 0.14,
                  fit: BoxFit.contain,
                ),
                Text(
                  'Nothing here.',
                  style: TextStyle(
                    fontSize: screenHeight * 0.020,
                    fontFamily: 'Inter_Bold',
                    color: const Color(0xFF95B45B),
                  ),
                ),
                Text(
                  'You have not harvested any batch yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenHeight * 0.014,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: screenHeight * 0.02),
              ],
            ),
          );
        }

        final lifeCycleList = snapshot.data!;

        return Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
          padding: EdgeInsets.all(screenWidth * 0.06),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 8, spreadRadius: 2),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Life Cycle",
                style: TextStyle(
                  fontSize: screenHeight * 0.020,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(color: Colors.black12),
              SizedBox(height: screenHeight * 0.012),
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: lifeCycleList.length,
                itemBuilder: (context, index) {
                  final batch = lifeCycleList[index];
                  DateTime planted = DateTime.parse(batch['date_planted']);
                  DateTime harvested = DateTime.parse(batch['date_harvested']);
                  int daysLifeCycle = harvested.difference(planted).inDays;
                  int batchNumber = batch['batch_number'];
                  String batchId = batch['id'];
                  String batchMethod = batch['method'];

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => BatchesOverview(
                                batchId: batchId,
                                batchNumber: batchNumber,
                              ),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$daysLifeCycle days',
                                    style: TextStyle(
                                      fontSize: screenHeight * 0.018,
                                      fontFamily: 'Inter_Bold',
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.004),
                                  Text(
                                    '${DateFormat('MMM dd').format(planted.toLocal())} - ${DateFormat('MMM dd').format(harvested.toLocal())}',
                                    style: TextStyle(
                                      fontSize: screenHeight * 0.014,
                                      fontWeight: FontWeight.bold,
                                      color: const Color.fromARGB(
                                        255,
                                        109,
                                        109,
                                        109,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Batch $batchNumber $batchMethod',
                                    style: TextStyle(
                                      fontSize: screenHeight * 0.014,
                                      fontWeight: FontWeight.bold,
                                      color: const Color.fromARGB(
                                        255,
                                        109,
                                        109,
                                        109,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: screenHeight * 0.02,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                        SizedBox(height: screenHeight * 0.015),
                        if (index < lifeCycleList.length - 1)
                          const Divider(color: Colors.black12),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchLifeCycleData() async {
    final response = await Supabase.instance.client
        .from('batches')
        .select('id, method, batch_number, date_planted, date_harvested')
        .eq('is_harvested', 'yes');

    if (response != null && response is List) {
      return response.map((e) => e as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to fetch life cycle data');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final NetworkController _net = Get.find();

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
        ),
        body: SafeArea(
          child: Obx(() {
            if (_net.isOffline.value) {
              return Center(
                child: OfflineBanner(
                  onTryAgain: () {
                    _net.checkConnectivity();
                  },
                ),
              );
            } else {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final maxHeight = constraints.maxHeight;
                  final cardWidth = maxWidth * 0.21;
                  final cardHeight = maxHeight * 0.14;

                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: maxHeight),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: screenHeight * 0.020),
                                  Center(
                                    child: FutureBuilder<Map<String, dynamic>>(
                                      future: _userData,
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return const CircularProgressIndicator();
                                        } else if (snapshot.hasError) {
                                          return Text(
                                            'Error: ${snapshot.error}',
                                          );
                                        } else if (!snapshot.hasData ||
                                            snapshot.data == null) {
                                          return const Text(
                                            'No data available',
                                          );
                                        }

                                        final userData = snapshot.data!;
                                        final fullName =
                                            userData['full_name'] ?? 'No Name';
                                        final email =
                                            userData['email'] ?? 'No Email';

                                        return Container(
                                          width: maxWidth * 0.9,
                                          padding: const EdgeInsets.all(20.0),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black12,
                                                blurRadius: 10,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              const CircleAvatar(
                                                radius: 40,
                                                backgroundImage: AssetImage(
                                                  "assets/profile.jpg",
                                                ),
                                              ),
                                              SizedBox(
                                                width: screenHeight * 0.02,
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      fullName,
                                                      style: TextStyle(
                                                        fontSize:
                                                            screenWidth * 0.038,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    Text(
                                                      email,
                                                      style: TextStyle(
                                                        fontSize:
                                                            screenWidth * 0.034,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder:
                                                          (context) =>
                                                              EditAccount(
                                                                fullName:
                                                                    fullName,
                                                                email: email,
                                                              ),
                                                    ),
                                                  );
                                                },
                                                child: const Icon(
                                                  Icons.edit,
                                                  size: 20,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.030),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Column(
                                        children: [
                                          Text(
                                            "Harvested:",
                                            style: TextStyle(
                                              fontSize: screenWidth * 0.036,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: screenHeight * 0.01),
                                          _buildCard(
                                            context,
                                            "Harvested",
                                            Icons.eco,
                                            _isLoadingHarvest
                                                ? "…"
                                                : '$_harvestedCount',
                                            cardWidth,
                                            cardHeight,
                                          ),
                                        ],
                                      ),
                                      Container(
                                        height: cardHeight,
                                        width: 1,
                                        color: Colors.black26,
                                      ),
                                      Column(
                                        children: [
                                          Text(
                                            "Currently Planted:",
                                            style: TextStyle(
                                              fontSize: screenWidth * 0.036,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: screenHeight * 0.01),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              _buildCard(
                                                context,
                                                "NFT",
                                                Icons.grass,
                                                _isLoadingHarvest
                                                    ? "…"
                                                    : '$_harvestedNFTCount',
                                                cardWidth,
                                                cardHeight,
                                              ),
                                              const SizedBox(width: 16),
                                              _buildCard(
                                                context,
                                                "Kratky",
                                                Icons.inventory,
                                                _isLoadingHarvest
                                                    ? "…"
                                                    : '$_harvestedKratkyCount',
                                                cardWidth,
                                                cardHeight,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: screenHeight * 0.02),
                                  buildLifeCycleCard(context),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Logout button fixed at bottom
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 16.0,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: screenHeight * 0.056,
                          child: ElevatedButton(
                            onPressed: () async {
                              try {
                                await Supabase.instance.client.auth.signOut();

                                final session =
                                    Supabase
                                        .instance
                                        .client
                                        .auth
                                        .currentSession;
                                if (session == null) {
                                  final prefs =
                                      await SharedPreferences.getInstance();

                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (_) => LogIn()),
                                    (_) => false,
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Logout failed — please try again.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error signing out')),
                                );
                              }
                            },
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
                              child: Container(
                                alignment: Alignment.center,
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Text(
                                  "Logout",
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
                  );
                },
              );
            }
          }),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    String title,
    IconData icon,
    String value,
    double width,
    double height,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        padding: EdgeInsets.all(screenHeight * 0.012),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(screenHeight * 0.02),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 5, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: height * 0.2, color: Colors.black54),
            SizedBox(height: screenHeight * 0.007),
            Text(
              value,
              style: TextStyle(
                fontSize: screenWidth * 0.042,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: screenWidth * 0.030,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
