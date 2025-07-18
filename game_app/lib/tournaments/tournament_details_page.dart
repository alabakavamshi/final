import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/tournaments/match_details_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:toastification/toastification.dart';

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

class TournamentDetailsPage extends StatefulWidget {
  final Tournament tournament;
  final String creatorName;

  const TournamentDetailsPage({
    super.key,
    required this.tournament,
    required this.creatorName,
  });

  @override
  State<TournamentDetailsPage> createState() => _TournamentDetailsPageState();
}

class _TournamentDetailsPageState extends State<TournamentDetailsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _hasJoined = false;
  late TabController _tabController;
  Map<String, Map<String, dynamic>> _leaderboardData = {};
  late List<Map<String, dynamic>> _participants;
  late List<Map<String, dynamic>> _teams;
  late List<Map<String, dynamic>> _matches;
  bool _isUmpire = false;
  final GlobalKey _matchesListKey = GlobalKey();

  // Professional color palette
  final Color _primaryColor = const Color(0xFF0A2647);
  final Color _secondaryColor = const Color(0xFF144272);
  final Color _accentColor = const Color(0xFF2C74B3);
  final Color _textColor = Colors.white;
  final Color _secondaryText = Colors.white70;
  final Color _cardBackground = const Color(0xFF1A374D);
  final Color _successColor = const Color(0xFF4CAF50);
  final Color _warningColor = const Color(0xFFFFC107);
  final Color _errorColor = const Color(0xFFF44336);
  final Color _goldColor = const Color(0xFFFFD700);
  final Color _silverColor = const Color(0xFFC0C0C0);
  final Color _bronzeColor = const Color(0xFFCD7F32);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _participants = List.from(widget.tournament.participants);
    _teams = List.from(widget.tournament.teams);
    _matches = List.from(widget.tournament.matches);
    _checkIfJoined();
    _checkIfUmpire();
    _generateLeaderboardData();
    _listenToTournamentUpdates();
  }

  void _listenToTournamentUpdates() {
    FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data();
      if (data != null) {
        setState(() {
          _participants = List<Map<String, dynamic>>.from(data['participants'] ?? []);
          _teams = List<Map<String, dynamic>>.from(data['teams'] ?? []);
          _matches = List<Map<String, dynamic>>.from(data['matches'] ?? []);
          widget.tournament.profileImage = data['profileImage']?.toString();
        });
        _generateLeaderboardData();
      }
    }, onError: (e) {
      debugPrint('Error in tournament updates: $e');
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Update Error'),
        description: Text('Failed to update tournament data: $e'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: _errorColor,
        foregroundColor: _textColor,
        alignment: Alignment.bottomCenter,
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _checkIfJoined() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userId = authState.user.uid;
      setState(() {
        _hasJoined = _participants.any((p) => p['id'] == userId);
      });
    }
  }

  void _checkIfUmpire() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userEmail = authState.user.email;
      if (userEmail != null) {
        final umpireDoc = await FirebaseFirestore.instance
            .collection('umpire_credentials')
            .doc(userEmail)
            .get();
        if (mounted) {
          setState(() {
            _isUmpire = umpireDoc.exists;
          });
        }
      }
    }
  }

  Future<void> _uploadTournamentImage() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('tournament_images/${widget.tournament.id}.jpg');
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'profileImage': downloadUrl});

      if (mounted) {
        setState(() {
          widget.tournament.profileImage = downloadUrl;
        });
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Image Uploaded'),
          description: const Text('Tournament image updated successfully!'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _successColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Upload Failed'),
          description: Text('Failed to upload image: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showImageOptionsDialog(bool isCreator) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Image Options',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.visibility, color: _accentColor),
              title: Text(
                'View Image',
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showFullImageDialog();
              },
            ),
            if (isCreator)
              ListTile(
                leading: Icon(Icons.edit, color: _accentColor),
                title: Text(
                  'Edit Image',
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _uploadTournamentImage();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: _secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImageDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: widget.tournament.profileImage != null &&
                      widget.tournament.profileImage!.isNotEmpty
                  ? Image.network(
                      widget.tournament.profileImage!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/tournament_placholder.jpg',
                        fit: BoxFit.contain,
                      ),
                    )
                  : Image.asset(
                      'assets/tournament_placholder.jpg',
                      fit: BoxFit.contain,
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateLeaderboardData() async {
    if (_isDoublesTournament()) {
      final teamLeaderboardData = <String, Map<String, dynamic>>{};
      for (var team in _teams) {
        final teamId = team['teamId'] as String;
        final playerNames = team['players'].map((player) {
          final firstName = player['firstName'] ?? 'Unknown';
          final lastName = player['lastName']?.toString() ?? '';
          return '$firstName $lastName'.trim();
        }).toList();
        int teamScore = 0;
        for (var match in _matches) {
          if (match['completed'] == true && match['winner'] != null) {
            final winner = match['winner'] as String;
            final winningTeamIds = winner == 'team1'
                ? List<String>.from(match['team1Ids'])
                : List<String>.from(match['team2Ids']);
            final teamPlayerIds = team['players'].map((p) => p['id'] as String).toList();
            if (teamPlayerIds.every((id) => winningTeamIds.contains(id))) {
              teamScore += 1;
            }
          }
        }
        teamLeaderboardData[teamId] = {
          'name': playerNames.join(' & '),
          'score': teamScore,
        };
      }
      if (mounted) {
        setState(() {
          _leaderboardData = Map.fromEntries(
            teamLeaderboardData.entries.toList()
              ..sort((a, b) => b.value['score'].compareTo(a.value['score'])),
          );
        });
      }
    } else {
      final leaderboardData = <String, Map<String, dynamic>>{};
      for (var participant in _participants) {
        final userId = participant['id'] as String;
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final userData = userDoc.data() ?? await _createDefaultUser(userId);
        final firstName = userData['firstName']?.toString() ?? 'Unknown';
        final lastName = userData['lastName']?.toString() ?? '';
        final score = participant['score'] as int? ?? 0;
        leaderboardData[userId] = {
          'name': '$firstName $lastName'.trim(),
          'score': score,
        };
      }
      if (mounted) {
        setState(() {
          _leaderboardData = Map.fromEntries(
            leaderboardData.entries.toList()
              ..sort((a, b) => b.value['score'].compareTo(a.value['score'])),
          );
        });
      }
    }
  }

  Future<Map<String, dynamic>> _createDefaultUser(String userId) async {
    final defaultUser = {
      'createdAt': Timestamp.now(),
      'displayName': userId,
      'email': '$userId@unknown.com',
      'firstName': 'Unknown',
      'lastName': '',
      'gender': 'unknown',
      'phone': '',
      'profileImage': 'assets/default_profile.jpg',
      'updatedAt': Timestamp.now(),
    };
    await FirebaseFirestore.instance.collection('users').doc(userId).set(defaultUser);
    return defaultUser;
  }

  String? _getRequiredGender() {
    final gameFormat = widget.tournament.gameFormat.toLowerCase();
    if (gameFormat.contains("women's")) return 'female';
    if (gameFormat.contains("men's")) return 'male';
    return null;
  }

  bool _isDoublesTournament() {
    return widget.tournament.gameFormat.toLowerCase().contains('doubles');
  }

  Future<void> _generateTeams() async {
    if (!_isDoublesTournament()) {
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'teams': []});
      setState(() {
        _teams = [];
      });
      return;
    }

    final genderCounts = <String, int>{};
    for (var participant in _participants) {
      final gender = (participant['gender'] as String? ?? 'unknown').toLowerCase();
      genderCounts[gender] = (genderCounts[gender] ?? 0) + 1;
    }
    final maleCount = genderCounts['male'] ?? 0;
    final femaleCount = genderCounts['female'] ?? 0;
    final minPairs = maleCount < femaleCount ? maleCount : femaleCount;

    final males = _participants
        .where((p) => (p['gender'] as String? ?? 'unknown').toLowerCase() == 'male')
        .toList();
    final females = _participants
        .where((p) => (p['gender'] as String? ?? 'unknown').toLowerCase() == 'female')
        .toList();

    males.shuffle();
    females.shuffle();

    final newTeams = <Map<String, dynamic>>[];
    for (int i = 0; i < minPairs; i++) {
      final maleData = await _getUserData(males[i]['id']);
      final femaleData = await _getUserData(females[i]['id']);
      final team = {
        'teamId': 'team_${newTeams.length + 1}',
        'players': [
          {
            'id': males[i]['id'],
            'gender': 'male',
            'firstName': maleData['firstName']?.toString() ?? 'Unknown',
            'lastName': maleData['lastName']?.toString() ?? '',
          },
          {
            'id': females[i]['id'],
            'gender': 'female',
            'firstName': femaleData['firstName']?.toString() ?? 'Unknown',
            'lastName': femaleData['lastName']?.toString() ?? '',
          },
        ],
      };
      newTeams.add(team);
    }

    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .update({'teams': newTeams});

    if (mounted) {
      setState(() {
        _teams = newTeams;
      });
    }
  }

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data() ?? await _createDefaultUser(userId);
  }

  Future<String> _getDisplayName(String userId) async {
    final userData = await _getUserData(userId);
    final firstName = userData['firstName']?.toString() ?? 'Unknown';
    final lastName = userData['lastName']?.toString() ?? '';
    return '$firstName $lastName'.trim();
  }

  Future<void> _generateMatches() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final existingMatches = {
        for (var match in _matches) match['matchId'] as String: match
      };

      final newMatches = <Map<String, dynamic>>[];
      final updatedParticipants = _participants.map((p) => {...p, 'score': 0}).toList();

      DateTime matchStartDate = widget.tournament.startDate;
      final startHour = widget.tournament.startTime.hour;
      final startMinute = widget.tournament.startTime.minute;

      if (_isDoublesTournament()) {
        if (_teams.length < 2) {
          throw 'Need at least 2 teams to schedule matches.';
        }

        switch (widget.tournament.gameType.toLowerCase()) {
          case 'knockout':
            final shuffledTeams = List<Map<String, dynamic>>.from(_teams)..shuffle();
            for (int i = 0; i < shuffledTeams.length - 1; i += 2) {
              final team1 = shuffledTeams[i];
              final team2 = shuffledTeams[i + 1];
              final team1Names = team1['players']
                  .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                  .toList();
              final team2Names = team2['players']
                  .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                  .toList();

              final team1Ids = team1['players'].map((p) => p['id']).toList();
              final team2Ids = team2['players'].map((p) => p['id']).toList();

              final matchId = 'match_${team1Ids.join('_')}_vs_${team2Ids.join('_')}';

              final matchDateTime = DateTime(
                matchStartDate.year,
                matchStartDate.month,
                matchStartDate.day,
                startHour,
                startMinute,
              );

              if (existingMatches.containsKey(matchId)) {
                newMatches.add(existingMatches[matchId]!);
              } else {
                newMatches.add({
                  'matchId': matchId,
                  'round': 1,
                  'team1': team1Names,
                  'team2': team2Names,
                  'team1Ids': team1Ids,
                  'team2Ids': team2Ids,
                  'completed': false,
                  'winner': null,
                  'umpire': {'name': '', 'email': '', 'phone': ''},
                  'liveScores': {
                    'team1': [0, 0, 0],
                    'team2': [0, 0, 0],
                    'currentGame': 1,
                    'isLive': false,
                    'currentServer': 'team1',
                  },
                  'startTime': Timestamp.fromDate(matchDateTime),
                });
              }
              matchStartDate = matchStartDate.add(const Duration(days: 1));
            }
            break;

          case 'round-robin':
            final competitors = List<Map<String, dynamic>>.from(_teams);
            final numCompetitors = competitors.length;
            final isOdd = numCompetitors.isOdd;
            if (isOdd) {
              competitors.add({
                'teamId': 'bye',
                'players': [{'id': 'bye', 'firstName': 'Bye', 'lastName': ''}]
              });
            }
            final n = competitors.length;
            final totalRounds = n - 1;
            final matchesPerRound = n ~/ 2;

            final rounds = <List<Map<String, dynamic>>>[];
            for (var i = 0; i < totalRounds; i++) {
              rounds.add([]);
            }

            for (var round = 0; round < totalRounds; round++) {
              for (var i = 0; i < matchesPerRound; i++) {
                final team1 = competitors[i];
                final team2 = competitors[n - 1 - i];
                if (team1['teamId'] == 'bye' || team2['teamId'] == 'bye') continue;

                final team1Names = team1['players']
                    .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                    .toList();
                final team2Names = team2['players']
                    .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                    .toList();

                final team1Ids = team1['players'].map((p) => p['id']).toList();
                final team2Ids = team2['players'].map((p) => p['id']).toList();

                final matchId = 'match_${team1Ids.join('_')}_vs_${team2Ids.join('_')}';

                if (!existingMatches.containsKey(matchId)) {
                  rounds[round].add({
                    'matchId': matchId,
                    'round': round + 1,
                    'team1': team1Names,
                    'team2': team2Names,
                    'team1Ids': team1Ids,
                    'team2Ids': team2Ids,
                    'completed': false,
                    'winner': null,
                    'umpire': {'name': '', 'email': '', 'phone': ''},
                    'liveScores': {
                      'team1': [0, 0, 0],
                      'team2': [0, 0, 0],
                      'currentGame': 1,
                      'isLive': false,
                      'currentServer': 'team1',
                    },
                  });
                }
              }
              final temp = competitors.sublist(1, n - 1);
              competitors.setRange(1, n - 1, temp.sublist(1)..add(temp[0]));
            }

            final playerLastPlayDate = <String, DateTime>{};
            for (var round in rounds) {
              for (var match in round) {
                final team1Ids = List<String>.from(match['team1Ids']);
                final team2Ids = List<String>.from(match['team2Ids']);
                final allPlayerIds = [...team1Ids, ...team2Ids];

                DateTime candidateDate = matchStartDate;
                bool conflict;
                do {
                  conflict = false;
                  for (var playerId in allPlayerIds) {
                    final lastPlayDate = playerLastPlayDate[playerId];
                    if (lastPlayDate != null &&
                        candidateDate.difference(lastPlayDate).inDays.abs() < 1) {
                      conflict = true;
                      candidateDate = candidateDate.add(const Duration(days: 1));
                      break;
                    }
                  }
                } while (conflict);

                match['startTime'] = Timestamp.fromDate(DateTime(
                  candidateDate.year,
                  candidateDate.month,
                  candidateDate.day,
                  startHour,
                  startMinute,
                ));

                for (var playerId in allPlayerIds) {
                  playerLastPlayDate[playerId] = candidateDate;
                }

                newMatches.add(match);
                matchStartDate = candidateDate.add(const Duration(days: 1));
              }
            }
            break;

          default:
            throw 'Unsupported tournament type: ${widget.tournament.gameType}';
        }
      } else {
        if (_participants.length < 2) {
          throw 'Need at least 2 participants to schedule matches.';
        }

        switch (widget.tournament.gameType.toLowerCase()) {
          case 'knockout':
            final shuffledParticipants = List<Map<String, dynamic>>.from(_participants)..shuffle();
            for (int i = 0; i < shuffledParticipants.length - 1; i += 2) {
              final player1 = shuffledParticipants[i];
              final player2 = shuffledParticipants[i + 1];

              final matchId = 'match_${player1['id']}_vs_${player2['id']}';

              final matchDateTime = DateTime(
                matchStartDate.year,
                matchStartDate.month,
                matchStartDate.day,
                startHour,
                startMinute,
              );

              if (existingMatches.containsKey(matchId)) {
                newMatches.add(existingMatches[matchId]!);
              } else {
                newMatches.add({
                  'matchId': matchId,
                  'round': 1,
                  'player1': await _getDisplayName(player1['id']),
                  'player2': await _getDisplayName(player2['id']),
                  'player1Id': player1['id'],
                  'player2Id': player2['id'],
                  'completed': false,
                  'winner': null,
                  'umpire': {'name': '', 'email': '', 'phone': ''},
                  'liveScores': {
                    'player1': [0, 0, 0],
                    'player2': [0, 0, 0],
                    'currentGame': 1,
                    'isLive': false,
                    'currentServer': 'player1',
                  },
                  'startTime': Timestamp.fromDate(matchDateTime),
                });
              }
              matchStartDate = matchStartDate.add(const Duration(days: 1));
            }
            break;

          case 'round-robin':
            final competitors = List<Map<String, dynamic>>.from(_participants);
            final numCompetitors = competitors.length;
            final isOdd = numCompetitors.isOdd;
            if (isOdd) {
              competitors.add({'id': 'bye', 'gender': 'none', 'score': 0});
            }
            final n = competitors.length;
            final totalRounds = n - 1;
            final matchesPerRound = n ~/ 2;

            final rounds = <List<Map<String, dynamic>>>[];
            for (var i = 0; i < totalRounds; i++) {
              rounds.add([]);
            }

            for (var round = 0; round < totalRounds; round++) {
              for (var i = 0; i < matchesPerRound; i++) {
                final player1 = competitors[i];
                final player2 = competitors[n - 1 - i];
                if (player1['id'] == 'bye' || player2['id'] == 'bye') continue;

                final matchId = 'match_${player1['id']}_vs_${player2['id']}';

                if (!existingMatches.containsKey(matchId)) {
                  rounds[round].add({
                    'matchId': matchId,
                    'round': round + 1,
                    'player1': await _getDisplayName(player1['id']),
                    'player2': await _getDisplayName(player2['id']),
                    'player1Id': player1['id'],
                    'player2Id': player2['id'],
                    'completed': false,
                    'winner': null,
                    'umpire': {'name': '', 'email': '', 'phone': ''},
                    'liveScores': {
                      'player1': [0, 0, 0],
                      'player2': [0, 0, 0],
                      'currentGame': 1,
                      'isLive': false,
                      'currentServer': 'player1',
                    },
                  });
                }
              }
              final temp = competitors.sublist(1, n - 1);
              competitors.setRange(1, n - 1, temp.sublist(1)..add(temp[0]));
            }

            final playerLastPlayDate = <String, DateTime>{};
            for (var round in rounds) {
              for (var match in round) {
                final player1Id = match['player1Id'] as String;
                final player2Id = match['player2Id'] as String;

                DateTime candidateDate = matchStartDate;
                bool conflict;
                do {
                  conflict = false;
                  for (var playerId in [player1Id, player2Id]) {
                    final lastPlayDate = playerLastPlayDate[playerId];
                    if (lastPlayDate != null &&
                        candidateDate.difference(lastPlayDate).inDays.abs() < 1) {
                      conflict = true;
                      candidateDate = candidateDate.add(const Duration(days: 1));
                      break;
                    }
                  }
                } while (conflict);

                match['startTime'] = Timestamp.fromDate(DateTime(
                  candidateDate.year,
                  candidateDate.month,
                  candidateDate.day,
                  startHour,
                  startMinute,
                ));

                playerLastPlayDate[player1Id] = candidateDate;
                playerLastPlayDate[player2Id] = candidateDate;

                newMatches.add(match);
                matchStartDate = candidateDate.add(const Duration(days: 1));
              }
            }
            break;

          default:
            throw 'Unsupported tournament type: ${widget.tournament.gameType}';
        }
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'participants': updatedParticipants, 'matches': newMatches});

      if (mounted) {
        setState(() {
          _participants = updatedParticipants;
          _matches = newMatches;
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Matches Scheduled'),
          description: const Text('Match schedule has been successfully generated!'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _successColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to generate matches: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createManualMatch(
    dynamic competitor1,
    dynamic competitor2,
    DateTime matchDateTime,
  ) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final existingMatches = {
        for (var match in _matches) match['matchId'] as String: match
      };

      final isDoubles = _isDoublesTournament();
      String matchId;
      Map<String, dynamic> newMatch;

      if (isDoubles) {
        final team1Ids = competitor1['players'].map((p) => p['id']).toList();
        final team2Ids = competitor2['players'].map((p) => p['id']).toList();
        matchId = 'match_${team1Ids.join('_')}_vs_${team2Ids.join('_')}';

        if (existingMatches.containsKey(matchId)) {
          throw 'Match between these teams already exists.';
        }

        final team1Names = competitor1['players']
            .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
            .toList();
        final team2Names = competitor2['players']
            .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
            .toList();

        newMatch = {
          'matchId': matchId,
          'round': _matches.isNotEmpty ? (_matches.last['round'] ?? 1) : 1,
          'team1': team1Names,
          'team2': team2Names,
          'team1Ids': team1Ids,
          'team2Ids': team2Ids,
          'completed': false,
          'winner': null,
          'umpire': {'name': '', 'email': '', 'phone': ''},
          'liveScores': {
            'team1': [0, 0, 0],
            'team2': [0, 0, 0],
            'currentGame': 1,
            'isLive': false,
            'currentServer': 'team1',
          },
          'startTime': Timestamp.fromDate(matchDateTime),
        };
      } else {
        matchId = 'match_${competitor1['id']}_vs_${competitor2['id']}';

        if (existingMatches.containsKey(matchId)) {
          throw 'Match between these players already exists.';
        }

        newMatch = {
          'matchId': matchId,
          'round': _matches.isNotEmpty ? (_matches.last['round'] ?? 1) : 1,
          'player1': await _getDisplayName(competitor1['id']),
          'player2': await _getDisplayName(competitor2['id']),
          'player1Id': competitor1['id'],
          'player2Id': competitor2['id'],
          'completed': false,
          'winner': null,
          'umpire': {'name': '', 'email': '', 'phone': ''},
          'liveScores': {
            'player1': [0, 0, 0],
            'player2': [0, 0, 0],
            'currentGame': 1,
            'isLive': false,
            'currentServer': 'player1',
          },
          'startTime': Timestamp.fromDate(matchDateTime),
        };
      }

      final updatedMatches = List<Map<String, dynamic>>.from(_matches)..add(newMatch);

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'matches': updatedMatches});

      if (mounted) {
        setState(() {
          _matches = updatedMatches;
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Created'),
          description: const Text('Manual match has been successfully created!'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _successColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to create match: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showManualMatchDialog(bool isCreator) {
  if (!isCreator) return;

  final competitors = _isDoublesTournament() ? _teams : _participants;
  if (competitors.length < 2) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: const Text('Insufficient Competitors'),
      description: const Text('At least two teams or players are required to create a match.'),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: _errorColor,
      foregroundColor: _textColor,
      alignment: Alignment.bottomCenter,
    );
    return;
  }

  dynamic selectedCompetitor1;
  dynamic selectedCompetitor2;
  DateTime selectedDate = widget.tournament.startDate;
  TimeOfDay selectedTime = widget.tournament.startTime;

  showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Create Manual Match',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
              minWidth: 200.0, // Prevent overly narrow rendering
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DropdownButtonFormField<dynamic>(
                    decoration: InputDecoration(
                      labelText: _isDoublesTournament() ? 'Select Team 1' : 'Select Player 1',
                      labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor, width: 2),
                      ),
                      filled: true,
                      fillColor: _cardBackground.withOpacity(0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: _cardBackground,
                    isExpanded: true, // Ensures dropdown uses available width
                    items: competitors.map((competitor) {
                      return DropdownMenuItem(
                        value: competitor,
                        child: FutureBuilder<String>(
                          future: _isDoublesTournament()
                              ? Future.value(
                                  competitor['players']
                                      .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                                      .join(' & '),
                                )
                              : _getDisplayName(competitor['id']),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.connectionState == ConnectionState.waiting
                                  ? 'Loading...'
                                  : snapshot.data ?? competitor['id'],
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedCompetitor1 = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: DropdownButtonFormField<dynamic>(
                    decoration: InputDecoration(
                      labelText: _isDoublesTournament() ? 'Select Team 2' : 'Select Player 2',
                      labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor, width: 2),
                      ),
                      filled: true,
                      fillColor: _cardBackground.withOpacity(0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: _cardBackground,
                    isExpanded: true, // Ensures dropdown uses available width
                    items: competitors.map((competitor) {
                      return DropdownMenuItem(
                        value: competitor,
                        child: FutureBuilder<String>(
                          future: _isDoublesTournament()
                              ? Future.value(
                                  competitor['players']
                                      .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                                      .join(' & '),
                                )
                              : _getDisplayName(competitor['id']),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.connectionState == ConnectionState.waiting
                                  ? 'Loading...'
                                  : snapshot.data ?? competitor['id'],
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedCompetitor2 = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(
                    'Match Date: ${DateFormat('MMM dd, yyyy').format(selectedDate)}',
                    style: GoogleFonts.poppins(color: _textColor),
                  ),
                  trailing: Icon(Icons.calendar_today, color: _accentColor),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: widget.tournament.startDate,
                      lastDate: widget.tournament.endDate ?? DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate != null) {
                      setStateDialog(() {
                        selectedDate = pickedDate;
                      });
                    }
                  },
                ),
                ListTile(
                  title: Text(
                    'Match Time: ${selectedTime.format(context)}',
                    style: GoogleFonts.poppins(color: _textColor),
                  ),
                  trailing: Icon(Icons.access_time, color: _accentColor),
                  onTap: () async {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (pickedTime != null) {
                      setStateDialog(() {
                        selectedTime = pickedTime;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
          ),
          TextButton(
            onPressed: () {
              if (selectedCompetitor1 == null || selectedCompetitor2 == null) {
                toastification.show(
                  context: context,
                  type: ToastificationType.error,
                  title: const Text('Selection Required'),
                  description: const Text('Please select both competitors.'),
                  autoCloseDuration: const Duration(seconds: 2),
                  backgroundColor: _errorColor,
                  foregroundColor: _textColor,
                  alignment: Alignment.bottomCenter,
                );
                return;
              }
              if (selectedCompetitor1 == selectedCompetitor2) {
                toastification.show(
                  context: context,
                  type: ToastificationType.error,
                  title: const Text('Invalid Selection'),
                  description: const Text('Cannot create a match with the same competitor.'),
                  autoCloseDuration: const Duration(seconds: 2),
                  backgroundColor: _errorColor,
                  foregroundColor: _textColor,
                  alignment: Alignment.bottomCenter,
                );
                return;
              }
              Navigator.pop(context);
              final matchDateTime = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime.hour,
                selectedTime.minute,
              );
              _createManualMatch(selectedCompetitor1, selectedCompetitor2, matchDateTime);
            },
            child: Text(
              'Create',
              style: GoogleFonts.poppins(
                color: _successColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}


  Future<void> _deleteMatch(int matchIndex) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedMatches = List<Map<String, dynamic>>.from(_matches)..removeAt(matchIndex);
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'matches': updatedMatches});

      if (mounted) {
        setState(() {
          _matches = updatedMatches;
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Deleted'),
          description: const Text('The match has been successfully deleted.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _successColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Delete Failed'),
          description: Text('Failed to delete match: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showDeleteConfirmation(BuildContext context, int matchIndex) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Confirm Delete',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this match?',
          style: GoogleFonts.poppins(
            color: _secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: _secondaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMatch(matchIndex);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(
                color: _errorColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _getUserGender(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      return userDoc.data()?['gender'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<void> _joinTournament(BuildContext context) async {
    if (_isLoading) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Authentication Required'),
        description: const Text('Please sign in to join the tournament.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: _errorColor,
        foregroundColor: _textColor,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    final userId = authState.user.uid;
    if (widget.tournament.createdBy == userId) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Creator Cannot Join'),
        description: const Text('As the tournament creator, you cannot join as a participant.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: _errorColor,
        foregroundColor: _textColor,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    if (_hasJoined) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        title: const Text('Already Joined'),
        description: const Text('You have already joined this tournament!'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: _warningColor,
        foregroundColor: _textColor,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    final requiredGender = _getRequiredGender();
    final userGender = await _getUserGender(userId);
    if (userGender == null) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Gender Not Set'),
        description: const Text('Please set your gender in your profile to join a tournament.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: _errorColor,
        foregroundColor: _textColor,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    if (requiredGender != null && userGender.toLowerCase() != requiredGender) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Gender Mismatch'),
        description: Text(
          'This tournament (${widget.tournament.gameFormat}) is restricted to ${StringExtension(requiredGender).capitalize()} participants only.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: _errorColor,
        foregroundColor: _textColor,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    if (_isDoublesTournament() && requiredGender == null) {
      final genderCounts = <String, int>{};
      for (var participant in _participants) {
        final gender = (participant['gender'] as String? ?? 'unknown').toLowerCase();
        genderCounts[gender] = (genderCounts[gender] ?? 0) + 1;
      }
      final maleCount = genderCounts['male'] ?? 0;
      final femaleCount = genderCounts['female'] ?? 0;
      final userGenderLower = userGender.toLowerCase();

      if (userGenderLower == 'other') {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Invalid Gender for Doubles'),
          description: const Text(
            'Doubles tournaments require Male or Female participants for pairing.',
          ),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
        return;
      }

      if (userGenderLower == 'male' && maleCount >= femaleCount + 1) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Gender Balance Required'),
          description: const Text(
            'Doubles tournament requires equal Male and Female participants. Please wait for a Female participant to join.',
          ),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
        return;
      }

      if (userGenderLower == 'female' && femaleCount >= maleCount + 1) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Gender Balance Required'),
          description: const Text(
            'Doubles tournament requires equal Male and Female participants. Please wait for a Male participant to join.',
          ),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_participants.length >= widget.tournament.maxParticipants) {
        throw 'This tournament has reached its maximum participants.';
      }

      final newParticipant = {'id': userId, 'gender': userGender, 'score': 0};
      final updatedParticipants = List<Map<String, dynamic>>.from(_participants)..add(newParticipant);

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'participants': updatedParticipants});

      if (mounted) {
        setState(() {
          _participants = updatedParticipants;
          _hasJoined = true;
        });
        await _generateTeams();
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Joined Tournament'),
          description: Text('Successfully joined ${widget.tournament.name}!'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _successColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Join Failed'),
          description: Text('Failed to join tournament: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _withdrawFromTournament(BuildContext context) async {
    if (_isLoading) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final userId = authState.user.uid;

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedParticipants = _participants.where((p) => p['id'] != userId).toList();
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'participants': updatedParticipants});

      if (mounted) {
        setState(() {
          _participants = updatedParticipants;
          _hasJoined = false;
        });
        await _generateTeams();
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Withdrawn'),
          description: Text('You have successfully withdrawn from ${widget.tournament.name}.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _successColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Withdrawal Failed'),
          description: Text('Failed to withdraw from tournament: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: _errorColor,
          foregroundColor: _textColor,
          alignment: Alignment.bottomCenter,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateRange(DateTime startDate, DateTime? endDate) {
    final start = DateFormat('MMM dd, yyyy').format(startDate);
    if (endDate == null) return start;
    if (startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day) {
      return start;
    }
    return '$start - ${DateFormat('MMM dd, yyyy').format(endDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final isClosed = widget.tournament.endDate != null && widget.tournament.endDate!.isBefore(now);
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.uid : null;
    final isCreator = userId != null && widget.tournament.createdBy == userId;
    final withdrawDeadline = widget.tournament.startDate.subtract(const Duration(days: 3));
    final canWithdraw = now.isBefore(withdrawDeadline) && !isClosed;

    return Scaffold(
      backgroundColor: _primaryColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200.0,
              floating: false,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  widget.tournament.name,
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.tournament.profileImage != null && widget.tournament.profileImage!.isNotEmpty
                        ? Image.network(
                            widget.tournament.profileImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Image.asset(
                              'assets/tournament_placholder.jpg',
                              fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset(
                            'assets/tournament_placholder.jpg',
                            fit: BoxFit.cover,
                          ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _secondaryColor.withOpacity(0.7),
                            _primaryColor.withOpacity(0.7),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              backgroundColor: _secondaryColor,
              elevation: 10,
            ),
          ];
        },
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildTournamentOverviewCard(isCreator, isClosed),
                const SizedBox(height: 20),
                if (!isCreator && !_hasJoined && !isClosed)
                  _buildActionButton(
                    text: 'REGISTER NOW',
                    onPressed: _isLoading ? null : () => _joinTournament(context),
                  ),
                if (!isCreator && _hasJoined)
                  _buildWithdrawSection(canWithdraw, withdrawDeadline, context),
                const SizedBox(height: 20),
                _buildTournamentDetailsSection(),
                if (_hasJoined || isCreator) ...[
                  const SizedBox(height: 20),
                  if (isCreator)
                    _buildActionButton(
                      text: 'GENERATE MATCH SCHEDULE',
                      onPressed: isClosed || _isLoading ? null : _generateMatches,
                    ),
                  const SizedBox(height: 20),
                  _buildTournamentTabs(isCreator),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTournamentOverviewCard(bool isCreator, bool isClosed) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: _cardBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _showImageOptionsDialog(isCreator),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accentColor,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: widget.tournament.profileImage != null &&
                              widget.tournament.profileImage!.isNotEmpty
                          ? Image.network(
                              widget.tournament.profileImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Image.asset(
                                'assets/tournament_placholder.jpg',
                                fit: BoxFit.cover,
                              ),
                            )
                          : Image.asset(
                              'assets/tournament_placholder.jpg',
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.tournament.name.isNotEmpty ? widget.tournament.name : 'Unnamed',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: _textColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCreator)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _accentColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Created by You',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _textColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            widget.tournament.gameFormat.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _accentColor,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isClosed ? _errorColor.withOpacity(0.7) : _successColor.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isClosed ? 'Closed' : 'Open',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailItem(
              icon: Icons.calendar_month,
              title: 'TOURNAMENT DATES',
              value: _formatDateRange(widget.tournament.startDate, widget.tournament.endDate),
            ),
            _buildDetailItem(
              icon: Icons.location_pin,
              title: 'VENUE',
              value: (widget.tournament.venue.isNotEmpty && widget.tournament.city.isNotEmpty)
                  ? '${widget.tournament.venue}, ${widget.tournament.city}'
                  : 'No Location',
            ),
            _buildDetailItem(
              icon: Icons.people,
              title: 'PARTICIPANTS',
              value: '${_participants.length}/${widget.tournament.maxParticipants} registered',
            ),
            _buildDetailItem(
              icon: Icons.account_balance_wallet,
              title: 'ENTRY FEE',
              value: widget.tournament.entryFee == 0 ? 'FREE ENTRY' : '₹${widget.tournament.entryFee.toStringAsFixed(0)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: _secondaryText,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: _textColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        onPressed: _isLoading ? null : onPressed,
        label: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildWithdrawSection(bool canWithdraw, DateTime withdrawDeadline, BuildContext context) {
    return Column(
      children: [
        _buildActionButton(
          text: 'WITHDRAW REGISTRATION',
          onPressed: canWithdraw && !_isLoading ? () => _withdrawFromTournament(context) : null,
        ),
        if (!canWithdraw)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Withdrawal deadline: ${DateFormat('MMM dd, yyyy').format(withdrawDeadline)}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: _secondaryText,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTournamentDetailsSection() {
    const String defaultBadmintonRules = '''
1. Matches follow BWF regulations - best of 3 games to 21 points (rally point scoring)
2. Players must report 15 minutes before scheduled match time
3. Proper sports attire and non-marking shoes required
4. Tournament director reserves the right to modify rules as needed
5. Any disputes will be resolved by the tournament committee
''';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: _cardBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOURNAMENT DETAILS',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _accentColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailItem(
              icon: Icons.sports,
              title: 'COMPETITION FORMAT',
              value: widget.tournament.gameFormat,
            ),
            _buildDetailItem(
              icon: Icons.tour,
              title: 'TOURNAMENT TYPE',
              value: widget.tournament.gameType,
            ),
            _buildDetailItem(
              icon: Icons.person,
              title: 'ORGANIZER',
              value: widget.creatorName,
            ),
            const SizedBox(height: 16),
            Divider(
              color: _secondaryColor,
              thickness: 1,
              height: 1,
            ),
            const SizedBox(height: 16),
            Text(
              'TOURNAMENT RULES',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _accentColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (widget.tournament.rules != null && widget.tournament.rules!.isNotEmpty)
                  ? widget.tournament.rules!
                  : defaultBadmintonRules,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: _secondaryText,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTournamentTabs(bool isCreator) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: _secondaryColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _accentColor,
            ),
            labelColor: _textColor,
            unselectedLabelColor: _secondaryText,
            labelStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            tabs: const [
              Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Matches'))),
              Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Players'))),
              Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Standings'))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMatchesTab(isCreator),
              _buildPlayersTab(),
              _buildLeaderboardTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatchesTab(bool isCreator) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final isClosed = widget.tournament.endDate != null && widget.tournament.endDate!.isBefore(now);

    return Column(
      children: [
        if (isCreator && !isClosed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildActionButton(
              text: 'CREATE MANUAL MATCH',
              onPressed: _isLoading ? null : () => _showManualMatchDialog(isCreator),
            ),
          ),
        Expanded(
          child: _matches.isEmpty
              ? _buildEmptyState(
                  icon: Icons.schedule,
                  title: 'No Matches Scheduled',
                  description: isCreator
                      ? 'Generate or create matches to begin the tournament'
                      : 'Waiting for organizer to schedule matches',
                )
              : ListView.builder(
                  key: _matchesListKey,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _matches.length,
                  itemBuilder: (context, index) {
                    final match = _matches[index];
                    final isDoubles = _isDoublesTournament();
                    final isCompleted = match['completed'] == true;
                    final isLive = match['liveScores']?['isLive'] == true;
                    final currentGame = match['liveScores']?['currentGame'] ?? 1;

                    final team1Score = isDoubles
                        ? (match['liveScores']?['team1'] as List<dynamic>?)?.isNotEmpty == true
                            ? match['liveScores']['team1'][currentGame - 1] ?? 0
                            : 0
                        : (match['liveScores']?['player1'] as List<dynamic>?)?.isNotEmpty == true
                            ? match['liveScores']['player1'][currentGame - 1] ?? 0
                            : 0;
                    final team2Score = isDoubles
                        ? (match['liveScores']?['team2'] as List<dynamic>?)?.isNotEmpty == true
                            ? match['liveScores']['team2'][currentGame - 1] ?? 0
                            : 0
                        : (match['liveScores']?['player2'] as List<dynamic>?)?.isNotEmpty == true
                            ? match['liveScores']['player2'][currentGame - 1] ?? 0
                            : 0;

                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 400),
                      child: SlideAnimation(
                        verticalOffset: 30.0,
                        child: FadeInAnimation(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MatchDetailsPage(
                                    tournamentId: widget.tournament.id,
                                    match: match,
                                    matchIndex: index,
                                    isCreator: isCreator,
                                    isDoubles: isDoubles,
                                    isUmpire: _isUmpire,
                                    onDeleteMatch: () => _deleteMatch(index),
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: _cardBackground,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _secondaryColor.withOpacity(0.3),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(12),
                                        topRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _accentColor.withOpacity(0.2),
                                            border: Border.all(color: _accentColor),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${index + 1}',
                                              style: GoogleFonts.poppins(
                                                color: _accentColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '${isDoubles ? 'DOUBLES' : 'SINGLES'} • ROUND ${match['round'] ?? 1}',
                                            style: GoogleFonts.poppins(
                                              color: _accentColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (isCreator && !isLive && !isCompleted)
                                          IconButton(
                                            icon: Icon(Icons.delete, color: _errorColor),
                                            onPressed: () => _showDeleteConfirmation(context, index),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      children: [
                                        _buildMatchParticipant(
                                          name: isDoubles
                                              ? (match['team1'] as List<dynamic>).join(' & ')
                                              : match['player1'],
                                          isWinner: isCompleted && match['winner'] == (isDoubles ? 'team1' : 'player1'),
                                          score: team1Score,
                                          isLive: isLive,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'VS',
                                          style: GoogleFonts.poppins(
                                            color: _secondaryText,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildMatchParticipant(
                                          name: isDoubles
                                              ? (match['team2'] as List<dynamic>).join(' & ')
                                              : match['player2'],
                                          isWinner: isCompleted && match['winner'] == (isDoubles ? 'team2' : 'player2'),
                                          score: team2Score,
                                          isLive: isLive,
                                        ),
                                        if (match['startTime'] != null) ...[
                                          const SizedBox(height: 12),
                                          Divider(
                                            color: _secondaryColor,
                                            height: 1,
                                            thickness: 1,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(Icons.access_time, size: 16, color: _secondaryText),
                                              const SizedBox(width: 8),
                                              Text(
                                                DateFormat('MMM dd, hh:mm a').format(
                                                  (match['startTime'] as Timestamp).toDate(),
                                                ),
                                                style: GoogleFonts.poppins(
                                                  color: _secondaryText,
                                                                                                  fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (isCompleted || isLive)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 12),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isLive ? _warningColor.withOpacity(0.7) : _successColor.withOpacity(0.7),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                isLive ? 'LIVE' : 'COMPLETED',
                                                style: GoogleFonts.poppins(
                                                  color: _textColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                 ] ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMatchParticipant({
    required String name,
    required bool isWinner,
    required int score,
    required bool isLive,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.poppins(
              color: isWinner ? _successColor : _textColor,
              fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isLive || score > 0)
          Text(
            score.toString(),
            style: GoogleFonts.poppins(
              color: isWinner ? _successColor : _textColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
      ],
    );
  }

  Widget _buildPlayersTab() {
    return _isDoublesTournament()
        ? _buildTeamsList()
        : _buildParticipantsList();
  }

  Widget _buildParticipantsList() {
    return _participants.isEmpty
        ? _buildEmptyState(
            icon: Icons.people,
            title: 'No Participants',
            description: 'No players have joined this tournament yet.',
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _participants.length,
            itemBuilder: (context, index) {
              final participant = _participants[index];
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 400),
                child: SlideAnimation(
                  verticalOffset: 30.0,
                  child: FadeInAnimation(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _accentColor.withOpacity(0.2),
                              border: Border.all(color: _accentColor),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.poppins(
                                  color: _accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FutureBuilder<String>(
                              future: _getDisplayName(participant['id']),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? participant['id'],
                                  style: GoogleFonts.poppins(
                                    color: _textColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            ),
                          ),
                          Text(
                           StringExtension(participant['gender']?.toString() ?? '').capitalize(),
                            style: GoogleFonts.poppins(
                              color: _secondaryText,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildTeamsList() {
    return _teams.isEmpty
        ? _buildEmptyState(
            icon: Icons.group,
            title: 'No Teams',
            description: 'No teams have been formed yet.',
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _teams.length,
            itemBuilder: (context, index) {
              final team = _teams[index];
              final playerNames = team['players']
                  .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                  .join(' & ');
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 400),
                child: SlideAnimation(
                  verticalOffset: 30.0,
                  child: FadeInAnimation(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _accentColor.withOpacity(0.2),
                              border: Border.all(color: _accentColor),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.poppins(
                                  color: _accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              playerNames,
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildLeaderboardTab() {
    return _leaderboardData.isEmpty
        ? _buildEmptyState(
            icon: Icons.leaderboard,
            title: 'No Standings Available',
            description: 'Play some matches to see the leaderboard!',
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _leaderboardData.length,
            itemBuilder: (context, index) {
              final entry = _leaderboardData.entries.elementAt(index);
              final name = entry.value['name'];
              final score = entry.value['score'] as int;
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 400),
                child: SlideAnimation(
                  verticalOffset: 30.0,
                  child: FadeInAnimation(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == 0
                                  ? _goldColor.withOpacity(0.2)
                                  : index == 1
                                      ? _silverColor.withOpacity(0.2)
                                      : index == 2
                                          ? _bronzeColor.withOpacity(0.2)
                                          : _accentColor.withOpacity(0.2),
                              border: Border.all(
                                color: index == 0
                                    ? _goldColor
                                    : index == 1
                                        ? _silverColor
                                        : index == 2
                                            ? _bronzeColor
                                            : _accentColor,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.poppins(
                                  color: index == 0
                                      ? _goldColor
                                      : index == 1
                                          ? _silverColor
                                          : index == 2
                                              ? _bronzeColor
                                              : _accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            'Score: $score',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 60,
            color: _secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.poppins(
              color: _textColor,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.poppins(
              color: _secondaryText,
              fontWeight: FontWeight.w400,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}