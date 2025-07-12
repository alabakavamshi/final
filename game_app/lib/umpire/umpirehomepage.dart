import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/screens/auth_page.dart';
import 'package:game_app/screens/player_profile.dart';
import 'package:game_app/umpire/umpire_matches.dart';
import 'package:game_app/umpire/umpire_schedule.dart';
import 'package:game_app/umpire/umpire_stats.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:toastification/toastification.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class StringExtension {
  StringExtension(this.value);
  final String value;

  String capitalize() {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }
}

class UmpireHomePage extends StatefulWidget {
  const UmpireHomePage({super.key});

  @override
  State<UmpireHomePage> createState() => _UmpireHomePageState();
}

class _UmpireHomePageState extends State<UmpireHomePage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _location = 'Hyderabad, India';
  String _userCity = 'hyderabad';
  bool _isLoadingLocation = false;
  bool _locationFetchCompleted = false;
  Position? _lastPosition;
  final TextEditingController _locationController = TextEditingController();
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;
  bool _showToast = false;
  String? _toastMessage;
  ToastificationType? _toastType;
  bool _hasNavigated = false;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _upcomingMatches = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeUserData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(authState.user.uid);
        userDocRef.get().then((userDoc) {
          if (userDoc.exists && userDoc.data()?['city']?.toString().isNotEmpty == true) {
            if (mounted) {
              setState(() {
                _userCity = userDoc.data()!['city'].toString().toLowerCase();
                _location = '${StringExtension(_userCity).capitalize()}, India';
                _locationFetchCompleted = true;
                _isLoadingLocation = false;
              });
            }
          } else if (!kIsWeb) {
            _getUserLocation();
          } else {
            if (mounted) {
              setState(() {
                _location = 'Hyderabad, India';
                _userCity = 'hyderabad';
                _locationFetchCompleted = true;
                _isLoadingLocation = false;
              });
            }
          }
        });
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOutQuint),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
    );
    _animationController?.forward();
  }

  Future<void> _initializeUserData() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(authState.user.uid);
    final userDoc = await userDocRef.get();

    final defaultUser = {
      'createdAt': Timestamp.now(),
      'displayName': authState.user.email?.split('@')[0] ?? 'Umpire',
      'email': authState.user.email ?? '',
      'firstName': 'Umpire',
      'lastName': '',
      'gender': 'unknown',
      'phone': '',
      'profileImage': '',
      'city': _userCity.isNotEmpty ? _userCity : 'hyderabad',
      'updatedAt': Timestamp.now(),
    };

    if (!userDoc.exists) {
      await userDocRef.set(defaultUser);
      if (mounted) {
        setState(() => _userData = defaultUser);
      }
    } else {
      if (mounted) {
        setState(() => _userData = userDoc.data() ?? defaultUser);
      }
    }
  }

  Stream<Map<String, dynamic>?> _userDataStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Stream.value(null);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(authState.user.uid)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  Stream<List<Map<String, dynamic>>> _upcomingMatchesStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      debugPrint('No authenticated user found');
      return Stream.value([]);
    }

    final umpireEmail = authState.user.email?.toLowerCase().trim();
    debugPrint('Authenticated umpire email: $umpireEmail');

    return FirebaseFirestore.instance
        .collection('tournaments')
        .snapshots()
        .map((querySnapshot) {
      List<Map<String, dynamic>> upcomingMatches = [];
      final now = DateTime.now();
      debugPrint('Fetched ${querySnapshot.docs.length} tournaments');

      for (var tournamentDoc in querySnapshot.docs) {
        final tournamentData = tournamentDoc.data();
        final matches = tournamentData['matches'] as List<dynamic>? ?? [];
        debugPrint('Tournament ${tournamentDoc.id}: ${matches.length} matches');

        for (var match in matches) {
          try {
            final matchData = match as Map<String, dynamic>;
            if (matchData['completed'] == true) {
              debugPrint('Skipping completed match: ${matchData['matchId']}');
              continue;
            }

            String? matchUmpireEmail;
            if (matchData['umpire'] is Map<String, dynamic>?) {
              final matchUmpire = matchData['umpire'] as Map<String, dynamic>?;
              matchUmpireEmail = (matchUmpire?['email'] as String?)?.toLowerCase().trim();
            } else if (matchData['umpireEmail'] is String?) {
              matchUmpireEmail = (matchData['umpireEmail'] as String?)?.toLowerCase().trim();
            }

            if (matchUmpireEmail == null) {
              debugPrint('No umpire assigned for match: ${matchData['matchId']}');
              continue;
            }

            if (matchUmpireEmail != umpireEmail) {
              debugPrint('Match ${matchData['matchId']} assigned to different umpire: $matchUmpireEmail');
              continue;
            }

            final matchStartTime = matchData['startTime'] as Timestamp?;
            if (matchStartTime == null) {
              debugPrint('No startTime for match: ${matchData['matchId']}');
              continue;
            }

            final matchTime = matchStartTime.toDate();
            final isLive = (matchData['liveScores'] as Map<String, dynamic>?)?['isLive'] == true;
            final status = isLive
                ? 'LIVE'
                : matchTime.isAfter(now)
                    ? 'SCHEDULED'
                    : 'PAST';

            debugPrint('Processing match: ${matchData['matchId']}, isLive: $isLive, startTime: $matchTime, status: $status');
            upcomingMatches.add({
              'id': matchData['matchId'] as String? ?? 'match_${tournamentDoc.id}_${matches.indexOf(match)}',
              'tournamentId': tournamentDoc.id,
              'name': '${tournamentData['name'] as String? ?? 'Tournament'} - ${matchData['matchId'] ?? 'Match ${matches.indexOf(match) + 1}'}',
              'startDate': matchStartTime,
              'location': (tournamentData['venue'] as String?)?.isNotEmpty == true && (tournamentData['city'] as String?)?.isNotEmpty == true
                  ? '${tournamentData['venue']}, ${tournamentData['city']}'
                  : tournamentData['city'] as String? ?? 'Unknown venue',
              'status': status,
              'player1Id': matchData['player1Id'] as String? ?? 'Unknown',
              'player2Id': matchData['player2Id'] as String? ?? 'Unknown',
              'isDoubles': matchData['isDoubles'] ?? false,
              'tournamentName': tournamentData['name'] as String? ?? 'Unknown Tournament',
            });
          } catch (e) {
            debugPrint('[ERROR] Processing match in stream: $e');
          }
        }
      }
      debugPrint('Upcoming matches count: ${upcomingMatches.length}');
      return upcomingMatches.take(5).toList();
    });
  }

  Future<List<Map<String, String>>> _fetchPlayerNames(List<Map<String, dynamic>> matches) async {
    final List<Map<String, String>> playerNames = [];
    final Set<String> uniqueIds = {};

    for (var match in matches) {
      final player1Id = match['player1Id'] as String?;
      final player2Id = match['player2Id'] as String?;
      if (player1Id != null && player1Id != 'Unknown') uniqueIds.add(player1Id);
      if (player2Id != null && player2Id != 'Unknown') uniqueIds.add(player2Id);
    }

    if (uniqueIds.isEmpty) {
      debugPrint('No unique player IDs to fetch');
      return playerNames;
    }

    debugPrint('Fetching player names for IDs: $uniqueIds');
    final userDocs = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: uniqueIds.toList())
        .get();

    for (var doc in userDocs.docs) {
      final data = doc.data();
      final name = '${data['firstName'] ?? 'Unknown'} ${data['lastName'] ?? ''}'.trim();
      playerNames.add({
        'id': doc.id,
        'name': name.isEmpty ? 'Unknown Player' : name,
      });
      debugPrint('Fetched player: ${doc.id} - $name');
    }

    return playerNames;
  }

  Color _getMatchStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SCHEDULED':
        return Colors.blueAccent;
      case 'LIVE':
        return Colors.greenAccent;
      case 'PAST':
        return Colors.grey;
      case 'COMPLETED':
        return Colors.purpleAccent;
      case 'CANCELLED':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    if (!mounted || kIsWeb) return;

    setState(() {
      _isLoadingLocation = true;
      _locationFetchCompleted = false;
    });

    try {
      if (_lastPosition == null) {
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _lastPosition = lastPosition;
          await _updateLocationFromPosition(lastPosition);
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationServiceDisabled();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _handlePermissionDenied();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _handlePermissionDeniedForever();
        return;
      }

      Position? position;
      bool success = false;
      int attempts = 0;
      const int maxAttempts = 3;

      while (!success && attempts < maxAttempts) {
        attempts++;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          success = true;
        } on TimeoutException {
          if (attempts == maxAttempts) {
            throw TimeoutException('Location fetch timed out after $maxAttempts attempts');
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (position != null) {
        _lastPosition = position;
        await _updateLocationFromPosition(position);
      } else {
        throw Exception('Failed to get location after $maxAttempts attempts');
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .update({'city': _userCity});
      }

      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Location updated to $_location';
          _toastType = ToastificationType.success;
        });
      }
    } on TimeoutException {
      _handleLocationTimeout();
    } catch (e) {
      _handleLocationError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationFetchCompleted = true;
        });
      }
    }
  }

  Future<void> _updateLocationFromPosition(Position position) async {
    if (!mounted) return;

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        if (mounted) {
          setState(() {
            _location = '${place.locality ?? 'Hyderabad'}, ${place.country ?? 'India'}';
            _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
          });
        }
        return;
      }

      final fallbackPlacemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 3));

      if (fallbackPlacemarks.isNotEmpty) {
        final place = fallbackPlacemarks.first;
        if (mounted) {
          setState(() {
            _location = '${place.locality ?? 'Hyderabad'}, ${place.country ?? 'India'}';
            _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
        });
      }
    }
  }

  Future<void> _handleLocationServiceDisabled() async {
    if (!mounted) return;

    final opened = await Geolocator.openLocationSettings();
    if (opened) {
      await Future.delayed(const Duration(seconds: 2));
      await _getUserLocation();
    } else {
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
          _showToast = true;
          _toastMessage = 'Please enable location services manually.';
          _toastType = ToastificationType.warning;
        });
      }
    }
  }

  void _handlePermissionDenied() {
    if (!mounted) return;
    _showPermissionDeniedDialog();
  }

  void _handlePermissionDeniedForever() {
    if (!mounted) return;
    _showPermissionDeniedForeverDialog();
  }

  void _handleLocationTimeout() {
    if (mounted) {
      setState(() {
        _location = 'Hyderabad, India';
        _userCity = 'hyderabad';
        _showToast = true;
        _toastMessage = 'Could not fetch location quickly. Using default: Hyderabad.';
        _toastType = ToastificationType.warning;
      });
    }
  }

  void _handleLocationError(dynamic e) {
    debugPrint('Location error: $e');
    if (mounted) {
      setState(() {
        _location = 'Hyderabad, India';
        _userCity = 'hyderabad';
        _showToast = true;
        _toastMessage = 'Failed to fetch location: ${e.toString()}. Using default: Hyderabad.';
        _toastType = ToastificationType.error;
      });
    }
  }

  Future<void> _getUserLocationFromCurrent() async {
    if (!mounted || kIsWeb) return;

    setState(() {
      _isLoadingLocation = true;
      _locationFetchCompleted = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationServiceDisabled();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionDeniedDialog();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showPermissionDeniedForeverDialog();
        return;
      }

      Position? position;
      bool success = false;
      int attempts = 0;
      const int maxAttempts = 3;

      while (!success && attempts < maxAttempts) {
        attempts++;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          success = true;
        } on TimeoutException {
          if (attempts == maxAttempts) {
            throw TimeoutException('Location fetch timed out after $maxAttempts attempts');
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (position != null) {
        _lastPosition = position;
        await _updateLocationFromPosition(position);
      } else {
        throw Exception('Failed to get location after $maxAttempts attempts');
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .update({'city': _userCity});
      }

      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Location updated to $_location';
          _toastType = ToastificationType.success;
        });
      }
    } on TimeoutException {
      _handleLocationTimeout();
    } catch (e) {
      _handleLocationError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationFetchCompleted = true;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (!mounted) return;

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Please enter a location';
          _toastType = ToastificationType.error;
        });
      }
      return;
    }

    try {
      final locations = await locationFromAddress(query).timeout(const Duration(seconds: 5));
      if (locations.isEmpty) {
        throw Exception('No locations found for "$query"');
      }

      final location = locations.first;
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 3));

      if (placemarks.isEmpty) {
        throw Exception('No placemarks found');
      }

      final place = placemarks.first;
      if (mounted) {
        setState(() {
          _location = '${place.locality ?? 'Hyderabad'}, ${place.country ?? 'India'}';
          _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
        });
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .update({'city': _userCity});
      }

      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Location updated to $_location';
          _toastType = ToastificationType.success;
        });
      }
    } catch (e) {
      debugPrint('Search location error: $e');
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
          _showToast = true;
          _toastMessage = 'Failed to find location: ${e.toString()}. Using default: Hyderabad.';
          _toastType = ToastificationType.error;
        });
      }
    }
  }

  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ScaleTransition(
          scale: _scaleAnimation!,
          child: FadeTransition(
            opacity: _fadeAnimation!,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D1B2A), Color(0xFF1A1A1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withOpacity(0.7),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 5,
                  ),
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Confirm Logout',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      shadows: [
                        Shadow(
                          color: const Color(0xFF00D4FF).withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Are you sure you want to logout?',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          backgroundColor: Colors.white10,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
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
    );
  }

  void _showPermissionDeniedDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Location Permission Denied',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This app needs location permission to fetch your current location. Please enable it in settings.',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: Text('Enable', style: GoogleFonts.poppins(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedForeverDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Location Permission Denied Forever',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Location permission has been permanently denied. You can enable it in app settings.',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: Text('Enable', style: GoogleFonts.poppins(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserWelcomeCard() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _userDataStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _userData == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading user data',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        _userData = snapshot.data ?? _userData;
        if (_userData == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final displayName = _userData!['firstName']?.toString().isNotEmpty == true
            ? '${StringExtension(_userData!['firstName'].toString()).capitalize()} ${_userData!['lastName']?.toString().isNotEmpty == true ? StringExtension(_userData!['lastName'].toString()).capitalize() : ''}'
            : 'Umpire';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3A506B), Color(0xFF1C2541)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome Back,',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayName,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _upcomingMatchesStream(),
                      builder: (context, matchesSnapshot) {
                        if (matchesSnapshot.hasData) {
                          _upcomingMatches = matchesSnapshot.data!;
                        }
                        return Row(
                          children: [
                            const Icon(Icons.sports_tennis, size: 16, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              '${_upcomingMatches.length} Upcoming Matches',
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _selectedIndex = 2),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  backgroundImage: _userData!['profileImage']?.toString().isNotEmpty == true
                      ? CachedNetworkImageProvider(_userData!['profileImage'])
                      : const AssetImage('assets/default_profile.png') as ImageProvider,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpcomingMatches() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _upcomingMatchesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint('Snapshot error: ${snapshot.error}');
          return const Center(child: Text('Error loading matches', style: TextStyle(color: Colors.red)));
        }
        _upcomingMatches = snapshot.data ?? [];
        debugPrint('Upcoming matches: $_upcomingMatches');

        return FutureBuilder<List<Map<String, String>>>(
          future: _fetchPlayerNames(_upcomingMatches),
          builder: (context, playerNamesSnapshot) {
            if (playerNamesSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (playerNamesSnapshot.hasError || !playerNamesSnapshot.hasData) {
              debugPrint('Player names error: ${playerNamesSnapshot.error}');
              return const Center(child: Text('Error loading player names', style: TextStyle(color: Colors.red)));
            }

            final playerNames = playerNamesSnapshot.data ?? [];
            final playerNameMap = {for (var p in playerNames) p['id']!: p['name']!};
            debugPrint('Player name map: $playerNameMap');

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Upcoming Matches', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Icon(Icons.sports_tennis, color: Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_upcomingMatches.isEmpty)
                    Column(
                      children: [
                        Text('No matches assigned', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() => _selectedIndex = 1),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: Text('View Matches', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    )
                  else
                    ..._upcomingMatches.map((match) {
                      final startDate = (match['startDate'] as Timestamp).toDate();
                      final player1Id = match['player1Id'] as String?;
                      final player2Id = match['player2Id'] as String?;
                      final player1Name = playerNameMap[player1Id] ?? player1Id ?? 'Unknown Player';
                      final player2Name = playerNameMap[player2Id] ?? player2Id ?? 'Unknown Player';
                      final tournamentName = match['tournamentName'] as String? ?? 'Unknown Tournament';
                      debugPrint('Match: $match, Player1: $player1Name, Player2: $player2Name, Tournament: $tournamentName');

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MatchDetailsPage(
                                matchId: match['id'],
                                tournamentId: match['tournamentId'],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: _getMatchStatusColor(match['status']), borderRadius: BorderRadius.circular(8)),
                                    child: Column(
                                      children: [
                                        Text('Date', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
                                        Text(DateFormat('MMM').format(startDate).toUpperCase(), style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text(DateFormat('dd').format(startDate), style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(

                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(tournamentName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on, size: 14, color: Colors.white70),
                                            const SizedBox(width: 4),
                                            Text(
                                              match['location'] as String,
                                              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          match['isDoubles'] ? 'Doubles' : 'Singles',
                                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              player1Name,
                                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'vs',
                                              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                player2Name,
                                                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        
                                      ],
                                    ),

                                  ),
                                  Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _getMatchStatusColor(match['status']).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            match['status'].toUpperCase(),
                                            style: GoogleFonts.poppins(
                                              color: _getMatchStatusColor(match['status']),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickActionButton(
                icon: Icons.sports_tennis,
                label: 'Matches',
                color: Colors.blueAccent,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _buildQuickActionButton(
                icon: Icons.schedule,
                label: 'Schedule',
                color: Colors.greenAccent,
                onTap: () async {
                  final authState = context.read<AuthBloc>().state;
                  if (authState is AuthAuthenticated) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UmpireSchedulePage(
                          userId: authState.user.uid,
                          userEmail: authState.user.email ?? '',
                        ),
                      ),
                    );
                  }
                },
              ),
              _buildQuickActionButton(
                icon: Icons.bar_chart,
                label: 'Stats',
                color: Colors.purpleAccent,
                onTap: () async {
                  final authState = context.read<AuthBloc>().state;
                  if (authState is AuthAuthenticated) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UmpireStatsPage(
                          userId: authState.user.uid,
                          userEmail: authState.user.email ?? '',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationSearchDialog() {
    _locationController.clear();
    _animationController?.forward();

    showDialog(
      context: context,
      builder: (context) {
        Widget dialogContent = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1B263B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Location',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _getUserLocationFromCurrent();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Use Current Location',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      if (_isLoadingLocation)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.2), height: 1),
              const SizedBox(height: 16),
              Text(
                'Or search for a location',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                style: GoogleFonts.poppins(color: Colors.white),
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: 'Enter city name',
                  hintStyle: GoogleFonts.poppins(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_locationController.text.isNotEmpty) {
                          _searchLocation(_locationController.text);
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Search',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        if (_scaleAnimation != null && _fadeAnimation != null) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: ScaleTransition(
              scale: _scaleAnimation!,
              child: FadeTransition(
                opacity: _fadeAnimation!,
                child: dialogContent,
              ),
            ),
          );
        }
        return Dialog(
          backgroundColor: Colors.transparent,
          child: dialogContent,
        );
      },
    );
  }

  void _onItemTapped(int index) {
    if (index < 0 || index >= 3) {
      debugPrint('Invalid index: $index');
      return;
    }
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
    debugPrint('Selected tab: $index');
  }

  @override
  Widget build(BuildContext context) {
    if (_showToast && _toastMessage != null && _toastType != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastification.show(
          context: context,
          type: _toastType!,
          title: Text(
            _toastType == ToastificationType.success
                ? 'Success'
                : _toastType == ToastificationType.error
                    ? 'Error'
                    : 'Info',
          ),
          description: Text(_toastMessage!),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor: _toastType == ToastificationType.success
              ? Colors.green
              : _toastType == ToastificationType.error
              ? Colors.red
              : Colors.blue,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
        if (mounted) {
          setState(() {
            _showToast = false;
            _toastMessage = null;
            _toastType = null;
          });
        }
      });
    }

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        debugPrint('UmpireHomePage Auth state: $state');
        if (state is AuthUnauthenticated && mounted && !_hasNavigated) {
          _hasNavigated = true;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthPage()),
            (route) => false,
          );
          debugPrint('Navigated to AuthPage due to unauthenticated state');
        } else if (state is AuthError && mounted) {
          setState(() {
            _showToast = true;
            _toastMessage = state.message;
            _toastType = ToastificationType.error;
          });
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          debugPrint('Building UmpireHomePage with state: $state');
          if (state is AuthUnauthenticated) {
            return const AuthPage();
          }

          if (state is AuthLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFF0D1B2A),
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            );
          }

          final List<Widget> pages = [
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildUserWelcomeCard(),
                  _buildQuickActions(),
                  _buildUpcomingMatches(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            const UmpireMatchesPage(),
            const PlayerProfilePage(),
          ];

          return WillPopScope(
            onWillPop: () async {
              if (_selectedIndex != 0) {
                if (mounted) {
                  setState(() => _selectedIndex = 0);
                }
                return false;
              }
              return true;
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0D1B2A),
              appBar: _selectedIndex != 2
                  ? AppBar(
                      elevation: 0,
                      toolbarHeight: 80,
                      flexibleSpace: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF3A506B), Color(0xFF1C2541)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SmashLive',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              color: Colors.white,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _showLocationSearchDialog,
                            child: Row(
                              children: [
                                const Icon(Icons.location_pin, color: Colors.white70, size: 18),
                                const SizedBox(width: 8),
                                _isLoadingLocation && !_locationFetchCompleted
                                    ? const SizedBox(
                                        width: 100,
                                        height: 20,
                                        child: Center(
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Flexible(
                                        child: Text(
                                          _location,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white10,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              state is AuthAuthenticated ? Icons.logout : Icons.login,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          onPressed: () async {
                            if (state is AuthAuthenticated && mounted) {
                              final shouldLogout = await _showLogoutConfirmationDialog();
                              if (shouldLogout == true) {
                                context.read<AuthBloc>().add(AuthLogoutEvent());
                                setState(() {
                                  _showToast = true;
                                  _toastMessage = 'You have been logged out successfully.';
                                  _toastType = ToastificationType.success;
                                });
                                debugPrint('User logged out');
                              }
                            } else if (mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const AuthPage()),
                                (route) => false,
                              );
                            }
                          },
                        ),
                      ],
                    )
                  : null,
              body: pages[_selectedIndex],
              bottomNavigationBar: BottomNavigationBar(
                backgroundColor: const Color(0xFF2A324B),
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white.withOpacity(0.6),
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                unselectedLabelStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_filled),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.sports_tennis_outlined),
                    activeIcon: Icon(Icons.sports_tennis),
                    label: 'Matches',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MatchDetailsPage extends StatelessWidget {
  final String matchId;
  final String tournamentId;

  const MatchDetailsPage({super.key, required this.matchId, required this.tournamentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Match Details',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D1B2A),
      ),
      body: Center(
        child: Text(
          'Match ID: $matchId\nTournament ID: $tournamentId',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
      ),
    );
  }
}