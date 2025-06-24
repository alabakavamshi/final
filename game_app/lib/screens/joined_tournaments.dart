import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class JoinedTournamentsPage extends StatelessWidget {
  final String userId;

  const JoinedTournamentsPage({super.key, required this.userId});

  Future<void> _withdrawFromTournament(BuildContext context, Tournament tournament) async {
    try {
      // Fetch the current tournament document to get the participant entry
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournament.id)
          .get();
      final data = tournamentDoc.data();
      if (data == null) throw Exception('Tournament data not found');

      final participants = List<Map<String, dynamic>>.from(data['participants'] ?? []);
      final participantEntry = participants.firstWhere(
        (p) => p['id'] == userId,
        orElse: () => throw Exception('Participant not found'),
      );

      // Remove the participant entry using arrayRemove
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournament.id)
          .update({
        'participants': FieldValue.arrayRemove([participantEntry]),
      });

      toastification.show(
        context: context,
        type: ToastificationType.info,
        title: const Text('Withdrawn'),
        description: Text('You have withdrawn from "${tournament.name}".'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      print('Error withdrawing from tournament ${tournament.id}: $e');
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Withdrawal Failed'),
        description: Text('Failed to withdraw from tournament: $e'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Current userId: $userId'); // Debug log for userId

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        title: Text(
          'Joined Tournaments',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B263B), Color(0xFF0D1B2A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('tournaments').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (snapshot.hasError) {
            print('Error in StreamBuilder: ${snapshot.error}');
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: GoogleFonts.poppins(color: Colors.white70),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No tournaments available.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          final tournaments = snapshot.data!.docs
              .map((doc) {
                print('Tournament data: ${doc.data()}'); // Debug log
                return Tournament.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
              })
              .where((tournament) => tournament.participants.any((p) => p['id'] == userId))
              .toList();

          if (tournaments.isEmpty) {
            return Center(
              child: Text(
                'You haven\'t joined any tournaments yet.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: tournaments.length,
            itemBuilder: (context, index) {
              final tournament = tournaments[index];
              final isPast = tournament.endDate!.isBefore(DateTime.now());
              final isCreator = tournament.createdBy == userId;

              // Check if withdraw option should be available (e.g., at least 3 days before event)
              final withdrawDeadline = tournament.startDate.subtract(const Duration(days: 3));
              final canWithdraw = DateTime.now().isBefore(withdrawDeadline) && !isPast;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF1A237E),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  title: Text(
                                    'Tournament Details',
                                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Name: ${tournament.name}',
                                        style: GoogleFonts.poppins(color: Colors.white70),
                                      ),
                                      Text(
                                        'Location: ${tournament.venue},${tournament.city}',
                                        style: GoogleFonts.poppins(color: Colors.white70),
                                      ),
                                      Text(
                                        'Date: ${DateFormat('MMM dd, yyyy').format(tournament.startDate)}',
                                        style: GoogleFonts.poppins(color: Colors.white70),
                                      ),
                                      Text(
                                        'Entry Fee: ${tournament.entryFee.toStringAsFixed(0)}',
                                        style: GoogleFonts.poppins(color: Colors.white70),
                                      ),
                                      Text(
                                        'Participants: ${tournament.participants.length}',
                                        style: GoogleFonts.poppins(color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(
                                        'Close',
                                        style: GoogleFonts.poppins(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tournament.name.isNotEmpty ? tournament.name : 'Unnamed',
                                          style: GoogleFonts.poppins(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          if (isCreator)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.yellow.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Hosted by You',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (isPast)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              margin: const EdgeInsets.only(left: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Closed',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  color: Colors.white70,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Venue: ${tournament.venue.isNotEmpty ? tournament.venue : 'No Venue'}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                  ),
                                  Text(
                                    'City: ${tournament.city.isNotEmpty ? tournament.city : 'No City'}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                  ),
                                  Text(
                                    'Date: ${DateFormat('MMM dd, yyyy').format(tournament.startDate)}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                  ),
                                  Text(
                                    'Entry Fee: ${tournament.entryFee == 0.0 ? 'Free' : tournament.entryFee.toStringAsFixed(0)}',
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Column(
                                      children: [
                                        GestureDetector(
                                          onTap: isPast || !canWithdraw
                                              ? null
                                              : () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      backgroundColor: const Color(0xFF1A237E),
                                                      shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(12)),
                                                      title: Text(
                                                        'Confirm Withdrawal',
                                                        style: GoogleFonts.poppins(
                                                            color: Colors.white, fontWeight: FontWeight.w600),
                                                      ),
                                                      content: Text(
                                                        'Are you sure you want to withdraw from "${tournament.name}"?',
                                                        style: GoogleFonts.poppins(color: Colors.white70),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, false),
                                                          child: Text(
                                                            'Cancel',
                                                            style: GoogleFonts.poppins(color: Colors.white),
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, true),
                                                          child: Text(
                                                            'Withdraw',
                                                            style: GoogleFonts.poppins(color: Colors.redAccent),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (confirm == true) {
                                                    await _withdrawFromTournament(context, tournament);
                                                  }
                                                },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: isPast || !canWithdraw
                                                    ? [Colors.grey, Colors.grey]
                                                    : [Colors.redAccent, Colors.red],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isPast || !canWithdraw
                                                      ? Colors.grey.withOpacity(0.3)
                                                      : Colors.red.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              isPast || !canWithdraw ? 'Cannot Withdraw' : 'Withdraw',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (!isPast)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Can withdraw before ${DateFormat('MMM dd').format(withdrawDeadline)}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.05),
                                  Colors.transparent,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}