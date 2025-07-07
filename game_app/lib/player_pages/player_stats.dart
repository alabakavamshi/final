import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class PlayerStatsPage extends StatefulWidget {
  final String userId;

  const PlayerStatsPage({super.key, required this.userId});

  @override
  State<PlayerStatsPage> createState() => _PlayerStatsPageState();
}

class _PlayerStatsPageState extends State<PlayerStatsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  int _totalMatches = 0;
  int _wins = 0;
  int _losses = 0;
  int _tournamentsPlayed = 0;
  double _winPercentage = 0.0;
  String _lastMatchDate = 'N/A';
  String _frequentOpponent = 'N/A';
  Map<String, dynamic>? _playerDetails;
  String _recentMatchResult = 'N/A';
  Color _recentMatchResultColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _fetchPlayerData();
    _fetchStats();
  }

  Future<void> _fetchPlayerData() async {
    try {
      final playerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (playerDoc.exists) {
        setState(() {
          _playerDetails = playerDoc.data();
        });
      } else {
        debugPrint('Player document not found for ID: ${widget.userId}');
      }
    } catch (e) {
      debugPrint('Error fetching player data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load player profile';
        });
      }
    }
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .get();

      int totalMatches = 0;
      int wins = 0;
      int losses = 0;
      DateTime? lastMatchDate;
      Map<String, dynamic>? mostRecentMatch;
      final opponentCount = <String, int>{};
      final tournamentIds = <String>{};

      for (var tournamentDoc in tournamentsQuery.docs) {
        final tournamentData = tournamentDoc.data();
        final matches = List<Map<String, dynamic>>.from(tournamentData['matches'] ?? []);

        bool playedInTournament = false;

        for (var match in matches) {
          final player1Id = match['player1Id']?.toString() ?? '';
          final player2Id = match['player2Id']?.toString() ?? '';
          final team1Ids = List<String>.from(match['team1Ids'] ?? []);
          final team2Ids = List<String>.from(match['team2Ids'] ?? []);

          // Check if player is in this match
          if (player1Id == widget.userId ||
              player2Id == widget.userId ||
              team1Ids.contains(widget.userId) ||
              team2Ids.contains(widget.userId)) {
            // Only count completed matches for stats
            final isCompleted = match['completed'] == true;

            if (isCompleted) {
              totalMatches++;
              playedInTournament = true;

              // Track opponent
              if (player1Id == widget.userId && player2Id.isNotEmpty) {
                opponentCount[player2Id] = (opponentCount[player2Id] ?? 0) + 1;
              } else if (player2Id == widget.userId && player1Id.isNotEmpty) {
                opponentCount[player1Id] = (opponentCount[player1Id] ?? 0) + 1;
              }

              // Check winner
              final winner = match['winner']?.toString();
              if (winner == 'player1' && player1Id == widget.userId ||
                  winner == 'player2' && player2Id == widget.userId) {
                wins++;
              } else if (winner != null && winner.isNotEmpty) {
                losses++;
              }

              // Track last match date and most recent match
              final matchTime = match['startTime'] as Timestamp?;
              if (matchTime != null) {
                final matchDate = matchTime.toDate();
                if (lastMatchDate == null || matchDate.isAfter(lastMatchDate)) {
                  lastMatchDate = matchDate;
                  mostRecentMatch = match;
                }
              }
            }
          }
        }

        if (playedInTournament) {
          tournamentIds.add(tournamentDoc.id);
        }
      }

      // Calculate recent match result
      if (mostRecentMatch != null) {
        final liveScores = mostRecentMatch['liveScores'] as Map<String, dynamic>? ?? {};
        final player1Scores = liveScores['player1'] as List<dynamic>? ?? [];
        final player2Scores = liveScores['player2'] as List<dynamic>? ?? [];
        final winner = mostRecentMatch['winner']?.toString();
        final player1Id = mostRecentMatch['player1Id']?.toString() ?? '';
        final player2Id = mostRecentMatch['player2Id']?.toString() ?? '';

        // Calculate set scores
        int player1Sets = 0;
        int player2Sets = 0;
        for (int i = 0; i < player1Scores.length && i < player2Scores.length; i++) {
          if (player1Scores[i] > player2Scores[i] && player1Scores[i] >= 21) {
            player1Sets++;
          } else if (player2Scores[i] > player1Scores[i] && player2Scores[i] >= 21) {
            player2Sets++;
          }
        }

        // Determine if the current player is player1 or player2 and order set score
        bool isPlayer1 = player1Id == widget.userId;
        final setScore = isPlayer1 ? '$player1Sets-$player2Sets' : '$player2Sets-$player1Sets';

        // Determine win/loss
        bool isPlayerWinner = (winner == 'player1' && player1Id == widget.userId) ||
                             (winner == 'player2' && player2Id == widget.userId);

        _recentMatchResult = isPlayerWinner ? 'Won: $setScore' : 'Lost: $setScore';
        _recentMatchResultColor = isPlayerWinner ? Colors.greenAccent : Colors.redAccent;
      }

      await _calculateFrequentOpponent(opponentCount);

      if (mounted) {
        setState(() {
          _totalMatches = totalMatches;
          _wins = wins;
          _losses = losses;
          _tournamentsPlayed = tournamentIds.length;
          _winPercentage = totalMatches > 0 ? (wins / totalMatches * 100) : 0.0;
          _lastMatchDate = lastMatchDate != null
              ? DateFormat('MMM dd, yyyy').format(lastMatchDate)
              : 'N/A';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load stats: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _calculateFrequentOpponent(Map<String, int> opponentCount) async {
    if (opponentCount.isEmpty) {
      setState(() => _frequentOpponent = 'N/A');
      return;
    }

    final sortedOpponents = opponentCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topOpponentId = sortedOpponents.first.key;

    try {
      final opponentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(topOpponentId)
          .get();

      if (opponentDoc.exists) {
        final opponentName = opponentDoc['firstName'] ?? 'Unknown Player';
        if (mounted) {
          setState(() => _frequentOpponent = opponentName);
        }
      }
    } catch (e) {
      debugPrint('Error fetching opponent name: $e');
      if (mounted) {
        setState(() => _frequentOpponent = 'Opponent ${sortedOpponents.first.value}x');
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
          'Player Stats',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.poppins(color: Colors.red, fontSize: 16),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_playerDetails != null) _buildPlayerHeader(),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Total Matches',
                        _totalMatches.toString(),
                        Icons.sports_tennis,
                        Colors.blueAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Tournaments Played',
                        _tournamentsPlayed.toString(),
                        Icons.tour,
                        Colors.purpleAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Wins',
                        _wins.toString(),
                        Icons.emoji_events,
                        Colors.greenAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Losses',
                        _losses.toString(),
                        Icons.sentiment_dissatisfied,
                        Colors.redAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Win Percentage',
                        '${_winPercentage.toStringAsFixed(1)}%',
                        Icons.show_chart,
                        Colors.amberAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildRecentMatchCard(),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Last Match Played',
                        _lastMatchDate,
                        Icons.calendar_today,
                        Colors.tealAccent,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Frequent Opponent',
                        _frequentOpponent,
                        Icons.people_alt,
                        Colors.pinkAccent,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildPlayerHeader() {
    return Card(
      color: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: _playerDetails?['profileImage'] != null
                  ? NetworkImage(_playerDetails!['profileImage'])
                  : const AssetImage('assets/default_avatar.png') as ImageProvider,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_playerDetails?['firstName'] ?? ''} ${_playerDetails?['lastName'] ?? ''}',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playerDetails?['role']?.toString().capitalize() ?? 'Player',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      color: Colors.white.withOpacity(0.05),
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
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
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
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMatchCard() {
    return Card(
      color: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.score, color: Colors.orangeAccent, size: 24),
                ),
                const SizedBox(width: 16),
                Text(
                  'Recent Match Result',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _recentMatchResultColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _recentMatchResultColor),
              ),
              child: Text(
                _recentMatchResult,
                style: GoogleFonts.poppins(
                  color: _recentMatchResultColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}