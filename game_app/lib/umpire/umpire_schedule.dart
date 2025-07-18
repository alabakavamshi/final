import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:game_app/umpire/matchcontrolpage.dart';

class UmpireSchedulePage extends StatefulWidget {
  final String userId;
  final String userEmail;

  const UmpireSchedulePage({super.key, required this.userId, required this.userEmail});

  @override
  State<UmpireSchedulePage> createState() => _UmpireSchedulePageState();
}

class _UmpireSchedulePageState extends State<UmpireSchedulePage> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _matches = [];
  Set<DateTime> _matchDates = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _filterMatchesOnly = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _matches = [];
      _matchDates = {};
    });

    try {
      final tournamentsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('status', whereIn: ['open', 'ongoing'])
          .orderBy('startDate', descending: false)
          .get();

      final List<Map<String, dynamic>> allMatches = [];
      final Set<DateTime> matchDates = {};

      for (var tournamentDoc in tournamentsSnapshot.docs) {
        final tournamentData = tournamentDoc.data();
        final matches = List<Map<String, dynamic>>.from(tournamentData['matches'] ?? []);

        for (var match in matches) {
          try {
            final matchUmpire = match['umpire'] as Map<String, dynamic>?;
            if (matchUmpire == null) continue;

            final matchUmpireEmail = (matchUmpire['email'] as String?)?.toLowerCase().trim();
            if (matchUmpireEmail != widget.userEmail.toLowerCase().trim()) continue;

            final matchStartTime = match['startTime'] as Timestamp?;
            if (matchStartTime == null) continue;

            final matchTime = matchStartTime.toDate();
            final matchDateOnly = DateTime(matchTime.year, matchTime.month, matchTime.day);
            
            matchDates.add(matchDateOnly);

            if (matchDateOnly.isAtSameMomentAs(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day))) {
              allMatches.add({
                'matchId': match['matchId']?.toString() ?? '',
                'tournamentId': tournamentDoc.id,
                'tournamentName': tournamentData['name']?.toString() ?? 'Unnamed Tournament',
                'player1': match['player1']?.toString() ?? 'TBD',
                'player2': match['player2']?.toString() ?? 'TBD',
                'startTime': matchTime,
                'status': match['completed'] == true 
                    ? 'completed' 
                    : (match['liveScores']?['isLive'] == true ? 'ongoing' : 'scheduled'),
                'location': (tournamentData['venue']?.isNotEmpty == true && tournamentData['city']?.isNotEmpty == true)
                    ? '${tournamentData['venue']}, ${tournamentData['city']}'
                    : tournamentData['city']?.isNotEmpty == true
                        ? tournamentData['city']
                        : 'Unknown',
                'match': match,
                'isDoubles': (tournamentData['gameFormat'] ?? '').toLowerCase().contains('doubles'),
                'matchIndex': matches.indexOf(match),
              });
            }
          } catch (e) {
            debugPrint('Error processing match: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _matches = allMatches;
          _matchDates = matchDates;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching matches: $e\nStack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load matches: $e';
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: _filterMatchesOnly
          ? (day) => _matchDates.any((d) => d.isAtSameMomentAs(DateTime(day.year, day.month, day.day)))
          : null,
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
    
    if (picked != null && picked != _selectedDate) {
      if (mounted) {
        setState(() {
          _selectedDate = picked;
        });
        await _fetchMatches();
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
            itemCount: 60,
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final dateOnly = DateTime(date.year, date.month, date.day);
              final isSelected = dateOnly.isAtSameMomentAs(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day));
              final hasMatches = _matchDates.any((d) => d.isAtSameMomentAs(dateOnly));

              if (_filterMatchesOnly && !hasMatches) {
                return const SizedBox.shrink();
              }

              return GestureDetector(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _selectedDate = dateOnly;
                      _fetchMatches();
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
                            : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blueAccent
                          : hasMatches
                              ? Colors.greenAccent
                              : Colors.white30,
                      width: hasMatches ? 2 : 1,
                    ),
                    boxShadow: hasMatches
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.3),
                              blurRadius: 4,
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
                      if (hasMatches)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildLegendItem(const Color(0xFF2E7D32), 'Match Days'),
                  const SizedBox(width: 16),
                  _buildLegendItem(Colors.blueAccent, 'Selected'),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.filter_alt,
                      color: _filterMatchesOnly ? Colors.blueAccent : Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _filterMatchesOnly = !_filterMatchesOnly;
                      });
                    },
                    tooltip: 'Show only days with matches',
                  ),
                ],
              ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B263B),
        title: Text(
          'Umpire Schedule',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            onPressed: () => _selectDate(context),
            tooltip: 'Open calendar',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchMatches,
            tooltip: 'Refresh schedule',
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.poppins(color: Colors.red, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchMatches,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              'Retry',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                          ),
                        ],
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
                              onPressed: _fetchMatches,
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
                          final startTime = DateFormat('hh:mm a').format(match['startTime'] as DateTime);
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
                                      Text(
                                        match['tournamentName'],
                                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
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
                                        icon: const Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MatchControlPage(
                                                tournamentId: match['tournamentId'],
                                                match: match['match'],
                                                matchIndex: match['matchIndex'],
                                                isDoubles: match['isDoubles'],
                                              ),
                                            ),
                                          );
                                        },
                                        tooltip: 'View match details',
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        match['location'],
                                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
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
}

extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}