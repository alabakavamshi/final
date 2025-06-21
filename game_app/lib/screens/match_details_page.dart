import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class MatchDetailsPage extends StatefulWidget {
  final String tournamentId;
  final Map<String, dynamic> match;
  final int matchIndex;
  final bool isCreator;
  final bool isDoubles;
  final bool isUmpire;
  final VoidCallback onDeleteMatch;

  const MatchDetailsPage({
    super.key,
    required this.tournamentId,
    required this.match,
    required this.matchIndex,
    required this.isCreator,
    required this.isDoubles,
    required this.isUmpire,
    required this.onDeleteMatch,
  });

  @override
  State<MatchDetailsPage> createState() => _MatchDetailsPageState();
}

class _MatchDetailsPageState extends State<MatchDetailsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late Map<String, dynamic> _match;
  final _umpireNameController = TextEditingController();
  final _umpireEmailController = TextEditingController();
  final _umpirePhoneController = TextEditingController();
  late String _initialUmpireName;
  late String _initialUmpireEmail;
  late String _initialUmpirePhone;
  String? _currentServer;
  String? _lastServer;
  int? _lastTeam1Score;
  int? _lastTeam2Score;
  bool _showPlusOneTeam1 = false;
  bool _showPlusOneTeam2 = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _debounceTimer;
  Timer? _countdownTimer;
  String? _countdown;
  Timestamp? _eventDate;

  @override
  void initState() {
    super.initState();
    _match = Map.from(widget.match);
    _umpireNameController.text = _match['umpire']?['name'] ?? '';
    _umpireEmailController.text = _match['umpire']?['email'] ?? '';
    _umpirePhoneController.text = _match['umpire']?['phone'] ?? '';
    _initialUmpireName = _umpireNameController.text;
    _initialUmpireEmail = _umpireEmailController.text;
    _initialUmpirePhone = _umpirePhoneController.text;
    _lastTeam1Score = _getCurrentScore(true);
    _lastTeam2Score = _getCurrentScore(false);
    _initializeServer();
    _listenToMatchUpdates();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _startCountdown();
  }

  @override
  void dispose() {
    _umpireNameController.dispose();
    _umpireEmailController.dispose();
    _umpirePhoneController.dispose();
    _animationController.dispose();
    _debounceTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() async {
    if (_match['liveScores']?['isLive'] == true ||
        _match['completed'] == true) {
      setState(() {
        _countdown = null;
      });
      _countdownTimer?.cancel();
      return;
    }

    final tournamentDoc =
        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .get();
    final eventDate = tournamentDoc.data()?['eventDate'] as Timestamp?;

    setState(() {
      _eventDate = eventDate;
      _countdown = eventDate == null ? 'Start time not scheduled' : null;
    });

    if (eventDate == null) {
      _countdownTimer?.cancel();
      return;
    }

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final startTime = eventDate.toDate();
      final difference = startTime.difference(now);

      if (difference.isNegative) {
        setState(() {
          _countdown = 'Match should have started';
        });
        timer.cancel();
      } else if (difference.inHours >= 24) {
        final days = difference.inDays;
        final hours = difference.inHours % 24;
        setState(() {
          _countdown = '${days}d ${hours}h';
        });
      } else {
        final hours = difference.inHours;
        final minutes = difference.inMinutes % 60;
        final seconds = difference.inSeconds % 60;
        setState(() {
          _countdown = '${hours}h ${minutes}m ${seconds}s';
        });
      }
    });
  }

  Future<void> _updateEventDate() async {
    if (_isLoading ||
        _match['liveScores']?['isLive'] == true ||
        _match['completed'] == true) {
      return;
    }

    final now = DateTime.now();
    final initialDate = _eventDate?.toDate() ?? now;
    final newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );

    if (newDate == null) return;

    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (newTime == null) return;

    final newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'eventDate': Timestamp.fromDate(newDateTime)});

      setState(() {
        _eventDate = Timestamp.fromDate(newDateTime);
        _startCountdown();
      });

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Start Time Updated'),
        description: const Text('Tournament start time has been updated.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Update Failed'),
        description: Text('Failed to update start time: $e'),
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

  void _initializeServer() {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final team1Scores = List<int>.from(
      liveScores[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0],
    );
    final team2Scores = List<int>.from(
      liveScores[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0],
    );

    if (!liveScores.containsKey('isLive') || !liveScores['isLive']) {
      _currentServer = widget.isDoubles ? 'team1' : 'player1';
      _lastServer = _currentServer;
    } else if (liveScores['currentServer'] != null) {
      _currentServer = liveScores['currentServer'];
      _lastServer = _currentServer;
    } else {
      String? lastSetWinner;
      for (int i = 0; i < currentGame - 1; i++) {
        if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
            team1Scores[i] == 30) {
          lastSetWinner = widget.isDoubles ? 'team1' : 'player1';
        } else if (team2Scores[i] >= 21 &&
                (team2Scores[i] - team1Scores[i]) >= 2 ||
            team2Scores[i] == 30) {
          lastSetWinner = widget.isDoubles ? 'team2' : 'player2';
        }
      }
      if (team1Scores[currentGame - 1] == 0 &&
          team2Scores[currentGame - 1] == 0 &&
          lastSetWinner != null) {
        _currentServer = lastSetWinner;
        _lastServer = _currentServer;
      } else if (_lastTeam1Score != null && _lastTeam2Score != null) {
        if (team1Scores[currentGame - 1] > _lastTeam1Score!) {
          _currentServer = widget.isDoubles ? 'team1' : 'player1';
          _lastServer = _currentServer;
        } else if (team2Scores[currentGame - 1] > _lastTeam2Score!) {
          _currentServer = widget.isDoubles ? 'team2' : 'player2';
          _lastServer = _currentServer;
        } else {
          _currentServer =
              _lastServer ?? (widget.isDoubles ? 'team1' : 'player1');
        }
      } else {
        _currentServer = widget.isDoubles ? 'team1' : 'player1';
        _lastServer = _currentServer;
      }
    }
  }

  int _getCurrentScore(bool isTeam1) {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
      liveScores[isTeam1
              ? (widget.isDoubles ? 'team1' : 'player1')
              : (widget.isDoubles ? 'team2' : 'player2')] ??
          [0, 0, 0],
    );
    return scores[currentGame - 1];
  }

  String _getServiceCourt(bool isTeam1) {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
      liveScores[isTeam1
              ? (widget.isDoubles ? 'team1' : 'player1')
              : (widget.isDoubles ? 'team2' : 'player2')] ??
          [0, 0, 0],
    );
    return scores[currentGame - 1].isEven ? 'Right' : 'Left';
  }

  void _listenToMatchUpdates() {
    FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data != null && data['matches'] != null && mounted) {
            final matches = List<Map<String, dynamic>>.from(data['matches']);
            if (matches.length > widget.matchIndex) {
              final newMatch = matches[widget.matchIndex];
              final newTeam1Score = _getCurrentScoreFromMatch(newMatch, true);
              final newTeam2Score = _getCurrentScoreFromMatch(newMatch, false);
              if (newTeam1Score > (_lastTeam1Score ?? 0)) {
                setState(() {
                  _showPlusOneTeam1 = true;
                  _animationController.forward().then((_) {
                    _animationController.reverse();
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        setState(() => _showPlusOneTeam1 = false);
                      }
                    });
                  });
                });
              } else if (newTeam2Score > (_lastTeam2Score ?? 0)) {
                setState(() {
                  _showPlusOneTeam2 = true;
                  _animationController.forward().then((_) {
                    _animationController.reverse();
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        setState(() => _showPlusOneTeam2 = false);
                      }
                    });
                  });
                });
              }
              setState(() {
                _match = newMatch;
                _eventDate = data['eventDate'] as Timestamp?;
                _umpireNameController.text = _match['umpire']?['name'] ?? '';
                _umpireEmailController.text = _match['umpire']?['email'] ?? '';
                _umpirePhoneController.text = _match['umpire']?['phone'] ?? '';
                _initialUmpireName = _umpireNameController.text;
                _initialUmpireEmail = _umpireEmailController.text;
                _initialUmpirePhone = _umpirePhoneController.text;
                _lastTeam1Score = newTeam1Score;
                _lastTeam2Score = newTeam2Score;
                _initializeServer();
                _startCountdown();
              });
            }
          }
        });
  }

  int _getCurrentScoreFromMatch(Map<String, dynamic> match, bool isTeam1) {
    final liveScores = match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
      liveScores[isTeam1
              ? (widget.isDoubles ? 'team1' : 'player1')
              : (widget.isDoubles ? 'team2' : 'player2')] ??
          [0, 0, 0],
    );
    return scores[currentGame - 1];
  }

  bool get _isUmpireButtonDisabled {
    final name = _umpireNameController.text.trim();
    final email = _umpireEmailController.text.trim();
    final phone = _umpirePhoneController.text.trim();
    final isLive = _match['liveScores']?['isLive'] == true;
    return isLive ||
        (name.isEmpty && email.isEmpty && phone.isEmpty) ||
        (name == _initialUmpireName &&
            email == _initialUmpireEmail &&
            phone == _initialUmpirePhone);
  }

  Future<void> _fetchUserData(String email) async {
    if (_match['liveScores']?['isLive'] == true) return;
    if (email.isEmpty ||
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      return;
    }

    try {
      final query =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .where('role', isEqualTo: 'umpire')
              .limit(1)
              .get();

      if (query.docs.isNotEmpty && mounted) {
        final userData = query.docs.first.data();
        setState(() {
          _umpireNameController.text =
              '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                  .trim();
          _umpirePhoneController.text = userData['phone'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  Future<void> _updateUmpireDetails() async {
    if (_isLoading || _isUmpireButtonDisabled) return;
    if (_match['liveScores']?['isLive'] == true) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Update Not Allowed'),
        description: const Text(
          'Umpire details cannot be updated after the match has started.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    final name = _umpireNameController.text.trim();
    final email = _umpireEmailController.text.trim();
    final phone = _umpirePhoneController.text.trim();

    if (email.isEmpty) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Email Required'),
        description: const Text('Please enter an email address.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Invalid Email'),
        description: const Text('Please enter a valid email address.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    if (phone.isNotEmpty && !RegExp(r'^\+\d{11,12}$').hasMatch(phone)) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Invalid Phone'),
        description: const Text(
          'Please enter a valid phone number with country code (e.g., +919346297919).',
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final emailQuery =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .where('role', isNotEqualTo: 'umpire')
              .limit(1)
              .get();

      if (emailQuery.docs.isNotEmpty) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Unauthorized Email'),
          description: const Text('Email is not authorized as umpire.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
        return;
      }

      if (phone.isNotEmpty) {
        final phoneQuery =
            await FirebaseFirestore.instance
                .collection('users')
                .where('phone', isEqualTo: phone)
                .where('role', isNotEqualTo: 'umpire')
                .limit(1)
                .get();

        if (phoneQuery.docs.isNotEmpty) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            title: const Text('Unauthorized Phone'),
            description: const Text('Phone is not authorized as umpire.'),
            autoCloseDuration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            alignment: Alignment.bottomCenter,
          );
          return;
        }
      }

      final tournamentDoc =
          await FirebaseFirestore.instance
              .collection('tournaments')
              .doc(widget.tournamentId)
              .get();
      final updatedMatches = List<Map<String, dynamic>>.from(
        tournamentDoc.data()!['matches'],
      );

      updatedMatches[widget.matchIndex] = {
        ..._match,
        'umpire': {'name': name, 'email': email, 'phone': phone},
      };

      final umpireQuery =
          await FirebaseFirestore.instance
              .collection('umpire_credentials')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

      if (umpireQuery.docs.isNotEmpty) {
        final umpireDocId = umpireQuery.docs.first.id;
        await FirebaseFirestore.instance
            .collection('umpire_credentials')
            .doc(umpireDocId)
            .update({
              'name': name,
              'phone': phone,
              'tournamentId': widget.tournamentId,
              'updatedAt': Timestamp.now(),
            });
      } else {
        final newUmpireDoc =
            FirebaseFirestore.instance.collection('umpire_credentials').doc();
        await newUmpireDoc.set({
          'uid': newUmpireDoc.id,
          'name': name,
          'email': email,
          'phone': phone,
          'tournamentId': widget.tournamentId,
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': updatedMatches});

      _initialUmpireName = name;
      _initialUmpireEmail = email;
      _initialUmpirePhone = phone;

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Umpire Details Saved'),
        description: const Text('Umpire details have been saved successfully.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      if (e.toString().contains('requires an index')) {
        debugPrint(
          '''Firestore index required. Create the following indexes in firestore.indexes.json:
{
  "indexes": [
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "email", "order": "ASCENDING" },
        { "fieldPath": "role", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "phone", "order": "ASCENDING" },
        { "fieldPath": "role", "order": "ASCENDING" }
      ]
    }
  ]
}
Then run: firebase deploy --only firestore:indexes
Error details: $e''',
        );
      }
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Save Failed'),
        description: Text('Failed to save umpire details: $e'),
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

  Future<void> _startMatch() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedMatches = List<Map<String, dynamic>>.from(
        (await FirebaseFirestore.instance
                .collection('tournaments')
                .doc(widget.tournamentId)
                .get())
            .data()!['matches'],
      );
      updatedMatches[widget.matchIndex] = {
        ..._match,
        'liveScores': {
          ..._match['liveScores'] ?? {},
          'isLive': true,
          'startTime': Timestamp.now(),
          'currentGame': 1,
          'currentServer': widget.isDoubles ? 'team1' : 'player1',
          widget.isDoubles ? 'team1' : 'player1': [0, 0, 0],
          widget.isDoubles ? 'team2' : 'player2': [0, 0, 0],
        },
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': updatedMatches});

      setState(() {
        _match = updatedMatches[widget.matchIndex];
        _initializeServer();
      });

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Match Started'),
        description: const Text('The match is now live.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Start Failed'),
        description: Text('Failed to start match: $e'),
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

  Future<void> _updateLiveScore(bool isTeam1, int gameIndex, int delta) async {
    if (_isLoading || !widget.isUmpire) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedMatches = List<Map<String, dynamic>>.from(
        (await FirebaseFirestore.instance
                .collection('tournaments')
                .doc(widget.tournamentId)
                .get())
            .data()!['matches'],
      );
      final currentScores = Map<String, dynamic>.from(_match['liveScores']);
      final key =
          isTeam1
              ? (widget.isDoubles ? 'team1' : 'player1')
              : (widget.isDoubles ? 'team2' : 'player2');
      final scores = List<int>.from(currentScores[key]);
      final newScore = (scores[gameIndex] + delta).clamp(0, 30);
      scores[gameIndex] = newScore;

      final newServer =
          isTeam1
              ? (widget.isDoubles ? 'team1' : 'player1')
              : (widget.isDoubles ? 'team2' : 'player2');
      updatedMatches[widget.matchIndex] = {
        ..._match,
        'liveScores': {
          ...currentScores,
          key: scores,
          'currentServer':
              newScore > scores[gameIndex]
                  ? newServer
                  : currentScores['currentServer'],
        },
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': updatedMatches});

      setState(() {
        _match = updatedMatches[widget.matchIndex];
        _lastTeam1Score = _getCurrentScore(true);
        _lastTeam2Score = _getCurrentScore(false);
        _initializeServer();
      });

      final team1Scores = List<int>.from(
        currentScores[widget.isDoubles ? 'team1' : 'player1'],
      );
      final team2Scores = List<int>.from(
        currentScores[widget.isDoubles ? 'team2' : 'player2'],
      );
      final currentSetScore =
          isTeam1 ? scores[gameIndex] : team1Scores[gameIndex];
      final opponentSetScore =
          isTeam1 ? team2Scores[gameIndex] : scores[gameIndex];

      if ((currentSetScore >= 21 &&
              (currentSetScore - opponentSetScore >= 2)) ||
          currentSetScore == 30) {
        await _advanceGame();
      }

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Score Updated'),
        description: const Text('Live score has been updated.'),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Update Failed'),
        description: Text('Failed to update score: $e'),
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

  Future<void> _advanceGame() async {
    if (_isLoading || !widget.isUmpire) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedMatches = List<Map<String, dynamic>>.from(
        (await FirebaseFirestore.instance
                .collection('tournaments')
                .doc(widget.tournamentId)
                .get())
            .data()!['matches'],
      );
      final currentGame = _match['liveScores']['currentGame'] as int;
      final team1Scores = List<int>.from(
        _match['liveScores'][widget.isDoubles ? 'team1' : 'player1'],
      );
      final team2Scores = List<int>.from(
        _match['liveScores'][widget.isDoubles ? 'team2' : 'player2'],
      );

      int team1Wins = 0;
      int team2Wins = 0;
      for (int i = 0; i < currentGame; i++) {
        if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
            team1Scores[i] == 30) {
          team1Wins++;
        } else if (team2Scores[i] >= 21 &&
                (team2Scores[i] - team1Scores[i]) >= 2 ||
            team2Scores[i] == 30) {
          team2Wins++;
        }
      }

      String? newServer;
      if (team1Scores[currentGame - 1] >= 21 &&
              (team1Scores[currentGame - 1] - team2Scores[currentGame - 1]) >=
                  2 ||
          team1Scores[currentGame - 1] == 30) {
        newServer = widget.isDoubles ? 'team1' : 'player1';
      } else if (team2Scores[currentGame - 1] >= 21 &&
              (team2Scores[currentGame - 1] - team1Scores[currentGame - 1]) >=
                  2 ||
          team2Scores[currentGame - 1] == 30) {
        newServer = widget.isDoubles ? 'team2' : 'player2';
      }

      String? winner;
      if (team1Wins >= 2) {
        winner = widget.isDoubles ? 'team1' : 'player1';
      } else if (team2Wins >= 2) {
        winner = widget.isDoubles ? 'team2' : 'player2';
      }

      if (winner != null) {
        List<String> winnerIds;
        if (widget.isDoubles) {
          winnerIds =
              winner == 'team1'
                  ? List<String>.from(_match['team1Ids'])
                  : List<String>.from(_match['team2Ids']);
        } else {
          winnerIds = [
            winner == 'player1' ? _match['player1Id'] : _match['player2Id'],
          ];
        }

        final updatedParticipants = List<Map<String, dynamic>>.from(
          (await FirebaseFirestore.instance
                  .collection('tournaments')
                  .doc(widget.tournamentId)
                  .get())
              .data()!['participants'],
        );
        final newParticipants =
            updatedParticipants.map((p) {
              final participantId = p['id'] as String;
              if (winnerIds.contains(participantId)) {
                final currentScore = p['score'] as int? ?? 0;
                return {...p, 'score': currentScore + 2};
              }
              return p;
            }).toList();

        updatedMatches[widget.matchIndex] = {
          ..._match,
          'completed': true,
          'winner': winner,
          'liveScores': {..._match['liveScores'], 'isLive': false},
        };

        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .update({
              'participants': newParticipants,
              'matches': updatedMatches,
            });

        setState(() {
          _match = updatedMatches[widget.matchIndex];
        });

        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Completed'),
          description: Text(
            'Winner: ${winner == 'team1' || winner == 'player1' ? (widget.isDoubles ? _match['team1'].join(', ') : _match['player1']) : (widget.isDoubles ? _match['team2'].join(', ') : _match['player2'])}',
          ),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      } else if (currentGame < 3) {
        updatedMatches[widget.matchIndex] = {
          ..._match,
          'liveScores': {
            ..._match['liveScores'],
            'currentGame': currentGame + 1,
            'currentServer': newServer ?? _match['liveScores']['currentServer'],
          },
        };

        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .update({'matches': updatedMatches});

        setState(() {
          _match = updatedMatches[widget.matchIndex];
          _initializeServer();
        });

        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Game Advanced'),
          description: const Text('Moved to the next game.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Advance Failed'),
        description: Text('Failed to advance game: $e'),
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

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    int? maxLength,
    bool isRequired = false,
    ValueChanged<String>? onChanged,
  }) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            maxLength: maxLength,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              label: RichText(
                text: TextSpan(
                  text: label,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  children:
                      isRequired
                          ? [
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ]
                          : [],
                ),
              ),
              hintText: isRequired ? 'Required' : null,
              hintStyle: GoogleFonts.poppins(
                color: Colors.white30,
                fontSize: 14,
              ),
              prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
              suffixIcon: suffixIcon,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Colors.cyanAccent,
                  width: 1.5,
                ),
              ),
              counterStyle: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
            ),
            onChanged: (value) {
              setState(() {});
              if (onChanged != null) {
                onChanged(value);
              }
            },
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
  }) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: GestureDetector(
            onTap: isLoading || onPressed == null ? null : onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              decoration: BoxDecoration(
                gradient:
                    isLoading || onPressed == null
                        ? LinearGradient(
                          colors: [Colors.grey.shade600, Colors.grey.shade700],
                        )
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
              child:
                  isLoading
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
                          color: Colors.white,
                        ),
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.cyanAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection({
    required String title,
    required List<Widget> children,
  }) {
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
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
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = _match['completed'] == true;
    final isLive = _match['liveScores']?['isLive'] == true;
    final currentGame = _match['liveScores']?['currentGame'] ?? 1;
    final team1Scores = List<int>.from(
      _match['liveScores']?[widget.isDoubles ? 'team1' : 'player1'] ??
          [0, 0, 0],
    );
    final team2Scores = List<int>.from(
      _match['liveScores']?[widget.isDoubles ? 'team2' : 'player2'] ??
          [0, 0, 0],
    );

    
    int team1Wins = 0;
    int team2Wins = 0;
    for (int i = 0; i < currentGame; i++) {
      if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
          team1Scores[i] == 30) {
        team1Wins++;
      } else if (team2Scores[i] >= 21 &&
              (team2Scores[i] - team1Scores[i]) >= 2 ||
          team2Scores[i] == 30) {
        team2Wins++;
      }
    }

    bool isCurrentSetComplete = false;
    if (currentGame <= 3) {
      final currentSetScore = team1Scores[currentGame - 1];
      isCurrentSetComplete =
          (currentSetScore >= 21 &&
              (currentSetScore - team2Scores[currentGame - 1] >= 2)) ||
          team1Scores[currentGame - 1] == 30 ||
          (team2Scores[currentGame - 1] >= 21 &&
              (team2Scores[currentGame - 1] - currentSetScore >= 2)) ||
          team2Scores[currentGame - 1] == 30;
    }

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
                  color: Colors.white70,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  widget.isDoubles
                      ? 'Team Match Details'
                      : 'Singles Match Details',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                actions: [
                  if (widget.isCreator && !isCompleted)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          widget.onDeleteMatch();
                          Navigator.pop(context);
                        }
                      },
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete Match',
                                style: GoogleFonts.poppins(
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                      icon: const Icon(Icons.more_vert, color: Colors.white70),
                    ),
                ],
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
                        childAnimationBuilder:
                            (child) => SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(child: child),
                            ),
                        children: [
                          _buildDetailSection(
                            title: 'Match Information',
                            children: [
                              _buildDetailRow(
                                icon: Icons.sports_tennis,
                                label: 'Round',
                                value: 'Round ${_match['round']}',
                              ),
                              _buildDetailRow(
                                icon: Icons.person,
                                label: widget.isDoubles ? 'Team 1' : 'Player 1',
                                value:
                                    widget.isDoubles
                                        ? _match['team1'].join(', ')
                                        : _match['player1'],
                              ),
                              _buildDetailRow(
                                icon: Icons.person,
                                label: widget.isDoubles ? 'Team 2' : 'Player 2',
                                value:
                                    widget.isDoubles
                                        ? _match['team2'].join(', ')
                                        : _match['player2'],
                              ),
                              if (_eventDate != null)
                                _buildDetailRow(
                                  icon: Icons.timer,
                                  label: 'Scheduled Start Time',
                                  value: DateFormat(
                                    'MMM dd, yyyy HH:mm',
                                  ).format(_eventDate!.toDate()),
                                ),
                              if (!isLive && !isCompleted)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _countdown ?? 'Start time not scheduled',
                                    style: GoogleFonts.poppins(
                                      color: Colors.cyanAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (widget.isCreator && !isLive && !isCompleted)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: _buildModernButton(
                                    text: 'Change Start Time',
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.blueAccent,
                                        Colors.cyanAccent,
                                      ],
                                    ),
                                    isLoading: _isLoading,
                                    onPressed: _updateEventDate,
                                  ),
                                ),
                              if (_match['umpire']?['name'] != null && isLive)
                                _buildDetailRow(
                                  icon: Icons.person,
                                  label: 'Umpire',
                                  value: _match['umpire']['name'],
                                ),
                              if (_match['umpire']?['email'] != null && isLive)
                                _buildDetailRow(
                                  icon: Icons.email,
                                  label: 'Umpire Email',
                                  value: _match['umpire']['email'],
                                ),
                              if (_match['umpire']?['phone'] != null && isLive)
                                _buildDetailRow(
                                  icon: Icons.phone,
                                  label: 'Umpire Phone',
                                  value: _match['umpire']['phone'],
                                ),
                              if (isCompleted)
                                _buildDetailRow(
                                  icon: Icons.emoji_events,
                                  label: 'Winner',
                                  value:
                                      _match['winner'] == 'team1' ||
                                              _match['winner'] == 'player1'
                                          ? (widget.isDoubles
                                              ? _match['team1'].join(', ')
                                              : _match['player1'])
                                          : (widget.isDoubles
                                              ? _match['team2'].join(', ')
                                              : _match['player2']),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (isLive)
                            _buildDetailSection(
                              title: 'Live Scores',
                              children: [
                                Text(
                                  'Game $currentGame',
                                  style: GoogleFonts.poppins(
                                    color: Colors.cyanAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.isDoubles
                                                ? _match['team1'].join(', ')
                                                : _match['player1'],
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          if (isLive &&
                                              _currentServer ==
                                                  (widget.isDoubles
                                                      ? 'team1'
                                                      : 'player1'))
                                            Flexible(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.sports_tennis,
                                                      size: 14,
                                                      color:
                                                          Colors.yellowAccent,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        'Serving (${_getServiceCourt(true)})',
                                                        style: GoogleFonts.poppins(
                                                          color:
                                                              Colors
                                                                  .yellowAccent,
                                                          fontSize:
                                                              MediaQuery.of(
                                                                        context,
                                                                      ).size.width <
                                                                      320
                                                                  ? 8
                                                                  : 10,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 120,
                                      alignment: Alignment.center,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Text(
                                            '${team1Scores[currentGame - 1]} - ${team2Scores[currentGame - 1]}',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (_showPlusOneTeam1)
                                            Positioned(
                                              left: 12,
                                              child: ScaleTransition(
                                                scale: _scaleAnimation,
                                                child: FadeTransition(
                                                  opacity: _fadeAnimation,
                                                  child: Text(
                                                    '+1',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.cyanAccent,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (_showPlusOneTeam2)
                                            Positioned(
                                              right: 12,
                                              child: ScaleTransition(
                                                scale: _scaleAnimation,
                                                child: FadeTransition(
                                                  opacity: _fadeAnimation,
                                                  child: Text(
                                                    '+1',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.cyanAccent,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.isDoubles
                                                ? _match['team2'].join(', ')
                                                : _match['player2'],
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          if (isLive &&
                                              _currentServer ==
                                                  (widget.isDoubles
                                                      ? 'team2'
                                                      : 'player2'))
                                            Flexible(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.sports_tennis,
                                                      size: 14,
                                                      color:
                                                          Colors.yellowAccent,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        'Serving (${_getServiceCourt(false)})',
                                                        style: GoogleFonts.poppins(
                                                          color:
                                                              Colors
                                                                  .yellowAccent,
                                                          fontSize:
                                                              MediaQuery.of(
                                                                        context,
                                                                      ).size.width <
                                                                      320
                                                                  ? 8
                                                                  : 10,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Sets: $team1Wins',
                                      style: GoogleFonts.poppins(
                                        color: Colors.cyanAccent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Sets: $team2Wins',
                                      style: GoogleFonts.poppins(
                                        color: Colors.cyanAccent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (widget.isUmpire &&
                                    !isCompleted &&
                                    !isCurrentSetComplete)
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 20),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _buildScoreButton(
                                            label: '+1',
                                            onPressed:
                                                () => _updateLiveScore(
                                                  true,
                                                  currentGame - 1,
                                                  1,
                                                ),
                                          ),
                                          _buildScoreButton(
                                            label: '-1',
                                            onPressed:
                                                () => _updateLiveScore(
                                                  true,
                                                  currentGame - 1,
                                                  -1,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _buildScoreButton(
                                            label: '+1',
                                            onPressed:
                                                () => _updateLiveScore(
                                                  false,
                                                  currentGame - 1,
                                                  1,
                                                ),
                                          ),
                                          _buildScoreButton(
                                            label: '-1',
                                            onPressed:
                                                () => _updateLiveScore(
                                                  false,
                                                  currentGame - 1,
                                                  -1,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 20),
                                Text(
                                  'Previous Games',
                                  style: GoogleFonts.poppins(
                                    color: Colors.cyanAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                ...List.generate(currentGame - 1, (index) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Game ${index + 1}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          '${team1Scores[index]} - ${team2Scores[index]}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          const SizedBox(height: 20),
                          if (!isLive && (widget.isCreator || widget.isUmpire))
                            _buildDetailSection(
                              title: 'Umpire Details',
                              children: [
                                _buildModernTextField(
                                  controller: _umpireNameController,
                                  label: 'Umpire Name',
                                  icon: Icons.person,
                                  keyboardType: TextInputType.name,
                                ),
                                const SizedBox(height: 16),
                                _buildModernTextField(
                                  controller: _umpireEmailController,
                                  label: 'Umpire Email',
                                  icon: Icons.email,
                                  keyboardType: TextInputType.emailAddress,
                                  isRequired: true,
                                  onChanged: (value) {
                                    _debounceTimer?.cancel();
                                    _debounceTimer = Timer(
                                      const Duration(milliseconds: 500),
                                      () {
                                        _fetchUserData(value.trim());
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildModernTextField(
                                  controller: _umpirePhoneController,
                                  label: 'Umpire Phone',
                                  icon: Icons.phone,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 12,
                                ),
                                const SizedBox(height: 20),
                                _buildModernButton(
                                  text:
                                      _isUmpireButtonDisabled
                                          ? 'Save Umpire Details'
                                          : 'Update Umpire Details',
                                  gradient: const LinearGradient(
                                    colors: [
                                      Colors.cyanAccent,
                                      Colors.blueAccent,
                                    ],
                                  ),
                                  isLoading: _isLoading,
                                  onPressed:
                                      _isUmpireButtonDisabled || isCompleted
                                          ? null
                                          : _updateUmpireDetails,
                                ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          if (widget.isUmpire && !isLive && !isCompleted)
                            _buildModernButton(
                              text: 'Start Match',
                              gradient: const LinearGradient(
                                colors: [Colors.greenAccent, Colors.green],
                              ),
                              isLoading: _isLoading,
                              onPressed: _startMatch,
                            ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
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
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}
