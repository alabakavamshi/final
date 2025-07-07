import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class SchedulePage extends StatefulWidget {
  final String userId;

  const SchedulePage({super.key, required this.userId});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _matches = [];
  Set<DateTime> _tournamentDates = {};
  Set<DateTime> _matchDates = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchTournamentsAndMatches();
  }

  Future<void> _fetchTournamentsAndMatches() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      debugPrint('Fetching tournaments for user: ${widget.userId}');

      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('createdBy', isEqualTo: widget.userId)
          .where('status', whereIn: ['open', 'ongoing'])
          .orderBy('startDate', descending: false)
          .get();

      debugPrint('Found ${tournamentsQuery.docs.length} tournaments');

      final List<Map<String, dynamic>> allMatches = [];
      final Set<DateTime> tournamentDates = {};
      final Set<DateTime> matchDates = {};

      for (var doc in tournamentsQuery.docs) {
        final data = doc.data();
        debugPrint('Processing tournament: ${doc.id}');

        // Debug print tournament dates
        final startDate = (data['startDate'] as Timestamp).toDate();
        final endDate = (data['endDate'] as Timestamp?)?.toDate() ?? startDate;
        debugPrint('Tournament dates: $startDate to $endDate');

        // Add all dates between start and end date
        for (var date = startDate;
            date.isBefore(endDate.add(const Duration(days: 1)));
            date = date.add(const Duration(days: 1))) {
          final dateOnly = DateTime(date.year, date.month, date.day);
          tournamentDates.add(dateOnly);
        }

        // Process matches
        final matches = List<Map<String, dynamic>>.from(data['matches'] ?? []);
        debugPrint('Found ${matches.length} matches in tournament');

        for (var match in matches) {
          if (match['startTime'] != null) {
            final matchStartTime = (match['startTime'] as Timestamp).toDate();
            final matchDateOnly = DateTime(
              matchStartTime.year,
              matchStartTime.month,
              matchStartTime.day,
            );

            debugPrint('Match ${match['matchId']} on $matchStartTime');

            matchDates.add(matchDateOnly);

            if (matchDateOnly.day == _selectedDate.day &&
                matchDateOnly.month == _selectedDate.month &&
                matchDateOnly.year == _selectedDate.year) {
              debugPrint('Match matches selected date!');
              allMatches.add({
                'matchId': match['matchId']?.toString() ?? '',
                'tournamentId': doc.id,
                'tournamentName': data['name']?.toString() ?? 'Unnamed Tournament',
                'player1': match['player1']?.toString() ?? 'TBD',
                'player2': match['player2']?.toString() ?? 'TBD',
                'startTime': matchStartTime,
                'status': match['status']?.toString() ?? 'scheduled',
              });
            }
          } else {
            debugPrint('Match ${match['matchId']} has no startTime');
          }
        }
      }

      debugPrint('Total matches found for selected date: ${allMatches.length}');
      debugPrint('Tournament dates: ${tournamentDates.length}');
      debugPrint('Match dates: ${matchDates.length}');

      if (mounted) {
        setState(() {
          _matches = allMatches;
          _tournamentDates = tournamentDates;
          _matchDates = matchDates;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching matches: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load matches: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _rescheduleMatch(String tournamentId, String matchId, DateTime newTime) async {
    try {
      final tournamentDoc = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);
      final tournamentSnapshot = await tournamentDoc.get();
      final matches = List<Map<String, dynamic>>.from(tournamentSnapshot.data()?['matches'] ?? []);
      final matchIndex = matches.indexWhere((m) => m['matchId'] == matchId);

      if (matchIndex != -1) {
        matches[matchIndex]['startTime'] = Timestamp.fromDate(newTime);
        await tournamentDoc.update({'matches': matches});

        if (mounted) {
          setState(() {
            _matches.firstWhere(
              (m) => m['matchId'] == matchId && m['tournamentId'] == tournamentId,
            )['startTime'] = newTime;
          });

          toastification.show(
            context: context,
            type: ToastificationType.success,
            title: const Text('Success'),
            description: const Text('Match rescheduled'),
            autoCloseDuration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          );

          // Refresh the dates
          _fetchTournamentsAndMatches();
        }
      }
    } catch (e) {
      debugPrint('Error rescheduling match: $e');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to reschedule match: ${e.toString()}'),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        );
      }
    }
  }

  Widget _buildCalendarRow() {
    return Column(
      children: [
        Container(
          height: 100,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 60, // Show 60 days
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final dateOnly = DateTime(date.year, date.month, date.day);
              final isSelected = dateOnly.day == _selectedDate.day &&
                  dateOnly.month == _selectedDate.month &&
                  dateOnly.year == _selectedDate.year;

              final hasTournament = _tournamentDates.any((d) =>
                  d.day == dateOnly.day && d.month == dateOnly.month && d.year == dateOnly.year);

              final hasMatches = _matchDates.any((d) =>
                  d.day == dateOnly.day && d.month == dateOnly.month && d.year == dateOnly.year);

              return GestureDetector(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _selectedDate = dateOnly;
                      _fetchTournamentsAndMatches();
                    });
                  }
                },
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blueAccent
                        : hasMatches
                            ? const Color(0xFF2E7D32)
                            : hasTournament
                                ? const Color(0xFF1B5E20)
                                : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blueAccent
                          : hasMatches
                              ? Colors.greenAccent
                              : hasTournament
                                  ? Colors.lightGreen
                                  : Colors.white30,
                      width: hasMatches ? 2 : (hasTournament ? 1.5 : 1),
                    ),
                    boxShadow: hasMatches
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.3),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )
                          ]
                        : hasTournament
                            ? [
                                BoxShadow(
                                  color: Colors.lightGreen.withOpacity(0.2),
                                  blurRadius: 2,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('MMM').format(date).toUpperCase(),
                        style: GoogleFonts.poppins(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 10,
                          fontWeight: hasMatches ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEE').format(date),
                        style: GoogleFonts.poppins(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: hasMatches ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd').format(date),
                        style: GoogleFonts.poppins(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasMatches || hasTournament)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: hasMatches ? Colors.greenAccent : Colors.lightGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(const Color(0xFF2E7D32), 'Matches'),
              const SizedBox(width: 16),
              _buildLegendItem(const Color(0xFF1B5E20), 'Tournaments'),
              const SizedBox(width: 16),
              _buildLegendItem(Colors.blueAccent, 'Selected'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMatchStatusChip(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'completed':
        backgroundColor = Colors.green;
        textColor = Colors.white;
        break;
      case 'ongoing':
        backgroundColor = Colors.orange;
        textColor = Colors.white;
        break;
      case 'cancelled':
        backgroundColor = Colors.red;
        textColor = Colors.white;
        break;
      default: // scheduled
        backgroundColor = Colors.blue;
        textColor = Colors.white;
    }

    return Chip(
      label: Text(
        status.capitalize(),
        style: GoogleFonts.poppins(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: backgroundColor,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B263B),
        title: Text(
          'Match Schedule',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchTournamentsAndMatches,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCalendarRow(),
          if (_isLoading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.poppins(color: Colors.red, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _matches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.event_busy, size: 48, color: Colors.white54),
                            const SizedBox(height: 16),
                            Text(
                              'No matches scheduled for',
                              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 18),
                            ),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(_selectedDate),
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchTournamentsAndMatches,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                'Refresh Data',
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _matches.length,
                        itemBuilder: (context, index) {
                          final match = _matches[index];
                          final startTime = match['startTime'] != null
                              ? DateFormat('hh:mm a').format(match['startTime'] as DateTime)
                              : 'Not scheduled';
                          return Card(
                            color: Colors.white10,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${match['player1']} vs ${match['player2']}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      _buildMatchStatusChip(match['status']),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.event, color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          match['tournamentName'],
                                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        startTime,
                                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.edit_calendar, color: Colors.amber, size: 20),
                                        onPressed: () async {
                                          final newTime = await showDateTimePicker(context);
                                          if (newTime != null) {
                                            await _rescheduleMatch(
                                              match['tournamentId'],
                                              match['matchId'],
                                              newTime,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> showDateTimePicker(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1B263B),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0D1B2A),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1B263B),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0D1B2A),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}