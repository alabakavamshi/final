import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

class MatchControlPage extends StatefulWidget {
  final String tournamentId;
  final Map<String, dynamic> match;
  final int matchIndex;
  final bool isDoubles;

  const MatchControlPage({
    super.key,
    required this.tournamentId,
    required this.match,
    required this.matchIndex,
    required this.isDoubles,
  });

  @override
  State<MatchControlPage> createState() => _MatchControlPageState();
}

class _MatchControlPageState extends State<MatchControlPage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late Map<String, dynamic> _match;
  String? _currentServer;
  String? _lastSetWinner;
  String? _lastServer;
  bool _isSetComplete = false;
  int? _lastTeam1Score;
  int? _lastTeam2Score;
  bool _showPlusOneTeam1 = false;
  bool _showPlusOneTeam2 = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timestamp? _eventDate;
  String? _countdownText;
  Timer? _countdownTimer;
  bool _canStartMatch = false;

  @override
  void initState() {
    super.initState();
    _match = Map.from(widget.match);
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
    _animationController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCountdown();
      } else {
        timer.cancel();
      }
    });
  }

  void _updateCountdown() {
    if (_eventDate == null) {
      setState(() {
        _countdownText = 'Start time not scheduled';
        _canStartMatch = true;
      });
      return;
    }

    final now = DateTime.now();
    final startTime = _eventDate!.toDate();
    final difference = startTime.difference(now);

    if (difference.isNegative) {
      setState(() {
        _countdownText = 'Match can start';
        _canStartMatch = true;
      });
    } else if (difference.inHours >= 24) {
      final days = difference.inDays;
      final hours = difference.inHours % 24;
      setState(() {
        _countdownText = '${days}d ${hours}h';
        _canStartMatch = false;
      });
    } else {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      final seconds = difference.inSeconds % 60;
      setState(() {
        _countdownText = '${hours}h ${minutes}m ${seconds}s';
        _canStartMatch = false;
      });
    }
  }

  int _getCurrentScore(bool isTeam1) {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
        liveScores[isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2')] ?? [0, 0, 0]);
    return scores[currentGame - 1];
  }

  void _initializeServer() {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final team1Scores = List<int>.from(
        liveScores[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0]);
    final team2Scores = List<int>.from(
        liveScores[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0]);
    
    if (!liveScores.containsKey('isLive') || !liveScores['isLive']) {
      _currentServer = widget.isDoubles ? 'team1' : 'player1';
      _lastServer = _currentServer;
    } else if (liveScores['currentServer'] != null) {
      _currentServer = liveScores['currentServer'];
      _lastServer = _currentServer;
    } else if (_lastSetWinner != null && team1Scores[currentGame - 1] == 0 && team2Scores[currentGame - 1] == 0) {
      _currentServer = _lastSetWinner;
      _lastServer = _currentServer;
    } else if (_lastTeam1Score != null && _lastTeam2Score != null) {
      if (team1Scores[currentGame - 1] > _lastTeam1Score!) {
        _currentServer = widget.isDoubles ? 'team1' : 'player1';
        _lastServer = _currentServer;
      } else if (team2Scores[currentGame - 1] > _lastTeam2Score!) {
        _currentServer = widget.isDoubles ? 'team2' : 'player2';
        _lastServer = _currentServer;
      } else {
        _currentServer = _lastServer ?? (widget.isDoubles ? 'team1' : 'player1');
      }
    } else {
      _currentServer = widget.isDoubles ? 'team1' : 'player1';
      _lastServer = _currentServer;
    }
  }

  void _listenToMatchUpdates() {
    FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data != null && mounted) {
        setState(() {
          _eventDate = data['eventDate'] as Timestamp?;
        });
        if (data['matches'] != null) {
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
              _lastTeam1Score = newTeam1Score;
              _lastTeam2Score = newTeam2Score;
              _checkSetCompletion();
              _initializeServer();
            });
          }
        }
      }
    });
  }

  int _getCurrentScoreFromMatch(Map<String, dynamic> match, bool isTeam1) {
    final liveScores = match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
        liveScores[isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2')] ?? [0, 0, 0]);
    return scores[currentGame - 1];
  }

  Future<void> _startMatch() async {
    if (_isLoading || !mounted || !_canStartMatch) {
      if (!_canStartMatch && mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.warning,
          title: const Text('Cannot Start Match'),
          description: const Text('Please wait until the scheduled start time.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      }
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final matches =
          List<Map<String, dynamic>>.from(tournamentDoc.data()!['matches']);
      matches[widget.matchIndex] = {
        ..._match,
        'liveScores': {
          'isLive': true,
          'startTime': Timestamp.now(),
          'currentGame': 1,
          widget.isDoubles ? 'team1' : 'player1': [0, 0, 0],
          widget.isDoubles ? 'team2' : 'player2': [0, 0, 0],
          'currentServer': widget.isDoubles ? 'team1' : 'player1',
        },
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': matches});

      setState(() {
        _match = matches[widget.matchIndex];
        _currentServer = widget.isDoubles ? 'team1' : 'player1';
        _lastServer = _currentServer;
      });

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Started'),
          description: const Text('The match has started successfully.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to start match: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
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

  Future<void> _updateLiveScore(bool isTeam1) async {
    if (_isLoading || !mounted || _isSetComplete) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final updatedMatches =
          List<Map<String, dynamic>>.from(tournamentDoc.data()!['matches']);
      final currentScores = Map<String, dynamic>.from(_match['liveScores']);
      final currentGame = currentScores['currentGame'] as int;
      final key =
          isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2');
      final opponentKey =
          !isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2');
      final scores = List<int>.from(currentScores[key]);
      final opponentScores = List<int>.from(currentScores[opponentKey]);
      scores[currentGame - 1]++;
      scores[currentGame - 1] = scores[currentGame - 1].clamp(0, 30);

      _lastTeam1Score = List<int>.from(currentScores[widget.isDoubles ? 'team1' : 'player1'])[currentGame - 1];
      _lastTeam2Score = List<int>.from(currentScores[widget.isDoubles ? 'team2' : 'player2'])[currentGame - 1];
      _currentServer = key;
      _lastServer = _currentServer;

      updatedMatches[widget.matchIndex] = {
        ..._match,
        'liveScores': {
          ...currentScores,
          key: scores,
          opponentKey: opponentScores,
          'currentServer': _currentServer,
        },
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': updatedMatches});

      setState(() {
        _match = updatedMatches[widget.matchIndex];
        _checkSetCompletion();
        _initializeServer();
      });

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Score Updated'),
          description: Text('Point for ${isTeam1 ? (widget.isDoubles ? _match['team1'].join(', ') : _match['player1']) : (widget.isDoubles ? _match['team2'].join(', ') : _match['player2'])}'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
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
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _decreaseScore(bool isTeam1) async {
    if (_isLoading || !mounted || _isSetComplete) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final updatedMatches =
          List<Map<String, dynamic>>.from(tournamentDoc.data()!['matches']);
      final currentScores = Map<String, dynamic>.from(_match['liveScores']);
      final currentGame = currentScores['currentGame'] as int;
      final key =
          isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2');
      final scores = List<int>.from(currentScores[key]);
      scores[currentGame - 1]--;
      scores[currentGame - 1] = scores[currentGame - 1].clamp(0, 30);

      _lastTeam1Score = List<int>.from(currentScores[widget.isDoubles ? 'team1' : 'player1'])[currentGame - 1];
      _lastTeam2Score = List<int>.from(currentScores[widget.isDoubles ? 'team2' : 'player2'])[currentGame - 1];
      _lastServer = _currentServer;

      updatedMatches[widget.matchIndex] = {
        ..._match,
        'liveScores': {
          ...currentScores,
          key: scores,
          'currentServer': _currentServer,
        },
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': updatedMatches});

      setState(() {
        _match = updatedMatches[widget.matchIndex];
        _checkSetCompletion();
        _initializeServer();
      });

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Score Adjusted'),
          description: Text('Score decreased for ${isTeam1 ? (widget.isDoubles ? _match['team1'].join(', ') : _match['player1']) : (widget.isDoubles ? _match['team2'].join(', ') : _match['player2'])}'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
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
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _checkSetCompletion() {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final team1Scores = List<int>.from(
        liveScores[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0]);
    final team2Scores = List<int>.from(
        liveScores[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0]);

    final currentSetScore = team1Scores[currentGame - 1];
    final opponentSetScore = team2Scores[currentGame - 1];
    if ((currentSetScore >= 21 && (currentSetScore - opponentSetScore >= 2)) ||
        currentSetScore == 30 ||
        (opponentSetScore >= 21 && (opponentSetScore - currentSetScore >= 2)) ||
        opponentSetScore == 30) {
      setState(() {
        _isSetComplete = true;
        _lastSetWinner = currentSetScore >= 21 && (currentSetScore - opponentSetScore >= 2) || currentSetScore == 30
            ? (widget.isDoubles ? 'team1' : 'player1')
            : (widget.isDoubles ? 'team2' : 'player2');
      });

      int team1Wins = 0;
      int team2Wins = 0;
      for (int i = 0; i < currentGame; i++) {
        if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
            team1Scores[i] == 30) {
          team1Wins++;
        } else if (team2Scores[i] >= 21 && (team2Scores[i] - team1Scores[i]) >= 2 ||
            team2Scores[i] == 30) {
          team2Wins++;
        }
      }
      if (team1Wins >= 2 || team2Wins >= 2) {
        _endMatch();
      }
    } else {
      setState(() {
        _isSetComplete = false;
      });
    }
  }

  Future<void> _startNextSet() async {
    if (_isLoading || !mounted || !_isSetComplete) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final updatedMatches =
          List<Map<String, dynamic>>.from(tournamentDoc.data()!['matches']);
      final currentScores = Map<String, dynamic>.from(_match['liveScores']);
      final currentGame = currentScores['currentGame'] as int;

      int team1Wins = 0;
      int team2Wins = 0;
      final team1Scores = List<int>.from(
          currentScores[widget.isDoubles ? 'team1' : 'player1']);
      final team2Scores = List<int>.from(
          currentScores[widget.isDoubles ? 'team2' : 'player2']);
      for (int i = 0; i < currentGame; i++) {
        if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
            team1Scores[i] == 30) {
          team1Wins++;
        } else if (team2Scores[i] >= 21 && (team2Scores[i] - team1Scores[i]) >= 2 ||
            team2Scores[i] == 30) {
          team2Wins++;
        }
      }

      if (team1Wins >= 2 || team2Wins >= 2 || currentGame >= 3) {
        await _endMatch();
        return;
      }

      team1Scores[currentGame] = 0;
      team2Scores[currentGame] = 0;

      updatedMatches[widget.matchIndex] = {
        ..._match,
        'liveScores': {
          ...currentScores,
          'currentGame': currentGame + 1,
          widget.isDoubles ? 'team1' : 'player1': team1Scores,
          widget.isDoubles ? 'team2' : 'player2': team2Scores,
          'currentServer': _lastSetWinner,
        },
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'matches': updatedMatches});

      setState(() {
        _match = updatedMatches[widget.matchIndex];
        _isSetComplete = false;
        _currentServer = _lastSetWinner;
        _lastServer = _currentServer;
      });

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Next Set Started'),
          description: Text('Set ${currentGame + 1} has begun.'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to start next set: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
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

  Future<void> _endMatch() async {
    if (_isLoading || !mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final updatedMatches =
          List<Map<String, dynamic>>.from(tournamentDoc.data()!['matches']);
      final currentScores = Map<String, dynamic>.from(_match['liveScores']);
      final currentGame = currentScores['currentGame'] as int;

      final team1Scores = List<int>.from(
          currentScores[widget.isDoubles ? 'team1' : 'player1']);
      final team2Scores = List<int>.from(
          currentScores[widget.isDoubles ? 'team2' : 'player2']);

      int team1Wins = 0;
      int team2Wins = 0;
      for (int i = 0; i < currentGame; i++) {
        if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
            team1Scores[i] == 30) {
          team1Wins++;
        } else if (team2Scores[i] >= 21 && (team2Scores[i] - team1Scores[i]) >= 2 ||
            team2Scores[i] == 30) {
          team2Wins++;
        }
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
          winnerIds = winner == 'team1'
              ? List<String>.from(_match['team1Ids'])
              : List<String>.from(_match['team2Ids']);
        } else {
          winnerIds = [
            winner == 'player1' ? _match['player1Id'] : _match['player2Id'],
          ];
        }

        final updatedParticipants = List<Map<String, dynamic>>.from(
            tournamentDoc.data()!['participants']);
        final newParticipants = updatedParticipants.map((p) {
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
          'liveScores': {...currentScores, 'isLive': false},
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

        if (mounted) {
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
        }
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to end match: $e'),
          autoCloseDuration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
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

  Widget _buildScoreButton({
    required String label,
    required VoidCallback onPressed,
    required bool isEnabled,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onPressed : null,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isEnabled
              ? Colors.cyanAccent.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.5),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: isEnabled ? Colors.cyanAccent : Colors.grey,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required String text,
    required LinearGradient gradient,
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                text,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  String _getServiceCourt(bool isTeam1) {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
        liveScores[isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2')] ?? [0, 0, 0]);
    return scores[currentGame - 1].isEven ? 'Right' : 'Left';
  }

  String? _getSetWinner(int setIndex) {
    final team1Scores = List<int>.from(
        _match['liveScores']?[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0]);
    final team2Scores = List<int>.from(
        _match['liveScores']?[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0]);
    if (team1Scores[setIndex] >= 21 && (team1Scores[setIndex] - team2Scores[setIndex]) >= 2 ||
        team1Scores[setIndex] == 30) {
      return widget.isDoubles ? _match['team1'].join(', ') : _match['player1'];
    } else if (team2Scores[setIndex] >= 21 && (team2Scores[setIndex] - team1Scores[setIndex]) >= 2 ||
        team2Scores[setIndex] == 30) {
      return widget.isDoubles ? _match['team2'].join(', ') : _match['player2'];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = _match['completed'] == true;
    final isLive = _match['liveScores']?['isLive'] == true;
    final currentGame = _match['liveScores']?['currentGame'] ?? 1;
    final team1Scores = List<int>.from(
        _match['liveScores']?[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0]);
    final team2Scores = List<int>.from(
        _match['liveScores']?[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0]);

    int team1Wins = 0;
    int team2Wins = 0;
    for (int i = 0; i < currentGame; i++) {
      if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
          team1Scores[i] == 30) {
        team1Wins++;
      } else if (team2Scores[i] >= 21 && (team2Scores[i] - team1Scores[i]) >= 2 ||
          team2Scores[i] == 30) {
        team2Wins++;
      }
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
          child: Column(
            children: [
              // Header: Match Info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Round ${_match['round']}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_match['startTime'] != null)
                            Text(
                              DateFormat('MMM dd, yyyy HH:mm').format(
                                  (_match['startTime'] as Timestamp).toDate()),
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Main Score Display
              Expanded(
                child: AnimationConfiguration.synchronized(
                  duration: const Duration(milliseconds: 1000),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Player and Score Row
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            // Player 1 / Team 1
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.isDoubles
                                            ? _match['team1'].join(', ')
                                            : _match['player1'],
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (isLive && _currentServer == (widget.isDoubles ? 'team1' : 'player1'))
                                      Flexible(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.sports_tennis,
                                              size: 16,
                                              color: Colors.yellowAccent,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'Serving (${_getServiceCourt(true)})',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.yellowAccent,
                                                  fontSize: MediaQuery.of(context).size.width < 360 ? 10 : 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            // Scores
                            Expanded(
                              flex: 3,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Set $currentGame',
                                    style: GoogleFonts.poppins(
                                      color: Colors.cyanAccent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${team1Scores[currentGame - 1]}',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: MediaQuery.of(context).size.width < 360 ? 40 : 48,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            ' - ',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white70,
                                              fontSize: MediaQuery.of(context).size.width < 360 ? 24 : 32,
                                            ),
                                          ),
                                          Text(
                                            '${team2Scores[currentGame - 1]}',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: MediaQuery.of(context).size.width < 360 ? 40 : 48,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_showPlusOneTeam1)
                                        Positioned(
                                          left: 10,
                                          child: ScaleTransition(
                                            scale: _scaleAnimation,
                                            child: FadeTransition(
                                              opacity: _fadeAnimation,
                                              child: Text(
                                                '+1',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.cyanAccent,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_showPlusOneTeam2)
                                        Positioned(
                                          right: 10,
                                          child: ScaleTransition(
                                            scale: _scaleAnimation,
                                            child: FadeTransition(
                                              opacity: _fadeAnimation,
                                              child: Text(
                                                '+1',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.cyanAccent,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.cyanAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$team1Wins',
                                          style: GoogleFonts.poppins(
                                            color: Colors.cyanAccent,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.cyanAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$team2Wins',
                                          style: GoogleFonts.poppins(
                                            color: Colors.cyanAccent,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Player 2 / Team 2
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.isDoubles
                                            ? _match['team2'].join(', ')
                                            : _match['player2'],
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (isLive && _currentServer == (widget.isDoubles ? 'team2' : 'player2'))
                                      Flexible(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.sports_tennis,
                                              size: 16,
                                              color: Colors.yellowAccent,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'Serving (${_getServiceCourt(false)})',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.yellowAccent,
                                                  fontSize: MediaQuery.of(context).size.width < 360 ? 10 : 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Previous Sets and Results
                      if (currentGame > 1 || isCompleted)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: List.generate(currentGame - 1, (index) {
                              final winner = _getSetWinner(index);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  children: [
                                    Text(
                                      'Set ${index + 1}: ${team1Scores[index]} - ${team2Scores[index]}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (winner != null)
                                      Text(
                                        'Set ${index + 1} won by $winner (${team1Scores[index]}-${team2Scores[index]})',
                                        style: GoogleFonts.poppins(
                                          color: Colors.greenAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      // Controls
                      if (!isCompleted)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: (!isLive)
                              ? Column(
                                  children: [
                                    if (_countdownText != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Text(
                                          'Countdown: $_countdownText',
                                          style: GoogleFonts.poppins(
                                            color: Colors.cyanAccent,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    _buildModernButton(
                                      text: _isLoading ? 'Starting...' : 'Start Match',
                                      gradient: const LinearGradient(
                                        colors: [Colors.greenAccent, Colors.green],
                                      ),
                                      onPressed: _startMatch,
                                      isLoading: _isLoading,
                                    ),
                                  ],
                                )
                              : (_isSetComplete
                                  ? Column(
                                      children: [
                                        Text(
                                          'Set $currentGame completed. Start Set ${currentGame + 1 <= 3 ? currentGame + 1 : ''} or end match?',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 16),
                                        if (currentGame < 3)
                                          _buildModernButton(
                                            text: _isLoading ? 'Starting...' : 'Start Set ${currentGame + 1}',
                                            gradient: const LinearGradient(
                                              colors: [Colors.blueAccent, Colors.cyanAccent],
                                            ),
                                            onPressed: _startNextSet,
                                            isLoading: _isLoading,
                                          ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        // Team 1 Controls
                                        Column(
                                          children: [
                                            _buildScoreButton(
                                              label: '+1',
                                              onPressed: () => _updateLiveScore(true),
                                              isEnabled: true,
                                            ),
                                            const SizedBox(height: 8),
                                            _buildScoreButton(
                                              label: '-1',
                                              onPressed: () => _decreaseScore(true),
                                              isEnabled: team1Scores[currentGame - 1] > 0,
                                            ),
                                          ],
                                        ),
                                        // Team 2 Controls
                                        Column(
                                          children: [
                                            _buildScoreButton(
                                              label: '+1',
                                              onPressed: () => _updateLiveScore(false),
                                              isEnabled: true,
                                            ),
                                            const SizedBox(height: 8),
                                            _buildScoreButton(
                                              label: '-1',
                                              onPressed: () => _decreaseScore(false),
                                              isEnabled: team2Scores[currentGame - 1] > 0,
                                            ),
                                          ],
                                        ),
                                      ],
                                    )),
                        ),
                      // Winner Display
                      if (isCompleted)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Winner: ${_match['winner'] == 'team1' || _match['winner'] == 'player1' ? (widget.isDoubles ? _match['team1'].join(', ') : _match['player1']) : (widget.isDoubles ? _match['team2'].join(', ') : _match['player2'])}',
                            style: GoogleFonts.poppins(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
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
}