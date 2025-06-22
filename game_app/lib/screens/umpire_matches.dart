import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/screens/matchcontrolpage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class UmpireMatchesPage extends StatefulWidget {
  const UmpireMatchesPage({super.key});

  @override
  State<UmpireMatchesPage> createState() => _UmpireMatchesPageState();
}

class _UmpireMatchesPageState extends State<UmpireMatchesPage> {
  String? _buildCountdown(Timestamp? eventDate) {
    if (eventDate == null) {
      return 'Start time not scheduled';
    }

    final now = DateTime.now();
    final startTime = eventDate.toDate();
    final difference = startTime.difference(now);

    if (difference.isNegative) {
      return 'Match should have started';
    } else if (difference.inHours >= 24) {
      final days = difference.inDays;
      final hours = difference.inHours % 24;
      return '${days}d ${hours}h';
    } else {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      final seconds = difference.inSeconds % 60;
      return '${hours}h ${minutes}m ${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A1325), Color(0xFF1A2A44)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'My Matches',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthLoading) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.cyanAccent),
                      );
                    } else if (state is AuthAuthenticated) {
                      final umpireEmail = state.user.email;
                      if (umpireEmail == null) {
                        return Center(
                          child: Text(
                            'No email associated with this account.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('tournaments')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(color: Colors.cyanAccent),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error loading matches: ${snapshot.error}',
                                style: GoogleFonts.poppins(color: Colors.redAccent),
                              ),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return Center(
                              child: Text(
                                'No tournaments available.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 18,
                                ),
                              ),
                            );
                          }

                          final matchesList = <Map<String, dynamic>>[];
                          for (var doc in snapshot.data!.docs) {
                            final tournamentId = doc.id;
                            final tournamentData = doc.data() as Map<String, dynamic>;
                            final matches = List<Map<String, dynamic>>.from(
                                tournamentData['matches'] ?? []);
                            final isDoubles = (tournamentData['gameFormat'] ?? '')
                                .toLowerCase()
                                .contains('doubles');
                            final eventDate = tournamentData['eventDate'] as Timestamp?;
                            for (var i = 0; i < matches.length; i++) {
                              final match = matches[i];
                              final matchUmpireEmail = match['umpire']?['email'] as String?;
                              if (matchUmpireEmail != null &&
                                  matchUmpireEmail.toLowerCase() == umpireEmail.toLowerCase()) {
                                matchesList.add({
                                  ...match,
                                  'tournamentId': tournamentId,
                                  'matchIndex': i,
                                  'isDoubles': isDoubles,
                                  'tournamentName': tournamentData['name'] ?? 'Unnamed',
                                  'eventDate': eventDate,
                                });
                              }
                            }
                          }

                          matchesList.sort((a, b) {
                            final timeA =
                                (a['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                            final timeB =
                                (b['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                            return timeA.compareTo(timeB);
                          });

                          if (matchesList.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'No matches assigned.',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Logged in as: $umpireEmail',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return AnimationLimiter(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: matchesList.length,
                              itemBuilder: (context, index) {
                                final matchData = matchesList[index];
                                final match = Map<String, dynamic>.from(matchData);
                                final tournamentId = match['tournamentId'];
                                final matchIndex = match['matchIndex'];
                                final isDoubles = match['isDoubles'];
                                final team1 = isDoubles
                                    ? (match['team1'] as List<dynamic>).join(', ')
                                    : match['player1'] ?? 'Player 1';
                                final team2 = isDoubles
                                    ? (match['team2'] as List<dynamic>).join(', ')
                                    : match['player2'] ?? 'Player 2';
                                final isLive = match['liveScores']?['isLive'] ?? false;
                                final isCompleted = match['completed'] ?? false;
                                final status = isCompleted
                                    ? 'completed'
                                    : isLive
                                        ? 'ongoing'
                                        : 'scheduled';
                                final currentGame = match['liveScores']?['currentGame'] ?? 1;
                                final team1Scores = List<int>.from(
                                    match['liveScores']?[isDoubles ? 'team1' : 'player1'] ??
                                        [0, 0, 0]);
                                final team2Scores = List<int>.from(
                                    match['liveScores']?[isDoubles ? 'team2' : 'player2'] ??
                                        [0, 0, 0]);
                                final startTime = (match['startTime'] as Timestamp?)?.toDate();
                                final eventDate = match['eventDate'] as Timestamp?;

                                return AnimationConfiguration.staggeredList(
                                  position: index,
                                  duration: const Duration(milliseconds: 500),
                                  child: SlideAnimation(
                                    verticalOffset: 50.0,
                                    child: FadeInAnimation(
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => MatchControlPage(
                                                tournamentId: tournamentId,
                                                match: match,
                                                matchIndex: matchIndex,
                                                isDoubles: isDoubles,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Card(
                                          color: Colors.white.withOpacity(0.1),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          margin: const EdgeInsets.symmetric(vertical: 8),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.all(16),
                                            title: Text(
                                              '$team1 vs $team2',
                                              style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Status: ${status.capitalize()}',
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Text(
                                                  'Tournament: ${match['tournamentName']}',
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                if (startTime != null)
                                                  Text(
                                                    'Time: ${DateFormat('MMM dd, yyyy HH:mm').format(startTime)}',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.white70,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                if (!isLive && !isCompleted)
                                                  Text(
                                                      'Starts in: ${_buildCountdown(eventDate)}',
                                                      style: GoogleFonts.poppins(
                                                        color: Colors.cyanAccent,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                if (isLive)
                                                  Text(
                                                    'Score: ${team1Scores[currentGame - 1]} - ${team2Scores[currentGame - 1]}',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.cyanAccent,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                if (isCompleted && match['winner'] != null)
                                                  Text(
                                                    'Winner: ${match['winner'] == (isDoubles ? 'team1' : 'player1') ? team1 : team2}',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.greenAccent,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    } else {
                      return Center(
                        child: Text(
                          'Please log in as an umpire.',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 18,
                          ),
                        ),
                      );
                    }
      }
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}