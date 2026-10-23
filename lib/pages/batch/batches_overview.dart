import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BatchesOverview extends StatelessWidget {
  final String batchId;
  final int batchNumber;

  const BatchesOverview({
    required this.batchId,
    required this.batchNumber,
    Key? key,
  }) : super(key: key);

  Future<Map<String, dynamic>> fetchBatchDates(String batchId) async {
    final resp =
        await Supabase.instance.client
            .from('batches')
            .select('date_planted, date_harvested')
            .eq('id', batchId)
            .single();
    if (resp == null) throw Exception('No batch dates found');
    return Map<String, dynamic>.from(resp);
  }

  Future<List<Map<String, dynamic>>> fetchBatchDetails(String batchId) async {
    final resp = await Supabase.instance.client
        .from('readings')
        .select('date, ph, tds, temperature, humidity')
        .eq('batch_id', batchId)
        .order('date', ascending: true);
    if (resp == null || resp is! List)
      throw Exception('Failed to load readings');
    return List<Map<String, dynamic>>.from(resp);
  }

  Widget buildBatchDatesCard(
    BuildContext context,
    Map<String, dynamic> batchDates,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    DateTime? plantedDate =
        batchDates['date_planted'] != null
            ? DateTime.tryParse(batchDates['date_planted'])
            : null;

    DateTime? harvestedDate =
        batchDates['date_harvested'] != null
            ? DateTime.tryParse(batchDates['date_harvested'])
            : null;

    final planted =
        plantedDate != null ? DateFormat.MMMd().format(plantedDate) : 'N/A';

    final harvested =
        harvestedDate != null ? DateFormat.MMMd().format(harvestedDate) : 'N/A';

    // Calculate duration
    final duration =
        (plantedDate != null && harvestedDate != null)
            ? '${harvestedDate.difference(plantedDate).inDays} days'
            : 'N/A';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Growth Cycle Duration: $duration',
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: screenWidth * 0.038,
                    fontFamily: 'Inter_Bold',
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$planted to $harvested',
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: screenWidth * 0.034,
                    fontWeight: FontWeight.bold,
                    color: const Color.fromARGB(158, 0, 0, 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildReadingsTable(
    BuildContext context,
    List<Map<String, dynamic>> readings,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final screenWidth =
        MediaQuery.of(context).size.width; // 👈 Get screen width
    final dayColumnWidth = screenWidth * 0.20;
    final otherColumnWidth = (screenWidth - dayColumnWidth - 30) / 4;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: ClipRRect(
                // 👈 Add this
                borderRadius: BorderRadius.circular(12),
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(
                    Colors.grey.shade200,
                  ),
                  columnSpacing: 16,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: dayColumnWidth,
                        child: Text(
                          'Day',
                          style: textTheme.titleSmall?.copyWith(
                            fontSize: screenWidth * 0.042,
                            fontFamily: 'Inter_Bold',
                          ),
                        ),
                      ),
                    ),
                    ...['pH', 'TDS', 'Temp', 'Humid'].map((label) {
                      return DataColumn(
                        label: SizedBox(
                          width: otherColumnWidth,
                          child: Text(
                            label,
                            style: textTheme.titleSmall?.copyWith(
                              fontSize: screenWidth * 0.042,
                              fontFamily: 'Inter_Bold',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                  rows:
                      readings.isEmpty
                          ? [
                            DataRow(
                              cells: List.generate(
                                5,
                                (_) => DataCell(
                                  Text(
                                    'No data',
                                    style: textTheme.bodySmall?.copyWith(
                                      fontSize:
                                          screenWidth * 0.032, // 👈 body size
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ]
                          : readings.map((r) {
                            final date =
                                r['date'] != null
                                    ? DateFormat.MMMd().format(
                                      DateTime.parse(r['date'] as String),
                                    )
                                    : 'N/A';
                            String cell(String? v) => v ?? 'N/A';

                            return DataRow(
                              cells: [
                                // Day column: wider
                                DataCell(
                                  SizedBox(
                                    width: dayColumnWidth,
                                    child: Text(
                                      date,
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontSize: screenWidth * 0.042,
                                      ),
                                    ),
                                  ),
                                ),
                                // Other columns: equal width
                                DataCell(
                                  SizedBox(
                                    width: otherColumnWidth,
                                    child: Text(
                                      cell(r['ph']?.toString()),
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontSize: screenWidth * 0.042,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: otherColumnWidth,
                                    child: Text(
                                      cell(r['tds']?.toString()),
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontSize: screenWidth * 0.042,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: otherColumnWidth,
                                    child: Text(
                                      cell(r['temperature']?.toString()),
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontSize: screenWidth * 0.042,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: otherColumnWidth,
                                    child: Text(
                                      cell(r['humidity']?.toString()),
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontSize: screenWidth * 0.042,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.width;
    final screenWidth = MediaQuery.of(context).size.height;
    final combined = Future.wait([
      fetchBatchDates(batchId),
      fetchBatchDetails(batchId),
    ]);

    return Scaffold(
      backgroundColor: const Color(0xFFEAEED1),
      appBar: AppBar(
        title: Text(
          'Batch $batchNumber Overview',
          style: TextStyle(
            fontSize: screenWidth * 0.026,
            fontFamily: 'Inter_Bold',
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: FutureBuilder<List<dynamic>>(
          future: combined,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return const Center(child: Text('Error loading data.'));
            }

            final dates = snap.data![0] as Map<String, dynamic>;
            final readings = List<Map<String, dynamic>>.from(
              snap.data![1] as List,
            );

            final panels = [
              buildBatchDatesCard(context, dates),
              buildReadingsTable(context, readings),
            ];

            return LayoutBuilder(
              builder: (ctx, c) {
                // side-by-side on tablets (wider than 600dp)
                if (c.maxWidth > 600) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: panels
                        .map((w) => Expanded(child: w))
                        .toList(growable: false),
                  );
                }
                // stacked on narrow screens
                return SingleChildScrollView(child: Column(children: panels));
              },
            );
          },
        ),
      ),
    );
  }
}
