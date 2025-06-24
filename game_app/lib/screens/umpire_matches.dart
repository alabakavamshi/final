// umpire_matches_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/screens/countdown_text.dart';
import 'package:game_app/screens/matchcontrolpage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class UmpireMatchesPage extends StatefulWidget {
  const UmpireMatchesPage({super.key});

  @override
  State<UmpireMatchesPage> createState() => _UmpireMatchesPageState();
}

class _UmpireMatchesPageState extends State<UmpireMatchesPage> {
  // Removed _timer and _now from here!
  // The countdown logic is now encapsulated in CountdownText

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
                  'My Officiating Schedule',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
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
                            'No email associated with this account',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('tournaments')
                            .where('matches', isNotEqualTo: [])
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
                                'Error loading schedule',
                                style: GoogleFonts.poppins(
                                  color: Colors.redAccent,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'No tournaments available',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Logged in as: $umpireEmail',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white60,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
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
                            final tournamentStartDate = tournamentData['startDate'] as Timestamp?;
                            final tournamentStartTime = tournamentData['startTime'] as Map<String, dynamic>?;

                            // Calculate tournament datetime
                            DateTime? tournamentDateTime;
                            if (tournamentStartDate != null && tournamentStartTime != null) {
                              final hour = tournamentStartTime['hour'] as int? ?? 0;
                              final minute = tournamentStartTime['minute'] as int? ?? 0;
                              tournamentDateTime = DateTime(
                                tournamentStartDate.toDate().year,
                                tournamentStartDate.toDate().month,
                                tournamentStartDate.toDate().day,
                                hour,
                                minute,
                              );
                            }

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
                                  'tournamentName': tournamentData['name'] ?? 'Tournament',
                                  'tournamentDateTime': tournamentDateTime,
                                });
                              }
                            }
                          }

                          // Sort matches by start time (soonest first)
                          matchesList.sort((a, b) {
                            final timeA = (a['startTime'] as Timestamp?)?.toDate() ??
                                a['tournamentDateTime'] ?? DateTime(2100);
                            final timeB = (b['startTime'] as Timestamp?)?.toDate() ??
                                b['tournamentDateTime'] ?? DateTime(2100);
                            return timeA.compareTo(timeB);
                          });

                          if (matchesList.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.schedule, size: 48, color: Colors.white60),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No matches assigned',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'You currently have no officiating assignments',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white60,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return AnimationLimiter(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: matchesList.length,
                              itemBuilder: (context, index) {
                                final matchData = matchesList[index];
                                final match = Map<String, dynamic>.from(matchData);
                                final tournamentId = match['tournamentId'];
                                final matchIndex = match['matchIndex'];
                                final isDoubles = match['isDoubles'];
                                final team1 = isDoubles
                                    ? (match['team1'] as List<dynamic>).join(' & ')
                                    : match['player1'] ?? 'Player 1';
                                final team2 = isDoubles
                                    ? (match['team2'] as List<dynamic>).join(' & ')
                                    : match['player2'] ?? 'Player 2';
                                final isLive = match['liveScores']?['isLive'] ?? false;
                                final isCompleted = match['completed'] ?? false;
                                final matchStartTime = match['startTime'] as Timestamp?;
                                final tournamentDateTime = match['tournamentDateTime'] as DateTime?;
                                final currentGame = match['liveScores']?['currentGame'] ?? 1;
                                final team1Scores = List<int>.from(
                                    match['liveScores']?[isDoubles ? 'team1' : 'player1'] ??
                                        [0, 0, 0]);
                                final team2Scores = List<int>.from(
                                    match['liveScores']?[isDoubles ? 'team2' : 'player2'] ??
                                        [0, 0, 0]);

                                // Determine the actual start time to display
                                final displayTime = matchStartTime?.toDate() ?? tournamentDateTime;
                                final countdownTime = matchStartTime ??
                                    (tournamentDateTime != null ? Timestamp.fromDate(tournamentDateTime) : null);

                                // Determine match status
                                String status;
                                Color statusColor;
                                if (isCompleted) {
                                  status = 'Completed';
                                  statusColor = Colors.greenAccent;
                                } else if (isLive) {
                                  status = 'In Progress';
                                  statusColor = Colors.amberAccent;
                                } else if (countdownTime != null &&
                                    countdownTime.toDate().isBefore(DateTime.now())) {
                                  status = 'Ready to Start';
                                  statusColor = Colors.cyanAccent;
                                } else {
                                  status = 'Scheduled';
                                  statusColor = Colors.white70;
                                }

                                return AnimationConfiguration.staggeredList(
                                  position: index,
                                  duration: const Duration(milliseconds: 500),
                                  child: SlideAnimation(
                                    verticalOffset: 50.0,
                                    child: FadeInAnimation(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white.withOpacity(0.05),
                                              Colors.white.withOpacity(0.02),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.1),
                                            width: 1,
                                          ),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(16),
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
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        '$team1 vs $team2',
                                                        style: GoogleFonts.poppins(
                                                          color: Colors.white,
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 12, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: statusColor.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(20),
                                                        border: Border.all(
                                                          color: statusColor.withOpacity(0.5),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        status,
                                                        style: GoogleFonts.poppins(
                                                          color: statusColor,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  match['tournamentName'],
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                if (displayTime != null)
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.schedule,
                                                          size: 16, color: Colors.white70),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        DateFormat('MMM d, y • h:mm a').format(displayTime),
                                                        style: GoogleFonts.poppins(
                                                          color: Colors.white70,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                const SizedBox(height: 8),
                                                if (!isLive && !isCompleted && countdownTime != null)
                                                  // Use the new CountdownText widget here!
                                                  CountdownText(
                                                    matchTime: matchStartTime,
                                                    tournamentTime: countdownTime,
                                                  ),
                                                if (isLive)
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.scoreboard,
                                                          size: 16, color: Colors.amberAccent),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Current: ${team1Scores[currentGame - 1]} - ${team2Scores[currentGame - 1]}',
                                                        style: GoogleFonts.poppins(
                                                          color: Colors.amberAccent,
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                if (isCompleted && match['winner'] != null)
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.emoji_events,
                                                          size: 16, color: Colors.greenAccent),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Winner: ${match['winner'] == (isDoubles ? 'team1' : 'player1') ? team1 : team2}',
                                                        style: GoogleFonts.poppins(
                                                          color: Colors.greenAccent,
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    } else {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.white60),
                            const SizedBox(height: 16),
                            Text(
                              'Authentication required',
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please log in as an official',
                              style: GoogleFonts.poppins(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}