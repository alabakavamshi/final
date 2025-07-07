import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class UmpireStatsPage extends StatefulWidget {
  final String userId;
  final String userEmail;

  const UmpireStatsPage({super.key, required this.userId, required this.userEmail});

  @override
  State<UmpireStatsPage> createState() => _UmpireStatsPageState();
}

class _UmpireStatsPageState extends State<UmpireStatsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  int _totalMatches = 0;
  int _completedMatches = 0;
  int _ongoingMatches = 0;
  int _totalTournaments = 0;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get all tournaments (we'll filter matches locally)
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .get();

      final Set<String> tournamentIds = {};
      int totalMatches = 0;
      int completedMatches = 0;
      int ongoingMatches = 0;

      for (var tournamentDoc in tournamentsQuery.docs) {
        final tournamentData = tournamentDoc.data();
        final matches = List<Map<String, dynamic>>.from(tournamentData['matches'] ?? []);

        bool umpireInThisTournament = false;

        for (var match in matches) {
          try {
            // Check umpire assignment at MATCH level
            final matchUmpire = match['umpire'] as Map<String, dynamic>?;
            if (matchUmpire == null) continue;

            final matchUmpireEmail = (matchUmpire['email'] as String?)?.toLowerCase().trim();
            if (matchUmpireEmail != widget.userEmail.toLowerCase().trim()) continue;

            // Count this match
            totalMatches++;
            umpireInThisTournament = true;

            // Check match status
            if (match['completed'] == true) {
              completedMatches++;
            } else if (match['liveScores']?['isLive'] == true) {
              ongoingMatches++;
            }
          } catch (e) {
            debugPrint('Error processing match: $e');
          }
        }

        if (umpireInThisTournament) {
          tournamentIds.add(tournamentDoc.id);
        }
      }

      if (mounted) {
        setState(() {
          _totalMatches = totalMatches;
          _completedMatches = completedMatches;
          _ongoingMatches = ongoingMatches;
          _totalTournaments = tournamentIds.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load stats';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B263B),
        title: Text(
          'Umpire Statistics',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchStats,
            tooltip: 'Refresh Stats',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: GoogleFonts.poppins(color: Colors.red, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchStats,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Try Again',
                          style: GoogleFonts.poppins(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildStatCard(
                        title: 'Total Matches Officiated',
                        value: _totalMatches.toString(),
                        icon: Icons.sports_tennis,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        title: 'Tournaments Umpired',
                        value: _totalTournaments.toString(),
                        icon: Icons.emoji_events,
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        title: 'Completed Matches',
                        value: _completedMatches.toString(),
                        icon: Icons.check_circle,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        title: 'Ongoing Matches',
                        value: _ongoingMatches.toString(),
                        icon: Icons.timer,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      color: Colors.white10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}