import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/screens/match_details_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

const String _defaultBadmintonRules = '''
  1. Matches are best of 3 games, each played to 21 points with a 2-point lead required to win.
  2. A rally point system is used; a point is scored on every serve.
  3. Players change sides after each game and at 11 points in the third game.
  4. A 60-second break is allowed between games, and a 120-second break at 11 points in a game.
  5. Service must be diagonal, below the waist, and the shuttle must land within the opponent's court.
  6. Faults include: shuttle landing out of bounds, double hits, or player touching the net.
  7. Respect the umpire's decisions and maintain sportsmanship at all times.
  ''';

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
  List<Map<String, dynamic>> _participantDetails = [];
  bool _isUmpire = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _participants = List.from(widget.tournament.participants);
    _teams = List.from(widget.tournament.teams);
    _matches = List.from(widget.tournament.matches);
    _checkIfJoined();
    _checkIfUmpire();
    _fetchParticipantDetails();
    _generateLeaderboardData();
    _listenToTournamentUpdates();
  }

  void _listenToTournamentUpdates() {
    FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          print('Fetched End Date: ${data?['endDate']}'); // Debug print
          if (data != null) {
            setState(() {
              _participants = List.from(data['participants'] ?? []);
              _teams = List.from(data['teams'] ?? []);
              _matches = List.from(data['matches'] ?? []);
            });
            _fetchParticipantDetails();
            _generateLeaderboardData();
          }
        });
  }

  Future<void> _fetchParticipantDetails() async {
    try {
      final List<Map<String, dynamic>> details = [];
      for (var participant in _participants) {
        final userId = participant['id'] as String;
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final userData = userDoc.data();
        details.add({
          'firstName': userData?['firstName']?.toString() ?? 'Unknown',
          'lastName': userData?['lastName']?.toString() ?? '',
          'phone': userData?['phone']?.toString() ?? 'Not provided',
          'email': userData?['email']?.toString() ?? 'Not provided',
          'gender': userData?['gender']?.toString() ?? 'Unknown',
        });
      }
      setState(() {
        _participantDetails = details;
      });
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Error'),
        description: const Text('Failed to load participant details.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    }
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
        setState(() {
          _isUmpire = umpireDoc.exists;
        });
      }
    }
  }

  Future<void> _generateLeaderboardData() async {
    if (_isDoublesTournament()) {
      final teamLeaderboardData = <String, Map<String, dynamic>>{};
      for (var team in _teams) {
        final teamId = team['teamId'] as String;
        final playerNames =
            team['players'].map((player) {
              final firstName = player['firstName'] ?? 'Unknown';
              final lastName = player['lastName']?.toString() ?? '';
              return '$firstName $lastName'.trim();
            }).toList();
        int teamScore = 0;
        for (var match in _matches) {
          if (match['completed'] == true && match['winner'] != null) {
            final winner = match['winner'] as String;
            final winningTeamIds =
                winner == 'team1'
                    ? List<String>.from(match['team1Ids'])
                    : List<String>.from(match['team2Ids']);
            final teamPlayerIds =
                team['players'].map((p) => p['id'] as String).toList();
            if (teamPlayerIds.every((id) => winningTeamIds.contains(id))) {
              teamScore += 2;
            }
          }
        }
        teamLeaderboardData[teamId] = {
          'teamName': playerNames.join(' & '),
          'score': teamScore,
        };
      }
      setState(() {
        _leaderboardData = Map.fromEntries(
          teamLeaderboardData.entries.toList()
            ..sort((a, b) => b.value['score'].compareTo(a.value['score'])),
        );
      });
    } else {
      final leaderboardData = <String, Map<String, dynamic>>{};
      for (var participant in _participants) {
        final userId = participant['id'] as String;
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final userData = userDoc.data() ?? await _createDefaultUser(userId);
        final firstName = userData['firstName']?.toString() ?? 'Unknown';
        final lastName = userData['lastName']?.toString() ?? '';
        final score = participant['score'] as int? ?? 0;
        leaderboardData[userId] = {
          'displayName': '$firstName $lastName'.trim(),
          'score': score,
        };
      }
      setState(() {
        _leaderboardData = Map.fromEntries(
          leaderboardData.entries.toList()
            ..sort((a, b) => b.value['score'].compareTo(a.value['score'])),
        );
      });
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
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .set(defaultUser);
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

    final males =
        _participants
            .where(
              (p) =>
                  (p['gender'] as String? ?? 'unknown').toLowerCase() == 'male',
            )
            .toList();
    final females =
        _participants
            .where(
              (p) =>
                  (p['gender'] as String? ?? 'unknown').toLowerCase() ==
                  'female',
            )
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

    setState(() {
      _teams = newTeams;
    });
  }

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
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
      final newMatches = <Map<String, dynamic>>[];
      final updatedParticipants =
          _participants.map((p) => {...p, 'score': 0}).toList();

      if (_isDoublesTournament()) {
        if (_teams.length < 2) {
          throw 'Need at least 2 teams to schedule matches.';
        }
        switch (widget.tournament.gameType.toLowerCase()) {
          case 'knockout':
            final shuffledTeams = List<Map<String, dynamic>>.from(_teams)
              ..shuffle();
            for (int i = 0; i < shuffledTeams.length - 1; i += 2) {
              final team1 = shuffledTeams[i];
              final team2 = shuffledTeams[i + 1];
              final team1Names =
                  team1['players']
                      .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                      .toList();
              final team2Names =
                  team2['players']
                      .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                      .toList();
              newMatches.add({
                'round': 1,
                'team1': team1Names,
                'team2': team2Names,
                'team1Ids': team1['players'].map((p) => p['id']).toList(),
                'team2Ids': team2['players'].map((p) => p['id']).toList(),
                'completed': false,
                'winner': null,
                'umpire': {'name': '', 'email': '', 'phone': ''},
                'liveScores': {
                  'team1': [0, 0, 0],
                  'team2': [0, 0, 0],
                  'currentGame': 1,
                  'isLive': false,
                },
                'startTime': null,
              });
            }
            break;
          case 'round-robin':
            for (int i = 0; i < _teams.length; i++) {
              for (int j = i + 1; j < _teams.length; j++) {
                final team1 = _teams[i];
                final team2 = _teams[j];
                final team1Names =
                    team1['players']
                        .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                        .toList();
                final team2Names =
                    team2['players']
                        .map((p) => '${p['firstName']} ${p['lastName']}'.trim())
                        .toList();
                newMatches.add({
                  'round': 1,
                  'team1': team1Names,
                  'team2': team2Names,
                  'team1Ids': team1['players'].map((p) => p['id']).toList(),
                  'team2Ids': team2['players'].map((p) => p['id']).toList(),
                  'completed': false,
                  'winner': null,
                  'umpire': {'name': '', 'email': '', 'phone': ''},
                  'liveScores': {
                    'team1': [0, 0, 0],
                    'team2': [0, 0, 0],
                    'currentGame': 1,
                    'isLive': false,
                  },
                  'startTime': null,
                });
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
            final shuffledParticipants =
                List<Map<String, dynamic>>.from(_participants)..shuffle();
            for (int i = 0; i < shuffledParticipants.length - 1; i += 2) {
              final player1 = shuffledParticipants[i];
              final player2 = shuffledParticipants[i + 1];
              newMatches.add({
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
                },
                'startTime': null,
              });
            }
            break;
          case 'round-robin':
            for (int i = 0; i < _participants.length; i++) {
              for (int j = i + 1; j < _participants.length; j++) {
                final player1 = _participants[i];
                final player2 = _participants[j];
                newMatches.add({
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
                  },
                  'startTime': null,
                });
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

      setState(() {
        _participants = updatedParticipants;
        _matches = newMatches;
      });

      await _generateLeaderboardData();

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Matches Scheduled'),
        description: const Text(
          'Match schedule has been successfully generated!',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Error'),
        description: Text('Failed to generate matches: $e'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteMatch(int matchIndex) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedMatches = List<Map<String, dynamic>>.from(_matches)
        ..removeAt(matchIndex);

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'matches': updatedMatches});

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
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Delete Failed'),
        description: Text('Failed to delete match: $e'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String?> _getUserGender(String userId) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();
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
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
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
        description: const Text(
          'As the tournament creator, you cannot join as a participant.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
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
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
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
        description: const Text(
          'Please set your gender in your profile to join a tournament.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
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
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
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
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
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
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
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
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
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
      final updatedParticipants = List<Map<String, dynamic>>.from(_participants)
        ..add(newParticipant);

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'participants': updatedParticipants});

      setState(() {
        _participants = updatedParticipants;
        _hasJoined = true;
      });

      await _generateTeams();
      await _fetchParticipantDetails();
      await _generateLeaderboardData();

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Joined Tournament'),
        description: Text('Successfully joined ${widget.tournament.name}!'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Join Failed'),
        description: Text('Failed to join tournament: $e'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
      final updatedParticipants =
          _participants.where((p) => p['id'] != userId).toList();
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'participants': updatedParticipants});

      setState(() {
        _participants = updatedParticipants;
        _hasJoined = false;
      });

      await _generateTeams();
      await _fetchParticipantDetails();
      await _generateLeaderboardData();

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Withdrawn'),
        description: Text(
          'You have successfully withdrawn from ${widget.tournament.name}.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Withdrawal Failed'),
        description: Text('Failed to withdraw from tournament: $e'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime(2025, 6, 22, 15, 10, 0); // 08:40 PM IST, June 22, 2025
    print('Current Time: $now'); // Debug print
    print('End Date: ${widget.tournament.endDate}'); // Debug print
    final isClosed = widget.tournament.endDate != null && widget.tournament.endDate!.isBefore(now);
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.uid : null;
    final isCreator = userId != null && widget.tournament.createdBy == userId;
    final withdrawDeadline = widget.tournament.startDate.subtract(
      const Duration(days: 3),
    );
    final canWithdraw = DateTime.now().isBefore(withdrawDeadline) && !isClosed;

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
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: AnimationConfiguration.synchronized(
                    duration: const Duration(milliseconds: 1000),
                    child: Column(
                      children: AnimationConfiguration.toStaggeredList(
                        duration: const Duration(milliseconds: 500),
                        childAnimationBuilder: (child) => SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(child: child),
                        ),
                        children: [
                          _buildHeaderCard(isCreator),
                          Center(
                            child: Column(
                              children: [
                                const SizedBox(height: 20),
                                if (!isCreator && !_hasJoined)
                                  _buildModernButton(
                                    text: isClosed
                                        ? 'Tournament Closed'
                                        : 'Join Now',
                                    gradient: LinearGradient(
                                      colors: isClosed
                                          ? [
                                              Colors.grey.shade700,
                                              Colors.grey.shade600,
                                            ]
                                          : [
                                              Colors.cyanAccent,
                                              Colors.blueAccent,
                                            ],
                                    ),
                                    isLoading: _isLoading,
                                    onPressed: isClosed
                                        ? null
                                        : () => _joinTournament(context),
                                  ),
                                if (!isCreator && _hasJoined)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Column(
                                      children: [
                                        _buildModernButton(
                                          text: 'Withdraw',
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.redAccent,
                                              Colors.red,
                                            ],
                                          ),
                                          isLoading: _isLoading,
                                          onPressed: canWithdraw
                                              ? () => _withdrawFromTournament(context)
                                              : null,
                                          isDisabled: !canWithdraw,
                                          disabledTooltip:
                                              'Withdraw deadline passed on ${DateFormat('MMM dd').format(withdrawDeadline)}',
                                        ),
                                        if (!canWithdraw)
                                          const SizedBox(height: 8),
                                        if (!canWithdraw)
                                          Text(
                                            'Withdraw deadline passed on ${DateFormat('MMM dd').format(withdrawDeadline)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.white54,
                                            ),

                                        
                                          ),
                                          SizedBox(height: 4),
                                          Text('Can withdraw until ${DateFormat('MMM dd').format(withdrawDeadline)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.white54,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_hasJoined || isCreator)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        Divider(
                          color: Colors.white.withOpacity(0.2),
                          thickness: 1.5,
                        ),
                        const SizedBox(height: 20),
                        if (isCreator)
                          _buildModernButton(
                            text: 'Generate Match Schedule',
                            gradient: LinearGradient(
                              colors: isClosed
                                  ? [
                                      Colors.grey.shade700,
                                      Colors.grey.shade600,
                                    ]
                                  : [Colors.cyanAccent, Colors.blueAccent],
                            ),
                            isLoading: _isLoading,
                            onPressed: isClosed ? null : () => _generateMatches(),
                          ),
                        const SizedBox(height: 20),
                        TabBar(
                          controller: _tabController,
                          tabs: [
                            Tab(
                              child: Text(
                                'Matches',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Tab(
                              child: Text(
                                'Leaderboard',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                          indicatorColor: Colors.cyanAccent,
                          indicatorWeight: 3,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              if (_hasJoined || isCreator)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 400, // Fixed height to prevent overflow
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMatchesTab(isCreator),
                        _buildLeaderboardTab(),
                      ],
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required String text,
    required LinearGradient gradient,
    required bool isLoading,
    VoidCallback? onPressed,
    bool isDisabled = false,
    String? disabledTooltip,
  }) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Tooltip(
            message: isDisabled ? disabledTooltip ?? 'Action disabled' : '',
            child: GestureDetector(
              onTap: isLoading || onPressed == null || isDisabled ? null : onPressed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                decoration: BoxDecoration(
                  gradient: isDisabled
                      ? LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade600])
                      : gradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
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
                          color: isDisabled ? Colors.grey.shade400 : Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isCreator) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.sports_tennis,
                    color: Colors.cyanAccent,
                    size: 36,
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
                              widget.tournament.name.isNotEmpty
                                  ? widget.tournament.name
                                  : 'Unnamed',
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCreator)
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.cyanAccent,
                                        Colors.blueAccent,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.cyanAccent.withOpacity(0.3),
                                        blurRadius: 5,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    'Created by You',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                               
                              ],
                            ),
                             IconButton(
                                  icon: const Icon(Icons.info_outline, color: Colors.white70, size: 25),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TournamentInfoPage(
                                          tournament: widget.tournament,
                                          creatorName: widget.creatorName,
                                          participantDetails: _participantDetails,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.tournament.gameFormat,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.cyanAccent,
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
    );
  }

  Widget _buildMatchesTab(bool isCreator) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: AnimationConfiguration.toStaggeredList(
        duration: const Duration(milliseconds: 500),
        childAnimationBuilder: (child) => SlideAnimation(
          verticalOffset: 50.0,
          child: FadeInAnimation(child: child),
        ),
        children: [
          if (_matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                isCreator
                    ? 'No matches scheduled yet. Use the button above to generate the match schedule.'
                    : 'No matches scheduled yet. Waiting for the tournament creator to set up the schedule.',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._matches.asMap().entries.map((entry) {
              final index = entry.key;
              final match = entry.value;
              final isCompleted = match['completed'] == true;
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatchDetailsPage(
                        tournamentId: widget.tournament.id,
                        match: match,
                        matchIndex: index,
                        isCreator: isCreator,
                        isDoubles: _isDoublesTournament(),
                        isUmpire: _isUmpire,
                        onDeleteMatch: () => _showDeleteConfirmationDialog(index),
                      ),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            match['team1'] != null
                                ? 'Team Match: Round ${match['round']}'
                                : 'Singles Match: Round ${match['round']}',
                            style: GoogleFonts.poppins(
                              color: Colors.cyanAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isCreator)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _showDeleteConfirmationDialog(index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        match['team1'] != null
                            ? 'Team 1: ${match['team1'].join(', ')} vs Team 2: ${match['team2'].join(', ')}'
                            : 'Player 1: ${match['player1']} vs Player 2: ${match['player2']}',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      if (isCompleted)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Winner: ${match['winner'] == 'team1' || match['winner'] == 'player1' ? (match['team1'] ?? match['player1']) : (match['team2'] ?? match['player2'])}',
                            style: GoogleFonts.poppins(
                              color: Colors.greenAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (match['liveScores']?['isLive'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Live: Game ${match['liveScores']['currentGame']} - ${match['team1'] != null ? 'Team 1' : 'Player 1'}: ${match['liveScores']['team1']?[match['liveScores']['currentGame'] - 1] ?? 0} vs ${match['team1'] != null ? 'Team 2' : 'Player 2'}: ${match['liveScores']['team2']?[match['liveScores']['currentGame'] - 1] ?? 0}',
                            style: GoogleFonts.poppins(
                              color: Colors.yellowAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: AnimationConfiguration.toStaggeredList(
        duration: const Duration(milliseconds: 500),
        childAnimationBuilder: (child) => SlideAnimation(
          verticalOffset: 50.0,
          child: FadeInAnimation(child: child),
        ),
        children: [
          if (_leaderboardData.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No leaderboard data available.',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._leaderboardData.entries.toList().asMap().entries.map(
                  (entry) {
                    final index = entry.key;
                    final data = entry.value.value;
                    final displayName =
                        data['teamName'] ?? data['displayName'] as String;
                    final score = data['score'] as int;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: index < 3
                            ? Colors.cyanAccent.withOpacity(
                                index == 0
                                    ? 0.15
                                    : index == 1
                                        ? 0.1
                                        : 0.05,
                              )
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: index < 3
                              ? Colors.cyanAccent.withOpacity(0.5)
                              : Colors.cyanAccent.withOpacity(0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
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
                              color: index < 3
                                  ? Colors.cyanAccent.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.1),
                              border: Border.all(
                                color: index < 3
                                    ? Colors.cyanAccent
                                    : Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.poppins(
                                  color: index < 3
                                      ? Colors.cyanAccent
                                      : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              displayName,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '$score pts',
                            style: GoogleFonts.poppins(
                              color: Colors.cyanAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(int matchIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Deletion',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete this match? This action cannot be undone.',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMatch(matchIndex);
            },
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
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

// New Page: TournamentInfoPage
class TournamentInfoPage extends StatelessWidget {
  final Tournament tournament;
  final String creatorName;
  final List<Map<String, dynamic>> participantDetails;

  const TournamentInfoPage({
    super.key,
    required this.tournament,
    required this.creatorName,
    required this.participantDetails,
  });

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
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tournament Info',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildDetailSection(
                        title: 'Tournament Details',
                        children: [
                          _buildDetailRow(
                            icon: Icons.sports_tennis,
                            label: 'Play Style',
                            value: tournament.gameFormat,
                          ),
                          _buildDetailRow(
                            icon: Icons.location_on,
                            label: 'Venue',
                            value: (tournament.venue.isNotEmpty && tournament.city.isNotEmpty)
                                ? '${tournament.venue}, ${tournament.city}'
                                : 'No Location',
                          ),
                          _buildDetailRow(
                            icon: Icons.calendar_today,
                            label: 'Date',
                            value: _formatDateRange(tournament.startDate, tournament.endDate),
                          ),
                          _buildDetailRow(
                            icon: Icons.account_balance_wallet,
                            label: 'Entry Fee',
                            value: tournament.entryFee == 0.0
                                ? 'Free'
                                : '₹${tournament.entryFee.toStringAsFixed(0)}',
                          ),
                          _buildDetailRow(
                            icon: Icons.people,
                            label: 'Max Participants',
                            value: '${tournament.maxParticipants}',
                          ),
                          _buildDetailRow(
                            icon: Icons.person,
                            label: 'Created By',
                            value: creatorName,
                          ),
                          _buildDetailRow(
                            icon: Icons.description,
                            label: 'Game Type',
                            value: tournament.gameType,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildDetailSection(
                        title: 'Participants Details',
                        children: [
                          if (participantDetails.isEmpty)
                            Text(
                              'No participants yet.',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            )
                          else
                            ...participantDetails.asMap().entries.map(
                                  (entry) {
                                    final index = entry.key;
                                    final details = entry.value;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Participant ${index + 1}: ',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                RichText(
                                                  text: TextSpan(
                                                    children: [
                                                      TextSpan(
                                                        text: '${details['firstName']} ${details['lastName']}',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 14,
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: ' (${StringExtension(details['gender']).capitalize()})',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 12,
                                                          color: Colors.cyanAccent,
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Phone: ${details['phone']}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                Text(
                                                  'Email: ${details['email']}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildDetailSection(
                        title: 'Rules',
                        children: [
                          Text(
                            tournament.rules.isNotEmpty
                                ? tournament.rules
                                : _defaultBadmintonRules,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white70,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 18),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateRange(DateTime startDate, DateTime? endDate) {
    if (endDate == null) {
      return DateFormat('MMM dd, yyyy').format(startDate);
    }
    final startDateOnly = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
    if (startDateOnly == endDateOnly) {
      return DateFormat('MMM dd, yyyy').format(startDate);
    }
    if (startDate.year == endDate.year) {
      return '${DateFormat('MMM dd').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
    }
    return '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
  }
}