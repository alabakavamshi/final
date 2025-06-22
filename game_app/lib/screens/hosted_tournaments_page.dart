import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/screens/edit_tournament_page.dart';// Updated import
import 'package:game_app/screens/tournament_overview_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class HostedTournamentsPage extends StatelessWidget {
  final String userId;

  const HostedTournamentsPage({super.key, required this.userId});

  Future<void> _deleteTournament(String tournamentId) async {
    try {
      print('Attempting to delete tournament $tournamentId');
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .delete();
      print('Tournament $tournamentId deleted successfully');
    } catch (e) {
      print('Error deleting tournament $tournamentId: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        title: Text(
          'Hosted Tournaments',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .where('createdBy', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (snapshot.hasError) {
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
                'No tournaments hosted yet.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          final tournaments = snapshot.data!.docs
              .map((doc) => Tournament.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: tournaments.length,
            itemBuilder: (context, index) {
              final tournament = tournaments[index];
              final isPast = tournament.eventDate.isBefore(DateTime.now());

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
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
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            print('Card tapped for tournament ${tournament.id}');
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TournamentOverviewPage(tournament: tournament),
                              ),
                            );
                          },
                          child: Container(
                            color: Colors.transparent,
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
                                    if (isPast)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                  'Date: ${DateFormat('MMM dd, yyyy').format(tournament.eventDate)}',
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                ),
                                Text(
                                  'Entry Fee: ${tournament.entryFee == 0.0 ? 'Free' : tournament.entryFee.toStringAsFixed(0)}',
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.edit, size: 16, color: Colors.white),
                                label: Text(
                                  'Edit',
                                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent.withOpacity(0.8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  print('Edit button tapped for tournament ${tournament.id}');
                                  try {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditTournamentPage(tournament: tournament),
                                      ),
                                    );
                                  } catch (e) {
                                    print('Navigation error: $e');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Navigation failed: $e')),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.delete, size: 16, color: Colors.white),
                                label: Text(
                                  'Delete',
                                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () async {
                                  print('Delete button tapped for tournament ${tournament.id}');
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF1A237E),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      title: Text(
                                        'Confirm Deletion',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      content: Text(
                                        'Are you sure you want to delete "${tournament.name}"?',
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
                                            'Delete',
                                            style: GoogleFonts.poppins(color: Colors.redAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    try {
                                      await _deleteTournament(tournament.id);
                                      print('Showing success toast');
                                      toastification.show(
                                        context: context,
                                        type: ToastificationType.success,
                                        title: Text('Tournament Deleted'),
                                        description: Text('"${tournament.name}" has been deleted.'),
                                        autoCloseDuration: const Duration(seconds: 3),
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        alignment: Alignment.bottomCenter,
                                      );
                                    } catch (e) {
                                      print('Showing error toast');
                                      toastification.show(
                                        context: context,
                                        type: ToastificationType.error,
                                        title: Text('Deletion Failed'),
                                        description: Text('Failed to delete tournament: $e'),
                                        autoCloseDuration: const Duration(seconds: 3),
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        alignment: Alignment.bottomCenter,
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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